import AppKit
import CoreGraphics
import Darwin
import Foundation
import SchreibtischUnterlageCore
import SchreibtischUnterlagePlatform

private struct PreviewProbeFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
final class PreviewProbe: NSObject, NSApplicationDelegate {
    private(set) var exitCode = EXIT_FAILURE

    private let visibleDuration: Duration
    private let testsCursorPortal: Bool
    private let measuresLatency: Bool
    private var controller: DisplaySessionController?
    private var previewWindowController: PreviewWindowController?
    private var captureFailure: Error?

    init(
        visibleDuration: Duration,
        testsCursorPortal: Bool = false,
        measuresLatency: Bool = false
    ) {
        self.visibleDuration = visibleDuration
        self.testsCursorPortal = testsCursorPortal
        self.measuresLatency = measuresLatency
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

        let configuration =
            VirtualDisplayModeCatalog.fallbackConfiguration
        try controller.start(configuration: configuration)
        guard let displayID = controller.activeDisplayID else {
            throw PreviewProbeFailure(description: "Virtual display has no display ID")
        }
        try await VirtualDisplayModeController.apply(
            configuration.preferredMode,
            to: displayID
        )

        let activeMode = try await DisplayProbe.waitForDisplayMode(
            displayID: displayID
        )
        print(
            "preview display: id=\(displayID) "
                + "mode=\(activeMode.pixelWidth)x\(activeMode.pixelHeight) "
                + "@\(activeMode.refreshRate)"
        )

        let previewWindowController = try PreviewWindowController.make(
            measuresLatency: measuresLatency,
            autoSurfacingMode: testsCursorPortal
                ? .raiseOnEntryAndLowerOnExit
                : .raiseOnEntry
        )
        previewWindowController.failureHandler = { [weak self] error in
            self?.captureFailure = error
        }
        self.previewWindowController = previewWindowController

        try await previewWindowController.start(displayID: displayID)
        try await waitForRenderedFrame(previewWindowController)
        print("screen capture frame delivery: PASS")
        print("metal frame submission: PASS")

        if testsCursorPortal {
            try await verifyCursorPortal(
                displayID: displayID,
                previewWindowController: previewWindowController
            )
            print("preview cursor portal: PASS")
        }

        if measuresLatency {
            try await Task.sleep(for: .milliseconds(250))
            previewWindowController.resetLatencyMeasurements()
            try await runLatencyWorkload(displayID: displayID)
            try await Task.sleep(for: .milliseconds(500))
            try printLatencyReport(
                previewWindowController.latencySnapshot
            )
        } else {
            try await Task.sleep(for: visibleDuration)
        }
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
    ) async throws {
        guard let originalCursorLocation = CGEvent(source: nil)?.location else {
            throw PreviewProbeFailure(
                description: "Could not read the original cursor location"
            )
        }
        defer {
            restoreCursor(to: originalCursorLocation)
        }

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

        restoreCursor(to: originalCursorLocation)
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

    private func runLatencyWorkload(
        displayID: CGDirectDisplayID
    ) async throws {
        guard let originalCursorLocation = CGEvent(source: nil)?.location else {
            throw PreviewProbeFailure(
                description: "Could not read the original cursor location"
            )
        }
        defer {
            restoreCursor(to: originalCursorLocation)
        }

        let displayBounds = CGDisplayBounds(displayID)
        guard displayBounds.width > 0, displayBounds.height > 0 else {
            throw PreviewProbeFailure(
                description: "Virtual display has invalid cursor bounds"
            )
        }

        let margin = max(
            min(displayBounds.width, displayBounds.height) * 0.05,
            24
        )
        let horizontalRange = max(displayBounds.width - margin * 2, 1)
        let verticalAmplitude = max(displayBounds.height * 0.25, 1)
        let deadline = ContinuousClock.now.advanced(by: visibleDuration)
        var step = 0

        while ContinuousClock.now < deadline {
            if let captureFailure {
                throw captureFailure
            }

            let phase = CGFloat(step % 240) / 239
            let sweep = (step / 240).isMultiple(of: 2)
                ? phase
                : 1 - phase
            let point = CGPoint(
                x: margin + horizontalRange * sweep,
                y: displayBounds.height / 2
                    + CGFloat(sin(Double(step) * 0.08)) * verticalAmplitude
            )
            let result = CGDisplayMoveCursorToPoint(displayID, point)
            guard result == .success else {
                throw PreviewProbeFailure(
                    description: "Cursor workload failed with \(result)"
                )
            }

            step += 1
            try await Task.sleep(for: .milliseconds(8))
        }
    }

    private func restoreCursor(to globalPoint: CGPoint) {
        var displayID = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        guard
            CGGetDisplaysWithPoint(
                globalPoint,
                1,
                &displayID,
                &displayCount
            ) == .success,
            displayCount > 0
        else {
            return
        }

        let bounds = CGDisplayBounds(displayID)
        _ = CGDisplayMoveCursorToPoint(
            displayID,
            CGPoint(
                x: globalPoint.x - bounds.minX,
                y: globalPoint.y - bounds.minY
            )
        )
    }

    private func printLatencyReport(
        _ snapshot: PreviewLatencySnapshot?
    ) throws {
        guard let snapshot else {
            throw PreviewProbeFailure(
                description: "Latency measurement was not enabled"
            )
        }
        guard snapshot.presentedFrameCount >= 10 else {
            throw PreviewProbeFailure(
                description: """
                Only \(snapshot.presentedFrameCount) frames were presented; \
                at least 10 are required
                """
            )
        }

        print(
            "latency frames: captured=\(snapshot.capturedFrameCount) "
                + "coalesced=\(snapshot.coalescedFrameCount) "
                + "delivered=\(snapshot.deliveredFrameCount) "
                + "submitted=\(snapshot.submittedFrameCount) "
                + "render-dropped=\(snapshot.renderDropCount) "
                + "presented=\(snapshot.presentedFrameCount) "
                + "presentation-dropped=\(snapshot.presentationDropCount)"
        )
        printDistribution(
            "WindowServer displayTime -> capture",
            snapshot.sourceToCapture
        )
        printDistribution(
            "capture -> main",
            snapshot.captureToDelivery
        )
        printDistribution(
            "capture -> submit",
            snapshot.captureToSubmit
        )
        printDistribution(
            "GPU execution",
            snapshot.gpuExecution
        )
        printDistribution(
            "submit -> present",
            snapshot.submitToPresentation
        )
        printDistribution(
            "capture -> present",
            snapshot.captureToPresentation
        )
        printDistribution(
            "WindowServer displayTime -> present",
            snapshot.sourceToPresentation
        )
        printDistribution(
            "presentation interval",
            snapshot.presentationInterval
        )

        if let framesPerSecond = snapshot.effectiveFramesPerSecond {
            print(
                "effective presentation rate: "
                    + String(format: "%.2f fps", framesPerSecond)
            )
        }
    }

    private func printDistribution(
        _ label: String,
        _ distribution: PreviewMetricDistribution?
    ) {
        guard let distribution else {
            print("\(label): unavailable")
            return
        }

        print(
            "\(label): n=\(distribution.sampleCount) "
                + String(
                    format: "min=%.3f avg=%.3f p50=%.3f p95=%.3f "
                        + "p99=%.3f max=%.3f ms",
                    distribution.minimum,
                    distribution.average,
                    distribution.p50,
                    distribution.p95,
                    distribution.p99,
                    distribution.maximum
                )
        )
    }
}
