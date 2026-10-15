// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MasterReminder",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.executable(name: "MasterReminder", targets: ["MasterReminder"]),
               .library(name: "ReminderCore", targets: ["ReminderCore"]),
               .library(name: "ReminderDesign", targets: ["ReminderDesign"])],
    targets: [
        .target(name: "ReminderCore", resources: [.process("Resources")]),
        .target(name: "ReminderDesign", dependencies: ["ReminderCore"]),
        .executableTarget(name: "MasterReminder", dependencies: ["ReminderCore", "ReminderDesign"],
                          resources: [.copy("Resources/PrivacyInfo.xcprivacy")]),
        .testTarget(name: "ReminderCoreTests", dependencies: ["ReminderCore"])
    ]
)
