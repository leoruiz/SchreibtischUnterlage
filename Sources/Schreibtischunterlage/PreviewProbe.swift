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
    private let testsCursorPortal: Bool
    private var controller: DisplaySessionController?
    private var previewWindowController: PreviewWindowController?
    private var captureFailure: Error?

    init(
        visibleDuration: Duration,
        testsCursorPortal: Bool = false
    ) {
        self.visibleDuration = visibleDuration
        self.testsCursorPortal = testsCursorPortal
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await run()
                exitCode = EXIT_SUCCESS
            } catch {
                fputs("preview probe failed: \(error)\n", stderr)
            }
            await cleanup()
            exit(exitCode)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        previewWindowController?.invalidate()
        previewWindowController = nil
        controller?.stopIfNeeded()
        controller = nil
    }

    private func cleanup() async {
        if let previewWindowController {
            try? await previewWindowController.stop()
        }
        self.previewWindowController = nil
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

        if testsCursorPortal {
            try verifyCursorPortal(
                displayID: displayID,
                previewWindowController: previewWindowController
            )
            print("preview cursor portal: PASS")
        }

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

    private func verifyCursorPortal(
        displayID: CGDirectDisplayID,
        previewWindowController: PreviewWindowController
    ) throws {
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
                + "preview=\(previewSize) source=\(sourceSize) "
                + "mapped=\(String(describing: mappedPoint))"
        )

        guard let mappedPoint else {
            throw PreviewProbeFailure(
                description: "Preview center did not map to the virtual display"
            )
        }
        try CursorPortal(displayID: displayID).moveCursor(
            from: CGPoint(
                x: previewSize.width / 2,
                y: previewSize.height / 2
            ),
            previewSize: previewSize,
            sourceSize: sourceSize
        )
        let expectedPoint = CGPoint(
            x: displayBounds.minX + mappedPoint.x,
            y: displayBounds.minY + mappedPoint.y
        )
        guard let actualPoint = CGEvent(source: nil)?.location else {
            throw PreviewProbeFailure(
                description: "Could not read the global cursor location"
            )
        }
        print("pointer location after portal: \(actualPoint)")
        guard
            abs(actualPoint.x - expectedPoint.x) <= 1,
            abs(actualPoint.y - expectedPoint.y) <= 1
        else {
            throw PreviewProbeFailure(
                description: """
                Cursor reached \(actualPoint) instead of expected \(expectedPoint)
                """
            )
        }
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
