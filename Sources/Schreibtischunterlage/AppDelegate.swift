import AppKit
import SchreibtischunterlageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "display",
            accessibilityDescription: "Schreibtischunterlage"
        )
        statusItem.menu = makeMenu()
        self.statusItem = statusItem
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: "Virtual Display: Inactive", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let startItem = NSMenuItem(
            title: "Start Virtual Display",
            action: #selector(startVirtualDisplay),
            keyEquivalent: ""
        )
        startItem.target = self
        menu.addItem(startItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Schreibtischunterlage",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    @objc
    private func startVirtualDisplay() {
        let alert = NSAlert()
        alert.messageText = "Virtual display support is not implemented yet."
        alert.informativeText = "This initial build intentionally launches without creating or changing any displays."
        alert.alertStyle = .informational
        alert.runModal()
    }
}

