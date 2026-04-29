# SwiftNetLayer

`SwiftNetLayer` is a lightweight networking layer for describing HTTP APIs in Swift. It helps keep networking code split into predictable, readable files:

- `Resource` describes the API host: `https://api.example.com`, shared headers, shared query params, and request limits.
- `Target` describes an endpoint group: `/users`, `/books`, `/wallets`, `/rpc`.
- A method inside a target describes one concrete request: HTTP method, path variables, query params, body, files, timeout, and response model.

The intended structure is simple: one folder per external service, with a resource file and one or more target files inside it.

## Installation

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nerzh/swift-net-layer.git", .upToNextMajor(from: "1.0.0"))
]
```

Then add the product to your app target:

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "SwiftNetLayer", package: "swift-net-layer")
    ]
)
```

Import it where you describe your API:

```swift
import SwiftNetLayer
```

## Basic Structure

Usually one external API gets one folder:

```text
Networking/
  ExampleApi/
    ExampleApi.swift
    Targets/
      UsersTarget.swift
      BooksTarget.swift
      ExampleModels.swift
```

`ExampleApi.swift` is the resource. It knows the domain and default settings:

```swift
import Foundation
import SwiftNetLayer

final class ExampleApi: SNLResource {
    static let shared = ExampleApi(token: "<token>")

    init(token: String) {
        super.init(
            protocol: .https,
            domain: "api.example.com",
            version: "v1",
            defaultHeaders: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json"
            ],
            defaultParams: [
                "locale": "en"
            ],
            requestPerSecondOptions: .init(
                .init(requestLimit: 5, timeRangeLimitSecond: 1)
            )
        )
    }

    func users() -> UsersTarget {
        UsersTarget(resource: self, path: "/users")
    }

    func books() -> BooksTarget {
        BooksTarget(resource: self, path: "/books")
    }
}
```

The base URL is:

```text
https://api.example.com/v1
```

And `UsersTarget(resource: self, path: "/users")` sends requests relative to:

```text
https://api.example.com/v1/users
```

## Resource

`SNLResource` stores shared settings for the whole service:

```swift
super.init(
    provider: SNLProvider(),
    protocol: .https,
    domain: "api.example.com",
    version: "v1",
    defaultHeaders: [
        "Authorization": "Bearer \(token)"
    ],
    defaultParams: [
        "api_key": apiKey
    ],
    requestPerSecondOptions: .init(
        .init(requestLimit: 10, timeRangeLimitSecond: 1)
    )
)
```

Common resource-level values:

- `protocol` - `.http` or `.https`.
- `domain` - host without the protocol, for example `api.example.com`. If your API uses part of the path as its base, values like `mainnet.infura.io/v3` are also valid.
- `version` - optional path component, for example `v1` or `api/v2`.
- `defaultHeaders` - auth token, `Accept`, or shared `Content-Type`.
- `defaultParams` - params that should be included in every request, for example `api_key`.
- `requestPerSecondOptions` - a simple limiter for APIs with request-per-second restrictions.

If you pass `requestPerSecondOptions` directly, you may need to import `SwiftExtensionsPack`, because the limiter is wrapped in `SafeValue<RequestPerSecondOptions>`.

## Target

`SNLTarget` stores the path, headers, and params for a specific group of methods. For example, `/users`:

```swift
import Foundation
import SwiftNetLayer

final class UsersTarget: SNLTarget {
    func list(limit: Int = 20) async throws -> [User] {
        try await makeExecutor(
            target: self,
            resource: resource,
            method: .get,
            requestParams: [
                "limit": limit
            ]
        )
        .execute(model: [User].self)
    }
}
```

Usage:

```swift
let users = try await ExampleApi.shared.users().list(limit: 50)
```

If a target needs its own defaults, pass them when creating the target:

```swift
func users() -> UsersTarget {
    UsersTarget(
        resource: self,
        path: "/users",
        headers: [
            "X-Feature": "new-users-api"
        ],
        params: [
            "include_deleted": false
        ]
    )
}
```

Headers and params are merged from three levels:

```text
Resource defaults -> Target defaults -> Request values
```

That means a concrete target method can override values defined at the resource or target level.

If `body == nil` and `requestHeaders` does not contain `Content-Type`, the library adds `Content-Type: application/x-www-form-urlencoded` by default. For JSON requests, explicitly pass `"Content-Type": "application/json"` either on the resource or on the concrete request.

## GET With Query Params

`Targets/UsersTarget.swift`:

```swift
import Foundation
import SwiftNetLayer

struct User: Decodable {
    let id: Int
    let name: String
}

final class UsersTarget: SNLTarget {
    func list(page: Int, limit: Int) async throws -> [User] {
        let params: SNLParams = [
            "page": page,
            "limit": limit
        ]

        return try await makeExecutor(
            target: self,
            resource: resource,
            method: .get,
            requestParams: params
        )
        .execute(model: [User].self)
    }
}
```

If the resource has `defaultParams: ["locale": "en"]`, the final request receives:

```text
?locale=en&page=1&limit=20
```

## Dynamic Path Parts

If a path has a variable component, write it as `:id`, `:method`, or `:chain`, then pass replacements through `dynamicPathsParts`.

Resource:

```swift
final class ExampleApi: SNLResource {
    func userDetails() -> UserDetailsTarget {
        UserDetailsTarget(resource: self, path: "/users/:id")
    }
}
```

Target:

```swift
final class UserDetailsTarget: SNLTarget {
    func get(id: Int) async throws -> User {
        try await makeExecutor(
            target: self,
            resource: resource,
            method: .get,
            dynamicPathsParts: [
                ":id": "\(id)"
            ]
        )
        .execute(model: User.self)
    }
}
```

Usage:

```swift
let user = try await ExampleApi.shared.userDetails().get(id: 42)
```

Final path:

```text
/users/42
```

The same pattern is useful for APIs shaped like `/:chain/:method`:

```swift
func stats() async throws -> Stats {
    try await makeExecutor(
        target: self,
        resource: resource,
        method: .get,
        dynamicPathsParts: [
            ":chain": "bitcoin",
            ":method": "stats"
        ]
    )
    .execute(model: Stats.self)
}
```

## POST With JSON Body

For a JSON request, encode `Data` and pass it as `body`. You can define `Content-Type` at the resource level or on a concrete request.

```swift
struct CreateBookRequest: Encodable {
    let title: String
    let authorId: Int
}

struct Book: Decodable {
    let id: Int
    let title: String
}

final class BooksTarget: SNLTarget {
    func create(title: String, authorId: Int) async throws -> Book {
        let request = CreateBookRequest(title: title, authorId: authorId)
        let body = try JSONEncoder().encode(request)

        return try await makeExecutor(
            target: self,
            resource: resource,
            method: .post,
            requestHeaders: [
                "Content-Type": "application/json"
            ],
            body: body
        )
        .execute(model: Book.self)
    }
}
```

For JSON-RPC APIs, it is convenient to keep a helper on the resource:

```swift
struct JsonRpcRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: Params
}

extension ExampleApi {
    static func jsonRpcBody<Params: Encodable>(
        id: Int = 1,
        method: String,
        params: Params
    ) throws -> Data {
        try JSONEncoder().encode(
            JsonRpcRequest(id: id, method: method, params: params)
        )
    }
}
```

Then use it in a target:

```swift
func balance(address: String) async throws -> BalanceResponse {
    let body = try ExampleApi.jsonRpcBody(
        method: "getBalance",
        params: [address]
    )

    return try await makeExecutor(
        target: self,
        resource: resource,
        method: .post,
        requestHeaders: [
            "Content-Type": "application/json"
        ],
        body: body
    )
    .execute(model: BalanceResponse.self)
}
```

## Multipart And Files

For multipart requests, pass `multipart: true` and a `files` dictionary.

```swift
struct UploadResponse: Decodable {
    let id: String
    let url: String
}

final class FilesTarget: SNLTarget {
    func uploadImage(data: Data) async throws -> UploadResponse {
        let file = SNLFile(
            data: data,
            fileName: "image.png",
            mimeType: SNLMIMEType.imagePNG.description
        )

        return try await makeExecutor(
            target: self,
            resource: resource,
            method: .post,
            multipart: true,
            requestParams: [
                "folder": "avatars"
            ],
            files: [
                "file": file
            ]
        )
        .execute(model: UploadResponse.self)
    }
}
```

`requestParams` become regular multipart fields, and `files` become file fields.

## Responses

The most common option is decoding a `Decodable` model directly:

```swift
let user: User = try await ExampleApi.shared.userDetails().get(id: 1)
```

If you also need `URLResponse`:

```swift
let output: (User, URLResponse) = try await makeExecutor(
    target: self,
    resource: resource,
    method: .get
)
.execute(model: User.self)

let user = output.0
let response = output.1
```

If you need raw data:

```swift
let data: Data = try await makeExecutor(
    target: self,
    resource: resource,
    method: .get
)
.execute()
```

Callback-style methods are also available:

```swift
try makeExecutor(
    target: self,
    resource: resource,
    method: .get
)
.execute(model: User.self) { user, response, error in
    // Handle callback result.
}
```

## Debug

To print URL, method, headers, params, body, and the multipart flag:

```swift
let user: User = try await makeExecutor(
    target: self,
    resource: resource,
    method: .get,
    dynamicPathsParts: [
        ":id": "42"
    ]
)
.execute(model: User.self, debug: true)
```

The request information is printed to the console.

## Timeouts

Timeouts can be configured per request:

```swift
let receipt = try await makeExecutor(
    target: self,
    resource: resource,
    method: .post,
    body: body,
    timeoutIntervalForRequest: 30,
    timeoutIntervalForResource: 60
)
.execute(model: Receipt.self)
```

## Rate Limit

If an API limits request frequency, define the limit on the resource:

```swift
final class BlockExplorerApi: SNLResource {
    init(apiKey: String) {
        super.init(
            protocol: .https,
            domain: "api.blockexplorer.example",
            defaultParams: [
                "key": apiKey
            ],
            requestPerSecondOptions: .init(
                .init(
                    requestLimit: 10,
                    timeRangeLimitSecond: 1,
                    retryDelaySecond: 100_000_000
                )
            )
        )
    }
}
```

Before executing a request, `SNLExecutor` waits until a free request slot is available.

## Complete Example: Users API

`Networking/UsersApi/UsersApi.swift`:

```swift
import Foundation
import SwiftNetLayer

final class UsersApi: SNLResource {
    static let shared = UsersApi(token: "<token>")

    init(token: String) {
        super.init(
            protocol: .https,
            domain: "api.example.com",
            version: "v1",
            defaultHeaders: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json"
            ],
            defaultParams: [
                "client": "ios"
            ]
        )
    }

    func users() -> UsersTarget {
        UsersTarget(resource: self, path: "/users")
    }

    func user() -> UserTarget {
        UserTarget(resource: self, path: "/users/:id")
    }
}
```

`Networking/UsersApi/Targets/UserModels.swift`:

```swift
import Foundation

struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

struct CreateUserRequest: Encodable {
    let name: String
    let email: String
}
```

`Networking/UsersApi/Targets/UsersTarget.swift`:

```swift
import Foundation
import SwiftNetLayer

final class UsersTarget: SNLTarget {
    func list(search: String? = nil, page: Int = 1) async throws -> [User] {
        var params: SNLParams = [
            "page": page
        ]

        if let search {
            params["search"] = search
        }

        return try await makeExecutor(
            target: self,
            resource: resource,
            method: .get,
            requestParams: params
        )
        .execute(model: [User].self)
    }

    func create(name: String, email: String) async throws -> User {
        let body = try JSONEncoder().encode(
            CreateUserRequest(name: name, email: email)
        )

        return try await makeExecutor(
            target: self,
            resource: resource,
            method: .post,
            requestHeaders: [
                "Content-Type": "application/json"
            ],
            body: body
        )
        .execute(model: User.self)
    }
}
```

`Networking/UsersApi/Targets/UserTarget.swift`:

```swift
import Foundation
import SwiftNetLayer

final class UserTarget: SNLTarget {
    func get(id: Int) async throws -> User {
        try await makeExecutor(
            target: self,
            resource: resource,
            method: .get,
            dynamicPathsParts: [
                ":id": "\(id)"
            ]
        )
        .execute(model: User.self)
    }

    func delete(id: Int) async throws -> Data {
        try await makeExecutor(
            target: self,
            resource: resource,
            method: .delete,
            dynamicPathsParts: [
                ":id": "\(id)"
            ]
        )
        .execute()
    }
}
```

App usage:

```swift
let users = try await UsersApi.shared.users().list(search: "oleh")
let user = try await UsersApi.shared.user().get(id: users[0].id)
let created = try await UsersApi.shared.users().create(
    name: "Ada",
    email: "ada@example.com"
)
```

## Practical Tips

- One external service should usually have one `SNLResource`.
- One logical API section should usually have one `SNLTarget`: `UsersTarget`, `BooksTarget`, `WalletsTarget`, `RpcTarget`.
- Keep methods that return ready-to-use app models inside target files.
- Put shared headers and params on the resource.
- Put section-specific headers and params on the target.
- Put method-specific values in `requestParams`, `requestHeaders`, `body`, `files`, or `dynamicPathsParts`.
- Do not keep real API keys in README files or repositories. Pass them through configuration, environment, Keychain, or dependency injection.

## Quick Reference

```swift
makeExecutor(
    target: self,
    resource: resource,
    method: .get,
    multipart: false,
    dynamicPathsParts: [":id": "42"],
    requestHeaders: ["Content-Type": "application/json"],
    requestParams: ["limit": 20],
    body: body,
    files: ["file": file],
    timeoutIntervalForRequest: 30,
    timeoutIntervalForResource: 60
)
```

Execution methods:

```swift
try await executor.execute()
try await executor.execute(debug: true)
try await executor.execute(model: User.self)
try await executor.execute(model: User.self, debug: true)
try executor.execute(model: User.self) { user, response, error in }
try executor.waitExecute(model: User.self) { user, response, error in }
```
