public struct PreviewSurfacingDebouncer: Sendable {
    public private(set) var isWithinVirtualDisplay = false

    private let requiredConsecutiveSamples: Int
    private var candidateState: Bool?
    private var candidateSampleCount = 0

    public init(requiredConsecutiveSamples: Int = 2) {
        self.requiredConsecutiveSamples = max(
            requiredConsecutiveSamples,
            1
        )
    }

    public mutating func observe(
        isWithinVirtualDisplay observedState: Bool
    ) -> Bool? {
        guard observedState != isWithinVirtualDisplay else {
            candidateState = nil
            candidateSampleCount = 0
            return nil
        }

        if candidateState == observedState {
            candidateSampleCount += 1
        } else {
            candidateState = observedState
            candidateSampleCount = 1
        }

        guard candidateSampleCount >= requiredConsecutiveSamples else {
            return nil
        }

        isWithinVirtualDisplay = observedState
        candidateState = nil
        candidateSampleCount = 0
        return observedState
    }

    public mutating func reset() {
        isWithinVirtualDisplay = false
        candidateState = nil
        candidateSampleCount = 0
    }
}
