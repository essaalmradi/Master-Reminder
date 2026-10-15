import ServiceManagement
import Foundation
import Combine

@MainActor final class LoginItemManager: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    var enabled: Bool { status == .enabled }
    var statusText: String {
        switch status {
        case .enabled: return "مفعّل"
        case .requiresApproval: return "بانتظار الموافقة في إعدادات النظام"
        case .notFound: return "انقل التطبيق إلى Applications أولًا"
        case .notRegistered: return "غير مفعّل"
        @unknown default: return "غير معروف"
        }
    }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        refresh(); Log.login.info("Login item state refreshed")
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
