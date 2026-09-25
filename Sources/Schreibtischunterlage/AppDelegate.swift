import AppKit
import SchreibtischunterlageCore
import SchreibtischunterlagePlatform

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessionController = DisplaySessionController(
        snapshotProvider: CoreGraphicsPhysicalDisplaySnapshotProvider(),
        displayFactory: CGVirtualDisplayFactory()
    )

    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var startMenuItem: NSMenuItem?
    private var stopMenuItem: NSMenuItem?
    private var displayChangeObserver: NSObjectProtocol?
    private var lastStatusMessage: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "display",
            accessibilityDescription: "Schreibtischunterlage"
        )
        statusItem.menu = makeMenu()
        self.statusItem = statusItem

        displayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDisplayConfigurationChange()
            }
        }

        updateMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionController.stopIfNeeded()

        if let displayChangeObserver {
            NotificationCenter.default.removeObserver(displayChangeObserver)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        self.statusMenuItem = statusMenuItem

        let startMenuItem = NSMenuItem(
            title: "Start Virtual Display",
            action: #selector(startVirtualDisplay),
            keyEquivalent: ""
        )
        startMenuItem.target = self
        menu.addItem(startMenuItem)
        self.startMenuItem = startMenuItem

        let stopMenuItem = NSMenuItem(
            title: "Stop Virtual Display",
            action: #selector(stopVirtualDisplay),
            keyEquivalent: ""
        )
        stopMenuItem.target = self
        menu.addItem(stopMenuItem)
        self.stopMenuItem = stopMenuItem

        let displaySettingsItem = NSMenuItem(
            title: "Open Display Settings…",
            action: #selector(openDisplaySettings),
            keyEquivalent: ""
        )
        displaySettingsItem.target = self
        menu.addItem(displaySettingsItem)

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
        do {
            try sessionController.start(
                configuration: VirtualDisplayModeCatalog.standardConfiguration
            )
            lastStatusMessage = nil
        } catch {
            lastStatusMessage = "Start failed"
            presentError(
                title: "Could not start the virtual display",
                error: error
            )
        }
        updateMenu()
    }

    @objc
    private func openDisplaySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Displays-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc
    private func stopVirtualDisplay() {
        do {
            try sessionController.stop()
            lastStatusMessage = nil
        } catch {
            lastStatusMessage = "Stop failed"
            presentError(
                title: "Could not stop the virtual display",
                error: error
            )
        }
        updateMenu()
    }

    private func handleDisplayConfigurationChange() {
        do {
            let violations = try sessionController.handleDisplayConfigurationChange()
            if !violations.isEmpty {
                lastStatusMessage = "Stopped after physical display change"
            }
        } catch {
            lastStatusMessage = "Stopped after display monitoring failed"
        }
        updateMenu()
    }

    private func updateMenu() {
        let isInactive = sessionController.state == .inactive
        let isActive = sessionController.state == .active

        if let lastStatusMessage {
            statusMenuItem?.title = lastStatusMessage
        } else if isActive {
            statusMenuItem?.title = "Virtual Display: Active"
        } else {
            statusMenuItem?.title = "Virtual Display: Inactive"
        }

        startMenuItem?.isEnabled = isInactive
        stopMenuItem?.isEnabled = !isInactive
    }

    private func presentError(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }
}
