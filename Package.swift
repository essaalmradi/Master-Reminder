// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MasterReminder",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MasterReminder", targets: ["MasterReminder"])
    ],
    targets: [
        .executableTarget(
            name: "MasterReminder",
            path: "Sources/MasterReminder"
        )
    ]
)
