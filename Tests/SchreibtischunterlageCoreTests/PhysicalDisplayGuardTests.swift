@testable import SchreibtischunterlageCore

enum PhysicalDisplayGuardTests {
    static func run() throws {
        try acceptsMatchingDisplay()
        try reportsMissingDisplay()
        try reportsAllUnexpectedChanges()
        try acceptsValuesWithinTolerance()
    }

    private static func acceptsMatchingDisplay() throws {
        let baseline = makeSnapshot()
        let guardPolicy = PhysicalDisplayGuard(baseline: baseline)

        try expect(
            guardPolicy.violations(in: [baseline]).isEmpty,
            "Expected matching display to pass validation"
        )
    }

    private static func reportsMissingDisplay() throws {
        let guardPolicy = PhysicalDisplayGuard(baseline: makeSnapshot())

        try expect(
            guardPolicy.violations(in: []) == [.displayMissing],
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
        let violations = PhysicalDisplayGuard(baseline: baseline).violations(in: [changed])

        try expect(violations.count == 4, "Expected four display violations")
        try expect(
            violations.contains(
                .resolutionChanged(
                    expectedWidth: 7680,
                    expectedHeight: 2160,
                    actualWidth: 5120,
                    actualHeight: 1440
                )
            ),
            "Expected a resolution violation"
        )
        try expect(
            violations.contains(.refreshRateChanged(expected: 120, actual: 60)),
            "Expected a refresh-rate violation"
        )
        try expect(
            violations.contains(.mainDisplayStateChanged(expected: true, actual: false)),
            "Expected a main-display violation"
        )
        try expect(
            violations.contains(
                .arrangementChanged(
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
            baseline: baseline,
            refreshRateTolerance: 0.5,
            arrangementTolerance: 0.5
        )

        try expect(
            guardPolicy.violations(in: [current]).isEmpty,
            "Expected values within tolerance to pass validation"
        )
    }

    private static func makeSnapshot(
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
                serialNumber: 0x5678
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
