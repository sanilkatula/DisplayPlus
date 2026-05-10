import AppKit
import SwiftUI

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let menu: NSMenu

    init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.menu = NSMenu()

        setupStatusItem()
        setupPopover()
        setupMenu()
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Display+")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        popover.contentSize = NSSize(width: 540, height: 780)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DisplayPanelView()
        )
    }

    private func setupMenu() {
        menu.removeAllItems()

        let openItem = NSMenuItem(
            title: "Open Display+",
            action: #selector(openPopoverFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit Display+",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self

        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    @objc private func openPopoverFromMenu() {
        guard let button = statusItem.button else { return }

        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func quitApp() {
        popover.performClose(nil)
        NSApp.terminate(nil)
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }

        popover.performClose(nil)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }
}
