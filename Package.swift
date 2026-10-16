// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HeadsetGesture",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HeadsetGesture", targets: ["HeadsetGestureApp"])
    ],
    targets: [
        .executableTarget(
            name: "HeadsetGestureApp",
            path: "Sources/HeadsetGestureApp"
        ),
        .testTarget(
            name: "HeadsetGestureAppTests",
            dependencies: ["HeadsetGestureApp"],
            path: "Tests/HeadsetGestureAppTests"
        )
    ]
)
