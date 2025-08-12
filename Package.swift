// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "SwiftCentrifuge",
    products: [
        .library(name: "SwiftCentrifuge", targets: ["SwiftCentrifuge"]),
        .library(name: "SwiftCentrifugeExperiments", targets: ["SwiftCentrifugeExperiments"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf", from:"1.7.0")
    ],
    targets: [
        .target(
            name: "SwiftCentrifuge",
            dependencies: ["SwiftProtobuf"]
        ),
        .target(
            name: "SwiftCentrifugeExperiments",
            dependencies: ["SwiftCentrifuge"]
        ),
        .testTarget(
            name: "SwiftCentrifugeTests",
            dependencies: ["SwiftCentrifuge"]
        )
    ]
)
