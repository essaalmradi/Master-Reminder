// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MasterReminder",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MasterReminder", targets: ["MasterReminder"])],
    targets: [
        .target(name: "ReminderCore"),
        .executableTarget(name: "MasterReminder", dependencies: ["ReminderCore"],
                          resources: [.copy("Resources/PrivacyInfo.xcprivacy")]),
        .testTarget(name: "ReminderCoreTests", dependencies: ["ReminderCore"])
    ]
)
