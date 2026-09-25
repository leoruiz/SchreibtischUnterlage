import AppKit
import CoreGraphics
import Darwin
import Foundation
import SchreibtischunterlageCore
import SchreibtischunterlagePlatform

private struct DisplayProbeFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
final class DisplayProbe: NSObject, NSApplicationDelegate {
    private(set) var exitCode = EXIT_FAILURE
    private var controller: DisplaySessionController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await run()
                exitCode = EXIT_SUCCESS
            } catch {
                fputs("display probe failed: \(error)\n", stderr)
            }
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stopIfNeeded()
    }

    private func run() async throws {
        let snapshotProvider = CoreGraphicsPhysicalDisplaySnapshotProvider()
        let baseline = try snapshotProvider.snapshots()
        guard !baseline.isEmpty else {
            throw DisplayProbeFailure(description: "No baseline displays found")
        }

        let controller = DisplaySessionController(
            snapshotProvider: snapshotProvider,
            displayFactory: CGVirtualDisplayFactory()
        )
        self.controller = controller
        defer {
            controller.stopIfNeeded()
            self.controller = nil
        }

        print("baseline displays: \(baseline.count)")
        try controller.start(
            configuration: VirtualDisplayModeCatalog.standardConfiguration
        )

        guard let displayID = controller.activeDisplayID else {
            throw DisplayProbeFailure(description: "Virtual display has no display ID")
        }
        print("virtual display created: id=\(displayID)")

        let activeMode = try await Self.waitForDisplayMode(displayID: displayID)
        print(
            "virtual display online: "
                + "\(activeMode.pixelWidth)x\(activeMode.pixelHeight) "
                + "@\(activeMode.refreshRate)"
        )

        try await Task.sleep(for: .seconds(3))
        try controller.stop()
        try await Self.waitForDisplayRemoval(displayID: displayID)

        let finalSnapshots = try snapshotProvider.snapshots()
        let violations = PhysicalDisplayGuard(baselines: baseline).violations(
            in: finalSnapshots
        )
        guard violations.isEmpty else {
            throw DisplayProbeFailure(
                description: "Physical display configuration changed: \(violations)"
            )
        }

        print("physical displays unchanged: PASS")
        print("virtual display teardown: PASS")
    }

    private static func waitForDisplayMode(
        displayID: CGDirectDisplayID
    ) async throws -> CGDisplayMode {
        for _ in 0..<100 {
            if
                onlineDisplayIDs().contains(displayID),
                let mode = CGDisplayCopyDisplayMode(displayID)
            {
                return mode
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        throw DisplayProbeFailure(
            description: "Virtual display did not become available within 10 seconds"
        )
    }

    private static func waitForDisplayRemoval(
        displayID: CGDirectDisplayID
    ) async throws {
        for _ in 0..<50 {
            if !onlineDisplayIDs().contains(displayID) {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        throw DisplayProbeFailure(
            description: "Virtual display remained online after Stop"
        )
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
            return []
        }

        var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard
            CGGetOnlineDisplayList(count, &displayIDs, &count) == .success
        else {
            return []
        }

        return Array(displayIDs.prefix(Int(count)))
    }
}
