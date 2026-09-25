public enum PhysicalDisplayViolation: Equatable, Sendable {
    case displayMissing(identity: PhysicalDisplayIdentity)
    case resolutionChanged(
        identity: PhysicalDisplayIdentity,
        expectedWidth: Int,
        expectedHeight: Int,
        actualWidth: Int,
        actualHeight: Int
    )
    case refreshRateChanged(
        identity: PhysicalDisplayIdentity,
        expected: Double,
        actual: Double
    )
    case mainDisplayStateChanged(
        identity: PhysicalDisplayIdentity,
        expected: Bool,
        actual: Bool
    )
    case arrangementChanged(
        identity: PhysicalDisplayIdentity,
        expectedX: Double,
        expectedY: Double,
        actualX: Double,
        actualY: Double
    )
}

public struct PhysicalDisplayGuard: Sendable {
    public let baselines: [PhysicalDisplaySnapshot]
    public let refreshRateTolerance: Double
    public let arrangementTolerance: Double

    public init(
        baselines: [PhysicalDisplaySnapshot],
        refreshRateTolerance: Double = 0.5,
        arrangementTolerance: Double = 0.5
    ) {
        self.baselines = baselines
        self.refreshRateTolerance = refreshRateTolerance
        self.arrangementTolerance = arrangementTolerance
    }

    public func violations(
        in snapshots: [PhysicalDisplaySnapshot]
    ) -> [PhysicalDisplayViolation] {
        var currentByIdentity: [PhysicalDisplayIdentity: PhysicalDisplaySnapshot] = [:]
        for snapshot in snapshots {
            currentByIdentity[snapshot.identity] = snapshot
        }

        var violations: [PhysicalDisplayViolation] = []
        for baseline in baselines {
            guard let current = currentByIdentity[baseline.identity] else {
                violations.append(.displayMissing(identity: baseline.identity))
                continue
            }

            if
                current.pixelWidth != baseline.pixelWidth
                || current.pixelHeight != baseline.pixelHeight
            {
                violations.append(
                    .resolutionChanged(
                        identity: baseline.identity,
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
                        identity: baseline.identity,
                        expected: baseline.refreshRate,
                        actual: current.refreshRate
                    )
                )
            }

            if current.isMain != baseline.isMain {
                violations.append(
                    .mainDisplayStateChanged(
                        identity: baseline.identity,
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
                        identity: baseline.identity,
                        expectedX: baseline.originX,
                        expectedY: baseline.originY,
                        actualX: current.originX,
                        actualY: current.originY
                    )
                )
            }
        }

        return violations
    }
}
