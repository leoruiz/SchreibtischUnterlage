public enum PhysicalDisplayViolation: Equatable, Sendable {
    case displayMissing
    case resolutionChanged(
        expectedWidth: Int,
        expectedHeight: Int,
        actualWidth: Int,
        actualHeight: Int
    )
    case refreshRateChanged(expected: Double, actual: Double)
    case mainDisplayStateChanged(expected: Bool, actual: Bool)
    case arrangementChanged(
        expectedX: Double,
        expectedY: Double,
        actualX: Double,
        actualY: Double
    )
}

public struct PhysicalDisplayGuard: Sendable {
    public let baseline: PhysicalDisplaySnapshot
    public let refreshRateTolerance: Double
    public let arrangementTolerance: Double

    public init(
        baseline: PhysicalDisplaySnapshot,
        refreshRateTolerance: Double = 0.5,
        arrangementTolerance: Double = 0.5
    ) {
        self.baseline = baseline
        self.refreshRateTolerance = refreshRateTolerance
        self.arrangementTolerance = arrangementTolerance
    }

    public func violations(
        in snapshots: [PhysicalDisplaySnapshot]
    ) -> [PhysicalDisplayViolation] {
        guard let current = snapshots.first(where: { $0.identity == baseline.identity }) else {
            return [.displayMissing]
        }

        var violations: [PhysicalDisplayViolation] = []

        if
            current.pixelWidth != baseline.pixelWidth
                || current.pixelHeight != baseline.pixelHeight
        {
            violations.append(
                .resolutionChanged(
                    expectedWidth: baseline.pixelWidth,
                    expectedHeight: baseline.pixelHeight,
                    actualWidth: current.pixelWidth,
                    actualHeight: current.pixelHeight
                )
            )
        }

        if abs(current.refreshRate - baseline.refreshRate) > refreshRateTolerance {
            violations.append(
                .refreshRateChanged(
                    expected: baseline.refreshRate,
                    actual: current.refreshRate
                )
            )
        }

        if current.isMain != baseline.isMain {
            violations.append(
                .mainDisplayStateChanged(
                    expected: baseline.isMain,
                    actual: current.isMain
                )
            )
        }

        if
            abs(current.originX - baseline.originX) > arrangementTolerance
                || abs(current.originY - baseline.originY) > arrangementTolerance
        {
            violations.append(
                .arrangementChanged(
                    expectedX: baseline.originX,
                    expectedY: baseline.originY,
                    actualX: current.originX,
                    actualY: current.originY
                )
            )
        }

        return violations
    }
}

