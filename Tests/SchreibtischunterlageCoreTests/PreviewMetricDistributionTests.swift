@testable import SchreibtischunterlageCore

enum PreviewMetricDistributionTests {
    static func run() throws {
        try calculatesInterpolatedPercentiles()
        try ignoresNonFiniteSamples()
        try rejectsEmptySamples()
    }

    private static func calculatesInterpolatedPercentiles() throws {
        let distribution = PreviewMetricDistribution(
            samples: [40, 0, 30, 10, 20]
        )

        try expect(distribution?.sampleCount == 5, "Expected five samples")
        try expect(distribution?.minimum == 0, "Expected minimum sample")
        try expect(distribution?.average == 20, "Expected sample average")
        try expect(distribution?.p50 == 20, "Expected median sample")
        try expect(distribution?.p95 == 38, "Expected interpolated p95")
        try expect(distribution?.p99 == 39.6, "Expected interpolated p99")
        try expect(distribution?.maximum == 40, "Expected maximum sample")
    }

    private static func ignoresNonFiniteSamples() throws {
        let distribution = PreviewMetricDistribution(
            samples: [1, .nan, .infinity, 3]
        )

        try expect(distribution?.sampleCount == 2, "Expected finite samples only")
        try expect(distribution?.average == 2, "Expected finite sample average")
    }

    private static func rejectsEmptySamples() throws {
        try expect(
            PreviewMetricDistribution(samples: []) == nil,
            "Expected empty samples to be rejected"
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw PreviewMetricDistributionTestFailure(description: message)
        }
    }
}

private struct PreviewMetricDistributionTestFailure:
    Error,
    CustomStringConvertible
{
    let description: String
}
