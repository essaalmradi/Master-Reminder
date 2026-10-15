import AppIntents
import AlarmKit

struct StopReminderAlarm: LiveActivityIntent {
    static var title: LocalizedStringResource = "إيقاف المنبّه"
    @Parameter(title: "معرّف المنبّه") var alarmID: String
    init() {}
    init(id: String) { alarmID = id }
    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.stop(id: id) }
        return .result()
    }
}
struct PauseReminderAlarm: LiveActivityIntent {
    static var title: LocalizedStringResource = "إيقاف مؤقت"
    @Parameter(title: "معرّف المنبّه") var alarmID: String
    init() {}
    init(id: String) { alarmID = id }
    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.pause(id: id) }
        return .result()
    }
}
struct ResumeReminderAlarm: LiveActivityIntent {
    static var title: LocalizedStringResource = "استئناف المنبّه"
    @Parameter(title: "معرّف المنبّه") var alarmID: String
    init() {}
    init(id: String) { alarmID = id }
    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.resume(id: id) }
        return .result()
    }
}
