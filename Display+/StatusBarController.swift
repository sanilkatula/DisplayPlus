import AppKit
import SwiftUI

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Display+")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentSize = NSSize(width: 540, height: 780)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DisplayPanelView()
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
