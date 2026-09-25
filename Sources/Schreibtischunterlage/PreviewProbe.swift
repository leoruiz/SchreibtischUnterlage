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
    private var controller: DisplaySessionController?
    private var previewWindowController: PreviewWindowController?
    private var captureFailure: Error?

    init(visibleDuration: Duration) {
        self.visibleDuration = visibleDuration
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

        let previewWindowController = try PreviewWindowController.make()
        previewWindowController.failureHandler = { [weak self] error in
            self?.captureFailure = error
        }
        self.previewWindowController = previewWindowController

        try await previewWindowController.start(displayID: displayID)
        try await waitForRenderedFrame(previewWindowController)
        print("screen capture frame delivery: PASS")
        print("metal frame submission: PASS")

        try await Task.sleep(for: visibleDuration)
        if let captureFailure {
            throw captureFailure
        }

        try await previewWindowController.stop()
        self.previewWindowController = nil
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

