import AppKit
import ServiceManagement

/// Launch at login through the modern login-items API (requires running from the .app bundle).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum PrivacySettings {
    static func openInputMonitoring() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    static func openBluetooth() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
    }

    static func openFullDiskAccess() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    private static func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
