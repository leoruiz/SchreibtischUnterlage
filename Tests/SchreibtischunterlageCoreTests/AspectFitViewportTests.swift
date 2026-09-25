@testable import SchreibtischunterlageCore

enum AspectFitViewportTests {
    static func run() throws {
        try fitsMatchingAspectRatio()
        try letterboxesWideSource()
        try pillarboxesTallSource()
        try rejectsInvalidDimensions()
    }

    private static func fitsMatchingAspectRatio() throws {
        let viewport = AspectFitViewport(
            sourceWidth: 1920,
            sourceHeight: 1080,
            destinationWidth: 1280,
            destinationHeight: 720
        )

        try expect(viewport?.originX == 0, "Expected zero horizontal offset")
        try expect(viewport?.originY == 0, "Expected zero vertical offset")
        try expect(viewport?.width == 1280, "Expected full destination width")
        try expect(viewport?.height == 720, "Expected full destination height")
    }

    private static func letterboxesWideSource() throws {
        let viewport = AspectFitViewport(
            sourceWidth: 2560,
            sourceHeight: 1080,
            destinationWidth: 1000,
            destinationHeight: 1000
        )

        try expect(viewport?.originX == 0, "Expected full destination width")
        try expect(viewport?.width == 1000, "Expected full destination width")
        try expect(
            approximatelyEqual(viewport?.height, 421.875),
            "Expected aspect-fitted height"
        )
        try expect(
            approximatelyEqual(viewport?.originY, 289.0625),
            "Expected vertical centering"
        )
    }

    private static func pillarboxesTallSource() throws {
        let viewport = AspectFitViewport(
            sourceWidth: 1000,
            sourceHeight: 1600,
            destinationWidth: 1000,
            destinationHeight: 500
        )

        try expect(viewport?.originY == 0, "Expected full destination height")
        try expect(viewport?.height == 500, "Expected full destination height")
        try expect(
            approximatelyEqual(viewport?.width, 312.5),
            "Expected aspect-fitted width"
        )
        try expect(
            approximatelyEqual(viewport?.originX, 343.75),
            "Expected horizontal centering"
        )
    }

    private static func rejectsInvalidDimensions() throws {
        try expect(
            AspectFitViewport(
                sourceWidth: 0,
                sourceHeight: 1080,
                destinationWidth: 1280,
                destinationHeight: 720
            ) == nil,
            "Expected invalid source dimensions to be rejected"
        )
    }

    private static func approximatelyEqual(
        _ value: Double?,
        _ expected: Double,
        tolerance: Double = 0.0001
    ) -> Bool {
        guard let value else {
            return false
        }
        return abs(value - expected) <= tolerance
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw AspectFitViewportTestFailure(description: message)
        }
    }
}

private struct AspectFitViewportTestFailure: Error, CustomStringConvertible {
    let description: String
}
