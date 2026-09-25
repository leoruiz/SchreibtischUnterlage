import AppKit
import CoreGraphics
import SchreibtischunterlageCore
import SchreibtischunterlagePlatform

private enum PreviewLifecycleError: Error, LocalizedError {
    case missingManagedDisplay

    var errorDescription: String? {
        "The managed virtual display did not publish a usable display identifier."
    }
}

private enum PreferenceKey {
    static let previewAutoSurfacingMode =
        "previewAutoSurfacingMode"
    static let cursorPortalActivationMode =
        "cursorPortalActivationMode"
}

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
    private var autoSurfacingMenuItems =
        [PreviewAutoSurfacingMode: NSMenuItem]()
    private var cursorPortalMenuItems =
        [CursorPortalActivationMode: NSMenuItem]()
    private var displayChangeObserver: NSObjectProtocol?
    private var lastStatusMessage: String?
    private var previewWindowController: PreviewWindowController?
    private var lifecycleTask: Task<Void, Never>?
    private var isTransitioning = false
    private var transitionFailure: Error?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(
            defaults: [
                PreferenceKey.previewAutoSurfacingMode:
                    PreviewAutoSurfacingMode.raiseOnEntry.rawValue,
                PreferenceKey.cursorPortalActivationMode:
                    CursorPortalActivationMode.singleClick.rawValue,
            ]
        )

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
        lifecycleTask?.cancel()
        previewWindowController?.invalidate()
        previewWindowController = nil
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

        let autoSurfacingItem = NSMenuItem(
            title: "Preview Auto-Surfacing",
            action: nil,
            keyEquivalent: ""
        )
        let autoSurfacingMenu = NSMenu()
        for mode in PreviewAutoSurfacingMode.allCases {
            let item = NSMenuItem(
                title: title(for: mode),
                action: #selector(selectPreviewAutoSurfacingMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            autoSurfacingMenu.addItem(item)
            autoSurfacingMenuItems[mode] = item
        }
        autoSurfacingItem.submenu = autoSurfacingMenu
        menu.addItem(autoSurfacingItem)

        let cursorPortalItem = NSMenuItem(
            title: "Pointer Teleport",
            action: nil,
            keyEquivalent: ""
        )
        let cursorPortalMenu = NSMenu()
        for mode in CursorPortalActivationMode.allCases {
            let item = NSMenuItem(
                title: title(for: mode),
                action: #selector(selectCursorPortalActivationMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            cursorPortalMenu.addItem(item)
            cursorPortalMenuItems[mode] = item
        }
        cursorPortalItem.submenu = cursorPortalMenu
        menu.addItem(cursorPortalItem)

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
        guard
            !isTransitioning,
            sessionController.state == .inactive
        else {
            return
        }

        isTransitioning = true
        lastStatusMessage = "Starting virtual display…"
        updateMenu()

        lifecycleTask = Task { @MainActor [weak self] in
            await self?.startVirtualDisplayAndPreview()
        }
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
    private func selectPreviewAutoSurfacingMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = PreviewAutoSurfacingMode(rawValue: rawValue)
        else {
            return
        }

        UserDefaults.standard.set(
            mode.rawValue,
            forKey: PreferenceKey.previewAutoSurfacingMode
        )
        previewWindowController?.setAutoSurfacingMode(mode)
        updateMenu()
    }

    @objc
    private func selectCursorPortalActivationMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = CursorPortalActivationMode(rawValue: rawValue)
        else {
            return
        }

        UserDefaults.standard.set(
            mode.rawValue,
            forKey: PreferenceKey.cursorPortalActivationMode
        )
        previewWindowController?.setCursorPortalActivationMode(mode)
        updateMenu()
    }

    @objc
    private func stopVirtualDisplay() {
        guard
            !isTransitioning,
            sessionController.state != .inactive
        else {
            return
        }

        isTransitioning = true
        lastStatusMessage = "Stopping virtual display…"
        updateMenu()

        lifecycleTask = Task { @MainActor [weak self] in
            await self?.stopVirtualDisplayAndPreview()
        }
    }

    private func startVirtualDisplayAndPreview() async {
        do {
            try sessionController.start(
                configuration: VirtualDisplayModeCatalog.standardConfiguration
            )
            guard let displayID = sessionController.activeDisplayID else {
                throw PreviewLifecycleError.missingManagedDisplay
            }

            let previewWindowController = try PreviewWindowController.make(
                autoSurfacingMode: previewAutoSurfacingMode,
                cursorPortalActivationMode: cursorPortalActivationMode
            )
            previewWindowController.closeHandler = { [weak self] in
                self?.stopVirtualDisplay()
            }
            previewWindowController.failureHandler = { [weak self] error in
                self?.handleCaptureFailure(error)
            }
            previewWindowController.interactionFailureHandler = { [weak self] error in
                self?.presentError(
                    title: "Could not enter the virtual display",
                    error: error
                )
            }
            self.previewWindowController = previewWindowController

            try await previewWindowController.start(displayID: displayID)
            try Task.checkCancellation()
            lastStatusMessage = nil
            transitionFailure = nil
        } catch {
            if let previewWindowController {
                try? await previewWindowController.stop()
            }
            previewWindowController = nil
            sessionController.stopIfNeeded()

            if let transitionFailure {
                self.transitionFailure = nil
                lastStatusMessage = "Start failed"
                presentError(
                    title: "Could not start the virtual display",
                    error: transitionFailure
                )
            } else if !(error is CancellationError && sessionController.state == .inactive) {
                lastStatusMessage = "Start failed"
                presentError(
                    title: "Could not start the virtual display",
                    error: error
                )
            }
        }

        isTransitioning = false
        lifecycleTask = nil
        updateMenu()
    }

    private func stopVirtualDisplayAndPreview() async {
        var captureStopError: Error?
        if let previewWindowController {
            do {
                try await previewWindowController.stop()
            } catch {
                captureStopError = error
            }
        }
        previewWindowController = nil

        do {
            try sessionController.stop()
            if let captureStopError {
                lastStatusMessage = "Capture stop failed"
                presentError(
                    title: "The preview did not stop cleanly",
                    error: captureStopError
                )
            } else {
                lastStatusMessage = nil
            }
        } catch {
            lastStatusMessage = "Stop failed"
            presentError(
                title: "Could not stop the virtual display",
                error: error
            )
        }

        isTransitioning = false
        lifecycleTask = nil
        updateMenu()
    }

    private func handleCaptureFailure(_ error: Error) {
        guard sessionController.state != .inactive else {
            return
        }

        if isTransitioning {
            transitionFailure = error
            lifecycleTask?.cancel()
            return
        }

        presentError(
            title: "Screen capture stopped unexpectedly",
            error: error
        )
        stopVirtualDisplay()
    }

    private func handleDisplayConfigurationChange() {
        do {
            let violations = try sessionController.handleDisplayConfigurationChange()
            if !violations.isEmpty {
                lastStatusMessage = "Stopped after physical display change"
                cancelTransitionOrStopPreview()
            } else {
                previewWindowController?.handleDisplayConfigurationChange()
            }
        } catch {
            lastStatusMessage = "Stopped after display monitoring failed"
            cancelTransitionOrStopPreview()
        }
        updateMenu()
    }

    private func cancelTransitionOrStopPreview() {
        if isTransitioning {
            lifecycleTask?.cancel()
        } else {
            stopPreviewAfterExternalTeardown()
        }
    }

    private func stopPreviewAfterExternalTeardown() {
        guard !isTransitioning else {
            return
        }

        isTransitioning = true
        lifecycleTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if let previewWindowController {
                do {
                    try await previewWindowController.stop()
                } catch {
                    presentError(
                        title: "The preview did not stop cleanly",
                        error: error
                    )
                }
            }
            previewWindowController = nil
            isTransitioning = false
            lifecycleTask = nil
            updateMenu()
        }
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

        startMenuItem?.isEnabled = isInactive && !isTransitioning
        stopMenuItem?.isEnabled = !isInactive && !isTransitioning
        for (mode, item) in autoSurfacingMenuItems {
            item.state = mode == previewAutoSurfacingMode ? .on : .off
        }
        for (mode, item) in cursorPortalMenuItems {
            item.state = mode == cursorPortalActivationMode ? .on : .off
        }
    }

    private var previewAutoSurfacingMode: PreviewAutoSurfacingMode {
        guard
            let rawValue = UserDefaults.standard.string(
                forKey: PreferenceKey.previewAutoSurfacingMode
            ),
            let mode = PreviewAutoSurfacingMode(rawValue: rawValue)
        else {
            return .raiseOnEntry
        }
        return mode
    }

    private var cursorPortalActivationMode: CursorPortalActivationMode {
        guard
            let rawValue = UserDefaults.standard.string(
                forKey: PreferenceKey.cursorPortalActivationMode
            ),
            let mode = CursorPortalActivationMode(rawValue: rawValue)
        else {
            return .singleClick
        }
        return mode
    }

    private func title(for mode: PreviewAutoSurfacingMode) -> String {
        switch mode {
        case .off:
            return "Off"
        case .raiseOnEntry:
            return "Bring Preview to Front When Pointer Enters"
        case .raiseOnEntryAndLowerOnExit:
            return "Bring Preview to Front on Entry, Send Behind on Exit"
        }
    }

    private func title(for mode: CursorPortalActivationMode) -> String {
        switch mode {
        case .singleClick:
            return "Single Click"
        case .doubleClick:
            return "Double Click"
        }
    }

    private func presentError(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical

        if case ScreenCaptureCoordinatorError.permissionDenied = error {
            alert.addButton(withTitle: "Open Privacy Settings")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                openScreenRecordingSettings()
            }
        } else {
            alert.runModal()
        }
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(
            string: """
            x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture
            """
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
