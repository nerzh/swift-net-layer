# SwiftNetLayer

A Swift library for describing HTTP APIs as resources, targets, and requests.

- **Resource** — the API host and shared settings: headers, query parameters, provider, and request limits.
- **Target** — a path template and methods that describe requests to that endpoint.
- **Executor** — a prepared request that you can execute with async/await or a callback.

## Basic example

This example describes a fictional users API at `https://api.example.com/v1`. Define the models and target first, then connect them to a resource:

```text
ExampleApi/
  UserModels.swift
  UsersTarget.swift
  ExampleApi.swift
  ExampleApi+Users.swift
```

### 1. Models — `UserModels.swift`

`User` describes the response JSON. `CreateUserBody` describes the JSON sent when creating a user.

```swift
struct User: Decodable, Sendable {
    let id: Int
    let name: String
}

struct CreateUserBody: Encodable, Sendable {
    let name: String
}
```

### 2. Requests — `UsersTarget.swift`

Each method returns an executor. Preparing a request does not send it; the caller chooses how to execute it and whether to decode the response.

```swift
import SwiftNetLayer

final class UsersTarget: SNLTarget {
    func list(page: Int = 1) -> SNLExecutorPrtcl {
        makeExecutor(
            target: self,
            resource: resource,
            method: .get,
            requestParams: ["page": page]
        )
    }

    func get(id: Int) -> SNLExecutorPrtcl {
        makeExecutor(
            target: self,
            resource: resource,
            method: .get,
            pathParams: ["id": String(id)]
        )
    }

    func create(_ body: CreateUserBody) -> SNLExecutorPrtcl {
        makeExecutor(
            target: self,
            resource: resource,
            method: .post,
            body: .json(body)
        )
    }
}
```

### 3. Resource — `ExampleApi.swift`

The resource sets the base URL and defaults for every target. `SNLProvider` is used by default.

```swift
import SwiftNetLayer

final class ExampleApi: SNLResource, @unchecked Sendable {
    init() {
        super.init(
            protocol: .https,
            domain: "api.example.com",
            version: "v1",
            defaultHeaders: [.accept: "application/json"]
        )
    }
}
```

### 4. Target path — `ExampleApi+Users.swift`

Connect the resource to the `UsersTarget` defined above. The target inherits its initializer from `SNLTarget`.

```swift
import SwiftNetLayer

extension ExampleApi {
    func users() -> UsersTarget {
        UsersTarget(resource: self, path: "/users/:id")
    }
}
```

`:id` is an optional dynamic segment. `get(id:)` fills it in; `list()` and `create()` omit it, so their path becomes `/users`.

### 5. Execute requests

Use these calls in an async context. Reuse the same resource instance for its shared settings and request limit.

```swift
import SwiftNetLayer

let api = ExampleApi()

// GET /v1/users?page=1 — decode only the model.
let users = try await api.users().list(page: 1)
    .modelExecute(model: [User].self)
print(users.count)

// GET /v1/users/42 — keep both the model and HTTP response.
let result = try await api.users().get(id: 42)
    .execute(model: User.self)
print(result.model.name, result.response.statusCode)

// POST /v1/users with {"name":"Ada"} — keep the raw HTTP response.
let response = try await api.users().create(CreateUserBody(name: "Ada"))
    .execute()
print(response.statusCode, response.body.count)
```

## Responses and errors

| Async call | Result |
| --- | --- |
| `try await executor.execute()` | `SNLHTTPResponse` |
| `try await executor.execute(model: User.self)` | `(model: User, response: SNLHTTPResponse)` |
| `try await executor.modelExecute(model: User.self)` | `User` |

`SNLHTTPResponse` contains:

| Property | Type | Meaning |
| --- | --- | --- |
| `url` | `URL` | Response URL |
| `statusCode` | `Int` | HTTP status code |
| `headers` | `SNLHeader` | Response headers, for example `response.headers[.contentType]` |
| `body` | `Data` | Response bytes; an empty body is valid and is not `nil` |

The default provider returns HTTP responses regardless of status. A `400` or `500` does not automatically throw, and model decoding does not validate the status code. Check `response.statusCode` according to your API's rules.

Async methods report transport, body encoding, and JSON decoding errors through `throws`. To inspect the status before decoding, use a custom `JSONDecoder`, or retain the response if decoding fails, call `execute()` first and decode `response.body` yourself.

## Additional usage

The examples below reuse `api`, `User`, and `CreateUserBody` from the basic example. Calls containing `try await` belong in an async context.

### Path parameters

A path segment starting with `:` is a placeholder. Pass its value in the `pathParams` dictionary when calling `makeExecutor`. Both `"id"` and `":id"` match the placeholder `:id`. If both keys are present, `":id"` takes precedence.

For a target with `path: "/users/:id/:action"`:

| `pathParams` | Resolved path |
| --- | --- |
| `nil` or `[:]` | `/users` |
| `["id": "42"]` | `/users/42` |
| `[":id": "42", "action": "posts"]` | `/users/42/posts` |
| `["id": ""]` | `/users` |
| `["id": "a/b"]` | `/users/a%2Fb` |

Missing or empty values remove the corresponding segments. Pass unescaped values: each value is encoded as one path segment, including any `/`, `?`, or `#` characters. A static path such as `/health` needs no `pathParams`.

### Headers and query parameters

Headers and query parameters are merged in this order; later values override earlier ones:

```text
Resource defaults → Target defaults → Request values
```

Header names use `SNLHeaderName`: standard names such as `.authorization` and `.accept`, or `.custom("X-Feature")`. Header name matching is case-insensitive.

```swift
import SwiftNetLayer

let resource = SNLResource(
    protocol: .https,
    domain: "api.example.com",
    defaultHeaders: [
        .authorization: "Bearer example-token",
        .acceptLanguage: "en"
    ],
    defaultParams: ["locale": "en"]
)

let target = SNLTarget(
    resource: resource,
    path: "/users",
    headers: [.custom("X-Feature"): "users"],
    params: ["limit": 20]
)

let executor = target.makeExecutor(
    target: target,
    resource: resource,
    method: .get,
    requestHeaders: [.acceptLanguage: "fr"],
    requestParams: ["limit": 50]
)
```

This request uses `Accept-Language: fr`, preserves the other headers, and sends `locale=en` and `limit=50` in the URL query.

`defaultParams`, target `params`, and `requestParams` always become query parameters, including for POST requests. Use `body` for request content.

### Request bodies and files

Pass an `SNLBody` to `makeExecutor(body:)`:

| Body | Example |
| --- | --- |
| JSON from an `Encodable` value | `.json(CreateUserBody(name: "Ada"))` |
| URL-encoded form | `.form(["name": "Ada"])` |
| UTF-8 text | `.data("Hello", contentType: .textPlain)` |
| Bytes with a MIME type | `.data(bytes: bytes, contentType: .applicationOctetStream)` |
| Raw bytes | `.raw(bytes: bytes)` |
| Multipart fields and files | `.multipart([.field(name: "name", value: "Ada")])` |

The default provider sets `Content-Type` for `.data`, `.json`, `.form`, and `.multipart`. A conflicting explicit header produces an error. With `.raw(bytes:)`, the provider leaves the header to the caller and the URL session. For a POST with bytes, `URLSession` may supply `application/x-www-form-urlencoded`. Both byte cases accept `nil` as zero bytes. Use `body: nil` to omit the body.

This example creates a text attachment in memory and sends it alongside a regular multipart field:

```swift
import Foundation
import SwiftNetLayer

let file = SNLFile(
    data: Data("Example attachment".utf8),
    fileName: "note.txt",
    mimeType: "text/plain"
)

let uploadTarget = SNLTarget(resource: api, path: "/uploads")
let upload = uploadTarget.makeExecutor(
    target: uploadTarget,
    resource: api,
    method: .post,
    body: .multipart([
        .field(name: "folder", value: "notes"),
        .file(name: "attachment", file: file)
    ])
)
let uploadResponse = try await upload.execute()
```

Multipart fields belong in `.field` entries. `requestParams` still goes into the URL query.

### Request rate limits

Set `requestPerSecondOptions` when constructing a resource or in your resource's `super.init`:

```swift
import SwiftNetLayer
import SwiftExtensionsPack

let limitedResource = SNLResource(
    protocol: .https,
    domain: "api.example.com",
    requestPerSecondOptions: SafeValue(
        RequestPerSecondOptions(requestLimit: 5, timeRangeLimitSecond: 1)
    )
)
let limitedUsers = UsersTarget(resource: limitedResource, path: "/users/:id")
```

This allows five request starts per fixed one-second window, shared by all targets using this resource. It does not limit the number of requests already in flight or retry failed requests. Omit the options to disable the limiter.

When an `SNLResource` reaches its limit, each waiting request tries to acquire a slot again at the next window boundary. Async execution suspends while waiting. Callback execution and `waitExecute` block the calling thread while waiting for a slot.

### Timeouts and debugging

Set timeouts in seconds through `makeExecutor` or on a prepared executor:

```swift
var request = api.users().get(id: 42)
request.timeoutIntervalForRequest = 15
request.timeoutIntervalForResource = 60

let timedResponse = try await request.execute(debug: true)
```

Unset timeouts use the provider's session configuration. With the default provider, `debug: true` prints request and response details, including headers and body. It is also available on model and callback execution methods.

### Callbacks and synchronous waiting

Callback methods and their handlers do not throw. Errors are delivered through the `error` argument. Closures are `@Sendable`; models decoded by callback methods must be `Decodable & Sendable`.

```swift
api.users().get(id: 42).execute(model: User.self) { user, response, error in
    if let error {
        print(error)
        return
    }
    guard let user, let response else { return }
    print(user.name, response.statusCode)
}
```

The raw callback overload receives `(SNLHTTPResponse?, SNLError?)`. The model overload receives `(Model?, SNLHTTPResponse?, SNLError?)`; if decoding fails, the HTTP response remains available alongside the error. Callback delivery is controlled by the provider; callbacks are not guaranteed to run on the main thread.

`waitExecute` accepts the same callbacks and blocks until the handler finishes:

```swift
api.users().get(id: 42).waitExecute { response, error in
    if let error {
        print(error)
        return
    }
    if let response {
        print(response.statusCode)
    }
}
```

If the current queue matches the provider's declared callback queue, `waitExecute` reports an error without sending the request. This prevents waiting inside one callback for another callback that needs the same queue. Use async/await or ordinary callbacks for request chains.

### Custom providers

Pass a provider through `SNLResource(provider: ...)` to replace the transport. Implement [`SNLProviderPrtcl`](Sources/SwiftNetLayer/Provider/SNL+ProviderPrtcl.swift): `init()`, both `executeRequest` methods, and `callbackContext`. There are no default protocol implementations. Return `SNLHTTPResponse` with the URL, status, headers, and body supplied by your transport.

`callbackContext` describes callback delivery for the executor's synchronous-wait check; it does not schedule callbacks:

| Context | `waitExecute` behavior |
| --- | --- |
| `.dispatchQueue(queue)` | Rejects waiting from the declared dispatch queue |
| `.operationQueue(queue)` | Rejects waiting from the declared operation queue or its underlying dispatch queue |
| `.waitUnsupported` | Always reports an error without sending; ordinary callback and async execution remain available |
| `.unchecked` | Skips the queue check; the provider author is responsible for safe synchronous waiting |

The default `SNLProvider` declares its session's delegate queue. To use your own `URLSession`, construct `SNLProvider(session:)`; import `FoundationNetworking` conditionally on platforms where it is available.
