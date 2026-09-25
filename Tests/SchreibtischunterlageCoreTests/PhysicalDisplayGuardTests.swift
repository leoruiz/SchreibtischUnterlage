@testable import SchreibtischunterlageCore

enum PhysicalDisplayGuardTests {
    static func run() throws {
        try acceptsMatchingDisplays()
        try reportsMissingDisplay()
        try reportsAllUnexpectedChanges()
        try acceptsValuesWithinTolerance()
        try ignoresDisplaysAddedAfterBaseline()
    }

    private static func acceptsMatchingDisplays() throws {
        let baselines = [
            makeSnapshot(unitNumber: 1),
            makeSnapshot(
                unitNumber: 2,
                pixelWidth: 3840,
                pixelHeight: 2160,
                refreshRate: 60,
                isMain: false,
                originX: 7680
            ),
        ]
        let guardPolicy = PhysicalDisplayGuard(baselines: baselines)

        try expect(
            guardPolicy.violations(in: baselines).isEmpty,
            "Expected matching displays to pass validation"
        )
    }

    private static func reportsMissingDisplay() throws {
        let baseline = makeSnapshot()
        let guardPolicy = PhysicalDisplayGuard(baselines: [baseline])

        try expect(
            guardPolicy.violations(in: []) == [
                .displayMissing(identity: baseline.identity),
            ],
            "Expected a missing display violation"
        )
    }

    private static func reportsAllUnexpectedChanges() throws {
        let baseline = makeSnapshot()
        let changed = makeSnapshot(
            pixelWidth: 5120,
            pixelHeight: 1440,
            refreshRate: 60,
            isMain: false,
            originX: 100,
            originY: 50
        )
        let violations = PhysicalDisplayGuard(baselines: [baseline]).violations(in: [changed])

        try expect(violations.count == 4, "Expected four display violations")
        try expect(
            violations.contains(
                .resolutionChanged(
                    identity: baseline.identity,
                    expectedWidth: 7680,
                    expectedHeight: 2160,
                    actualWidth: 5120,
                    actualHeight: 1440
                )
            ),
            "Expected a resolution violation"
        )
        try expect(
            violations.contains(
                .refreshRateChanged(
                    identity: baseline.identity,
                    expected: 120,
                    actual: 60
                )
            ),
            "Expected a refresh-rate violation"
        )
        try expect(
            violations.contains(
                .mainDisplayStateChanged(
                    identity: baseline.identity,
                    expected: true,
                    actual: false
                )
            ),
            "Expected a main-display violation"
        )
        try expect(
            violations.contains(
                .arrangementChanged(
                    identity: baseline.identity,
                    expectedX: 0,
                    expectedY: 0,
                    actualX: 100,
                    actualY: 50
                )
            ),
            "Expected an arrangement violation"
        )
    }

    private static func acceptsValuesWithinTolerance() throws {
        let baseline = makeSnapshot()
        let current = makeSnapshot(
            refreshRate: 119.75,
            originX: 0.25,
            originY: -0.25
        )
        let guardPolicy = PhysicalDisplayGuard(
            baselines: [baseline],
            refreshRateTolerance: 0.5,
            arrangementTolerance: 0.5
        )

        try expect(
            guardPolicy.violations(in: [current]).isEmpty,
            "Expected values within tolerance to pass validation"
        )
    }

    private static func ignoresDisplaysAddedAfterBaseline() throws {
        let baseline = makeSnapshot()
        let added = makeSnapshot(unitNumber: 2, isMain: false, originX: 7680)
        let guardPolicy = PhysicalDisplayGuard(baselines: [baseline])

        try expect(
            guardPolicy.violations(in: [baseline, added]).isEmpty,
            "Expected displays added after baseline not to invalidate protected displays"
        )
    }

    private static func makeSnapshot(
        unitNumber: UInt32 = 1,
        pixelWidth: Int = 7680,
        pixelHeight: Int = 2160,
        refreshRate: Double = 120,
        isMain: Bool = true,
        originX: Double = 0,
        originY: Double = 0
    ) -> PhysicalDisplaySnapshot {
        PhysicalDisplaySnapshot(
            identity: PhysicalDisplayIdentity(
                vendorID: 0x4C2D,
                modelID: 0x1234,
                serialNumber: 0x5678,
                unitNumber: unitNumber
            ),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            refreshRate: refreshRate,
            isMain: isMain,
            originX: originX,
            originY: originY
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw PhysicalDisplayGuardTestFailure(description: message)
        }
    }
}

private struct PhysicalDisplayGuardTestFailure: Error, CustomStringConvertible {
    let description: String
}
