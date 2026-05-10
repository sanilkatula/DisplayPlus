import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    static func enableIfInstalledInApplicationsFolder() {
        guard isInstalledInApplicationsFolder else {
            print("Display+ launch-at-login skipped: app is not in /Applications.")
            return
        }

        guard #available(macOS 13.0, *) else {
            print("Display+ launch-at-login requires macOS 13 or newer.")
            return
        }

        let service = SMAppService.mainApp

        switch service.status {
        case .enabled:
            print("Display+ launch-at-login is already enabled.")

        case .requiresApproval:
            print("Display+ launch-at-login requires approval in System Settings.")

        case .notRegistered:
            do {
                try service.register()
                print("Display+ launch-at-login enabled.")
            } catch {
                print("Display+ failed to enable launch-at-login: \(error)")
            }

        case .notFound:
            print("Display+ launch-at-login service was not found.")

        @unknown default:
            print("Display+ launch-at-login unknown status.")
        }
    }

    static func disable() {
        guard #available(macOS 13.0, *) else {
            print("Display+ launch-at-login disable requires macOS 13 or newer.")
            return
        }

        let service = SMAppService.mainApp

        do {
            try service.unregister()
            print("Display+ launch-at-login disabled.")
        } catch {
            print("Display+ failed to disable launch-at-login: \(error)")
        }
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }

        return SMAppService.mainApp.status == .enabled
    }

    static var statusText: String {
        guard #available(macOS 13.0, *) else {
            return "Unsupported"
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Needs approval"
        case .notRegistered:
            return "Off"
        case .notFound:
            return "Not found"
        @unknown default:
            return "Unknown"
        }
    }

    private static var isInstalledInApplicationsFolder: Bool {
        let appPath = Bundle.main.bundlePath
        return appPath.hasPrefix("/Applications/")
    }
}
