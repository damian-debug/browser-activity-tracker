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

    /// For scripts/uninstall.sh. Deleting the app does not remove its login
    /// item: macOS keeps it registered and enabled, pointing at a bundle that
    /// no longer exists, and only the app that registered it can take it out.
    static func unregisterForUninstall() -> Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return set(false)
        default:
            // Nothing registered. An app that has never been registered
            // reports .notFound rather than .notRegistered, and unregister()
            // throws in both cases, so neither is a failure worth reporting.
            return true
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
