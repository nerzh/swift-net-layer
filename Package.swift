// swift-tools-version:6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftNetLayer",
    
    platforms: [
       .macOS(.v12),
       .iOS(.v13)
    ],
    
    products: [
        .library(name: "SwiftNetLayer", targets: ["SwiftNetLayer"]),
    ],
    
    dependencies: [
        .package(url: "https://github.com/nerzh/swift-extensions-pack.git", .upToNextMajor(from: "2.0.0")),
    ],
    
    targets: [
        .target(
            name: "SwiftNetLayer",
            dependencies: [
                .product(name: "SwiftExtensionsPack", package: "swift-extensions-pack")
            ])
    ]
)
