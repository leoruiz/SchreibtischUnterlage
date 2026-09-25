import Foundation

public struct PreviewMetricDistribution: Equatable, Sendable {
    public let sampleCount: Int
    public let minimum: Double
    public let average: Double
    public let p50: Double
    public let p95: Double
    public let p99: Double
    public let maximum: Double

    public init?(samples: [Double]) {
        let sortedSamples = samples.filter(\.isFinite).sorted()
        guard
            let minimum = sortedSamples.first,
            let maximum = sortedSamples.last
        else {
            return nil
        }

        sampleCount = sortedSamples.count
        self.minimum = minimum
        average = sortedSamples.reduce(0, +) / Double(sortedSamples.count)
        p50 = Self.percentile(0.50, sortedSamples: sortedSamples)
        p95 = Self.percentile(0.95, sortedSamples: sortedSamples)
        p99 = Self.percentile(0.99, sortedSamples: sortedSamples)
        self.maximum = maximum
    }

    private static func percentile(
        _ percentile: Double,
        sortedSamples: [Double]
    ) -> Double {
        let position = Double(sortedSamples.count - 1) * percentile
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        guard lowerIndex != upperIndex else {
            return sortedSamples[lowerIndex]
        }

        let fraction = position - Double(lowerIndex)
        return sortedSamples[lowerIndex]
            + (sortedSamples[upperIndex] - sortedSamples[lowerIndex]) * fraction
    }
}
