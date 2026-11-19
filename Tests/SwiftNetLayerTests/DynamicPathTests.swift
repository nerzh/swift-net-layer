import Foundation
import SwiftNetLayer
import XCTest

final class DynamicPathTests: XCTestCase {
    func testReservedCharactersStayInsideOnePathSegment() throws {
        let request = SNLRequest(
            method: .get, path: try XCTUnwrap(URL(string: "/users/:id")),
            dynamicPathsParts: [":id": "a/b?x=1#section %"]
        )

        let components = try XCTUnwrap(URLComponents(url: request.path, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.percentEncodedPath, "/users/a%2Fb%3Fx%3D1%23section%20%25")
        XCTAssertNil(components.query)
        XCTAssertNil(components.fragment)
    }

    func testSubstitutionPreservesStaticEscapesQueryAndFragment() throws {
        let request = SNLRequest(
            method: .get,
            path: try XCTUnwrap(URL(string: "/files/a%2Fb/:id?keep=a%2Bb&literal=:id#part/:id")),
            dynamicPathsParts: [":id": "c/d"]
        )

        XCTAssertEqual(request.path.absoluteString, "/files/a%2Fb/c%2Fd?keep=a%2Bb&literal=:id#part/:id")
    }

    func testChangingAndRemovingValuesAlwaysUsesOriginalTemplate() throws {
        var request = SNLRequest(
            method: .get, path: try XCTUnwrap(URL(string: "/users/:id/posts/:post")),
            dynamicPathsParts: [":id": "42"]
        )
        XCTAssertEqual(request.path.absoluteString, "/users/42/posts")

        request.dynamicPathsParts[":id"] = "43"
        request.dynamicPathsParts[":post"] = "10"
        XCTAssertEqual(request.path.absoluteString, "/users/43/posts/10")

        request.dynamicPathsParts.removeValue(forKey: ":id")
        XCTAssertEqual(request.path.absoluteString, "/users/posts/10")

        request.dynamicPathsParts = [":id": "44"]
        XCTAssertEqual(request.path.absoluteString, "/users/44/posts")

        request.dynamicPathsParts = [:]
        XCTAssertEqual(request.path.absoluteString, "/users/posts")
    }

    func testMissingAndEmptyValuesRemoveOptionalSegments() throws {
        let cases: [(template: String, parts: [String: String]?, expected: String)] = [
            ("/users/:id/posts/:post", nil, "/users/posts"),
            ("/users/:id/posts/:post", [":id": "", ":post": "10"], "/users/posts/10"),
            ("/:first/:second", [:], "/"),
            ("/users/:id/", [:], "/users/"),
            ("users/:id", [:], "users")
        ]

        for entry in cases {
            let request = SNLRequest(
                method: .get, path: try XCTUnwrap(URL(string: entry.template)),
                dynamicPathsParts: entry.parts
            )
            XCTAssertEqual(request.path.absoluteString, entry.expected, entry.template)
        }
    }

    func testRepeatedPathSeparatorsAreCollapsedAfterSubstitution() throws {
        let cases: [(template: String, parts: [String: String]?, expected: String)] = [
            ("/:id//users", nil, "/users"),
            ("/:id///users", [":id": ""], "/users"),
            ("/users///:id//posts//", [":id": "42"], "/users/42/posts/"),
            ("/:first////:second///", [:], "/"),
            ("users///:id//posts", nil, "users/posts"),
            ("/:id//users", [":id": "a//b"], "/a%2F%2Fb/users"),
            ("/files/a%2F%2Fb///:id", [":id": "x//y"], "/files/a%2F%2Fb/x%2F%2Fy")
        ]

        for entry in cases {
            let request = SNLRequest(
                method: .get, path: try XCTUnwrap(URL(string: entry.template)),
                dynamicPathsParts: entry.parts
            )
            XCTAssertEqual(request.path.absoluteString, entry.expected, entry.template)
        }
    }

    func testPathNormalizationPreservesSchemeQueryAndFragment() throws {
        var request = SNLRequest(
            method: .get,
            path: try XCTUnwrap(URL(string: "https://example.test/:id///users//:section?next=https://other.test/a//b#part//anchor")),
            dynamicPathsParts: [":section": "a//b"]
        )
        XCTAssertEqual(
            request.path.absoluteString,
            "https://example.test/users/a%2F%2Fb?next=https://other.test/a//b#part//anchor"
        )

        request.dynamicPathsParts[":id"] = "42"
        XCTAssertEqual(
            request.path.absoluteString,
            "https://example.test/42/users/a%2F%2Fb?next=https://other.test/a//b#part//anchor"
        )

        request.dynamicPathsParts = [:]
        XCTAssertEqual(request.path.absoluteString, "https://example.test/users/?next=https://other.test/a//b#part//anchor")
    }

    func testAssigningPathReplacesTemplate() throws {
        var request = SNLRequest(
            method: .get, path: try XCTUnwrap(URL(string: "/users/:id")),
            dynamicPathsParts: [":id": "42"]
        )
        XCTAssertEqual(request.path.absoluteString, "/users/42")

        request.path = try XCTUnwrap(URL(string: "/teams/:id/:section"))
        XCTAssertEqual(request.path.absoluteString, "/teams/42")

        request.dynamicPathsParts = [":id": "7", ":section": "members"]
        XCTAssertEqual(request.path.absoluteString, "/teams/7/members")
    }

    func testValuesAreNotRecursivelySubstitutedOrEncodedAgainOnRead() throws {
        var request = SNLRequest(
            method: .get, path: try XCTUnwrap(URL(string: "/users/:id")),
            dynamicPathsParts: [":id": ":other", ":other": "unexpected"]
        )
        XCTAssertEqual(request.path.absoluteString, "/users/%3Aother")
        XCTAssertEqual(request.path.absoluteString, "/users/%3Aother")

        request.dynamicPathsParts[":id"] = "a%2Fb"
        XCTAssertEqual(request.path.absoluteString, "/users/a%252Fb")
        XCTAssertEqual(request.path.absoluteString, "/users/a%252Fb")

        request.dynamicPathsParts[":id"] = "a/b"
        XCTAssertEqual(request.path.absoluteString, "/users/a%2Fb")
    }

    func testDotAndUnicodeValuesAreEncoded() throws {
        for (value, expected) in [(".", "%2E"), ("..", "%2E%2E"), ("café ☕", "caf%C3%A9%20%E2%98%95")] {
            let request = SNLRequest(
                method: .get, path: try XCTUnwrap(URL(string: "/users/:id/details")),
                dynamicPathsParts: [":id": value]
            )
            XCTAssertEqual(request.path.absoluteString, "/users/\(expected)/details")
        }
    }

    func testLiteralColonsAndEncodedPlaceholderNamesRemainUnchanged() throws {
        let request = SNLRequest(
            method: .get, path: try XCTUnwrap(URL(string: "/files/a:b/%3Aid/:id")),
            dynamicPathsParts: [":id": "42", "a:b": "unexpected"]
        )
        XCTAssertEqual(request.path.absoluteString, "/files/a:b/%3Aid/42")

        let staticRequest = SNLRequest(
            method: .get, path: try XCTUnwrap(URL(string: "/files/a%2Fb?literal=/:id#/:id")),
            dynamicPathsParts: [":id": "42"]
        )
        XCTAssertEqual(staticRequest.path.absoluteString, "/files/a%2Fb?literal=/:id#/:id")
    }

    func testAbsoluteURLAndRepeatedPlaceholdersPreserveURLStructure() throws {
        let request = SNLRequest(
            method: .get, path: try XCTUnwrap(URL(string: "https://example.test/users/:id/related/:id?fixed=1#section")),
            dynamicPathsParts: [":id": "a/b"]
        )
        XCTAssertEqual(request.path.absoluteString, "https://example.test/users/a%2Fb/related/a%2Fb?fixed=1#section")
    }
}
