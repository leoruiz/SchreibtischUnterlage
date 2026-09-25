import AppKit
import CoreGraphics
import Darwin
import Foundation
import SchreibtischunterlageCore
import SchreibtischunterlagePlatform

private struct PreviewProbeFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
final class PreviewProbe: NSObject, NSApplicationDelegate {
    private(set) var exitCode = EXIT_FAILURE

    private let visibleDuration: Duration
    private let testsPointerForwarding: Bool
    private var controller: DisplaySessionController?
    private var previewWindowController: PreviewWindowController?
    private var pointerTarget: PointerProbeTarget?
    private var captureFailure: Error?

    init(
        visibleDuration: Duration,
        testsPointerForwarding: Bool = false
    ) {
        self.visibleDuration = visibleDuration
        self.testsPointerForwarding = testsPointerForwarding
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await run()
                exitCode = EXIT_SUCCESS
            } catch {
                fputs("preview probe failed: \(error)\n", stderr)
            }
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        previewWindowController?.invalidate()
        previewWindowController = nil
        pointerTarget?.close()
        pointerTarget = nil
        controller?.stopIfNeeded()
        controller = nil
    }

    private func run() async throws {
        let snapshotProvider = CoreGraphicsPhysicalDisplaySnapshotProvider()
        let baseline = try snapshotProvider.snapshots()
        guard !baseline.isEmpty else {
            throw PreviewProbeFailure(description: "No baseline displays found")
        }

        let controller = DisplaySessionController(
            snapshotProvider: snapshotProvider,
            displayFactory: CGVirtualDisplayFactory()
        )
        self.controller = controller

        try controller.start(
            configuration: VirtualDisplayModeCatalog.standardConfiguration
        )
        guard let displayID = controller.activeDisplayID else {
            throw PreviewProbeFailure(description: "Virtual display has no display ID")
        }

        let activeMode = try await DisplayProbe.waitForDisplayMode(
            displayID: displayID
        )
        print(
            "preview display: id=\(displayID) "
                + "mode=\(activeMode.pixelWidth)x\(activeMode.pixelHeight) "
                + "@\(activeMode.refreshRate)"
        )

        if testsPointerForwarding {
            let pointerTarget = try PointerProbeTarget(displayID: displayID)
            pointerTarget.show()
            self.pointerTarget = pointerTarget
        }

        let previewWindowController = try PreviewWindowController.make()
        previewWindowController.failureHandler = { [weak self] error in
            self?.captureFailure = error
        }
        self.previewWindowController = previewWindowController

        try await previewWindowController.start(displayID: displayID)
        try await waitForRenderedFrame(previewWindowController)
        print("screen capture frame delivery: PASS")
        print("metal frame submission: PASS")

        if let pointerTarget {
            try await verifyPointerForwarding(
                displayID: displayID,
                previewWindowController: previewWindowController,
                target: pointerTarget
            )
            print("preview click forwarding: PASS")
        }

        try await Task.sleep(for: visibleDuration)
        if let captureFailure {
            throw captureFailure
        }

        try await previewWindowController.stop()
        self.previewWindowController = nil
        pointerTarget?.close()
        pointerTarget = nil
        try controller.stop()
        try await DisplayProbe.waitForDisplayRemoval(displayID: displayID)
        try DisplayProbe.verifyPhysicalDisplays(
            baseline: baseline,
            snapshotProvider: snapshotProvider
        )
        self.controller = nil

        print("physical displays unchanged: PASS")
        print("virtual display teardown: PASS")
    }

    private func verifyPointerForwarding(
        displayID: CGDirectDisplayID,
        previewWindowController: PreviewWindowController,
        target: PointerProbeTarget
    ) async throws {
        guard let sourceSize = previewWindowController.currentSourceSize else {
            throw PreviewProbeFailure(
                description: "Preview has no source size for pointer mapping"
            )
        }

        let previewSize = previewWindowController.previewContentSize
        let displayBounds = CGDisplayBounds(displayID)
        let mappedPoint = PreviewCoordinateMapper.displayLocalPoint(
            previewPoint: CGPoint(
                x: previewSize.width / 2,
                y: previewSize.height / 2
            ),
            previewSize: previewSize,
            sourceSize: sourceSize,
            displaySize: displayBounds.size
        )
        print(
            "pointer geometry: display=\(displayBounds) "
                + "screen=\(target.screenFrame) target=\(target.windowFrame) "
                + "preview=\(previewSize) source=\(sourceSize) "
                + "mapped=\(String(describing: mappedPoint))"
        )

        let click = PreviewPointerClick(
            locationInView: CGPoint(
                x: previewSize.width / 2,
                y: previewSize.height / 2
            ),
            button: .left,
            clickCount: 1,
            modifierFlags: []
        )
        try await PointerEventForwarder(displayID: displayID).forward(
            click,
            previewSize: previewSize,
            sourceSize: sourceSize
        )
        print(
            "pointer location after forwarding: "
                + "\(String(describing: CGEvent(source: nil)?.location))"
        )

        for _ in 0..<100 {
            if target.clickCount > 0 {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        throw PreviewProbeFailure(
            description: "Forwarded click did not reach the virtual display target"
        )
    }

    private func waitForRenderedFrame(
        _ previewWindowController: PreviewWindowController
    ) async throws {
        for _ in 0..<100 {
            if let captureFailure {
                throw captureFailure
            }
            if previewWindowController.renderedFrameCount > 0 {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        throw PreviewProbeFailure(
            description: "No capture frame reached Metal within 10 seconds"
        )
    }
}

@MainActor
private final class PointerProbeTarget: NSObject {
    private(set) var clickCount = 0
    let screenFrame: CGRect

    private let window: NSWindow
    private let intendedFrame: CGRect
    var windowFrame: CGRect {
        window.frame
    }

    init(displayID: CGDirectDisplayID) throws {
        guard let screen = NSScreen.screens.first(
            where: { screen in
                let key = NSDeviceDescriptionKey("NSScreenNumber")
                return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
                    == displayID
            }
        ) else {
            throw PreviewProbeFailure(
                description: "Virtual display has no matching NSScreen"
            )
        }
        screenFrame = screen.frame

        let contentSize = CGSize(width: 600, height: 400)
        let contentRect = CGRect(
            x: screen.frame.midX - contentSize.width / 2,
            y: screen.frame.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        )
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        self.window = window
        intendedFrame = window.frameRect(forContentRect: contentRect)

        super.init()

        let button = NSButton(
            title: "Pointer forwarding target",
            target: self,
            action: #selector(didClick)
        )
        button.bezelStyle = .regularSquare
        button.frame = CGRect(origin: .zero, size: contentSize)
        button.autoresizingMask = [.width, .height]

        window.title = "Pointer Probe Target"
        window.contentView = button
        window.isReleasedWhenClosed = false
    }

    func show() {
        window.setFrame(intendedFrame, display: true)
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }

    @objc
    private func didClick() {
        clickCount += 1
    }
}
