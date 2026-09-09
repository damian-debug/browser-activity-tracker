import ServiceManagement

/// Registering the app to start with the Mac.
///
/// `SMAppService.mainApp` needs no helper bundle and no privileged step. The
/// state worth handling is `.requiresApproval`: the user can turn this off in
/// System Settings, and silently failing to start would look like the app had
/// simply lost a day of tracking.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
