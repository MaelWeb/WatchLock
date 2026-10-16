// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WatchLock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WatchLock", targets: ["WatchLock"])
    ],
    targets: [
        .executableTarget(
            name: "WatchLock",
            path: "Sources/WatchLock",
            exclude: [],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .define("WATCHLOCK_SPM")
            ]
        ),
        .testTarget(
            name: "WatchLockTests",
            dependencies: ["WatchLock"],
            path: "Tests/WatchLockTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .define("WATCHLOCK_SPM")
            ]
        )
    ]
)
