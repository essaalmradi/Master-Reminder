import OSLog

enum Log {
    static let scheduler = Logger(subsystem: "ly.masterlibya.masterreminder", category: "scheduler")
    static let notification = Logger(subsystem: "ly.masterlibya.masterreminder", category: "notification")
    static let overlay = Logger(subsystem: "ly.masterlibya.masterreminder", category: "overlay")
    static let storage = Logger(subsystem: "ly.masterlibya.masterreminder", category: "storage")
    static let sound = Logger(subsystem: "ly.masterlibya.masterreminder", category: "sound")
    static let login = Logger(subsystem: "ly.masterlibya.masterreminder", category: "login")
    static let app = Logger(subsystem: "ly.masterlibya.masterreminder", category: "app")
}
