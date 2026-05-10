import SwiftUI
import AppKit

@main
struct DisplayPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController()

        /*
         Launch at Login should only be registered after the app is copied
         to /Applications. If we register while running from Xcode, macOS may
         try to launch the temporary Debug build from DerivedData later.
         */
        LaunchAtLoginManager.enableIfInstalledInApplicationsFolder()
    }
}
