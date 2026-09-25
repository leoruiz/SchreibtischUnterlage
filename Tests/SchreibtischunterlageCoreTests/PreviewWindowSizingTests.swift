import CoreGraphics
@testable import SchreibtischunterlageCore

enum PreviewWindowSizingTests {
    static func run() throws {
        try capsLargeDisplays()
        try respectsAvailableHeight()
        try preservesUltrawideAspectRatio()
        try rejectsInvalidSizes()
    }

    private static func capsLargeDisplays() throws {
        let size = PreviewWindowSizing.initialContentSize(
            sourceSize: CGSize(width: 3360, height: 2100),
            availableSize: CGSize(width: 7680, height: 2100)
        )

        try expect(
            size == CGSize(width: 1800, height: 1125),
            "Expected large displays to use the maximum preview size"
        )
    }

    private static func respectsAvailableHeight() throws {
        let size = PreviewWindowSizing.initialContentSize(
            sourceSize: CGSize(width: 3360, height: 2100),
            availableSize: CGSize(width: 3840, height: 1080)
        )

        try expect(
            approximatelyEqual(size?.width, 1382.4),
            "Expected preview width to be constrained by available height"
        )
        try expect(size?.height == 864, "Expected 80 percent of available height")
    }

    private static func preservesUltrawideAspectRatio() throws {
        let size = PreviewWindowSizing.initialContentSize(
            sourceSize: CGSize(width: 5120, height: 1440),
            availableSize: CGSize(width: 7680, height: 2160)
        )

        try expect(size?.width == 1800, "Expected maximum preview width")
        try expect(
            approximatelyEqual(size?.height, 506.25),
            "Expected ultrawide aspect ratio to be preserved"
        )
    }

    private static func rejectsInvalidSizes() throws {
        try expect(
            PreviewWindowSizing.initialContentSize(
                sourceSize: .zero,
                availableSize: CGSize(width: 1920, height: 1080)
            ) == nil,
            "Expected invalid source size to be rejected"
        )
    }

    private static func approximatelyEqual(
        _ value: CGFloat?,
        _ expected: CGFloat,
        tolerance: CGFloat = 0.0001
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
            throw PreviewWindowSizingTestFailure(description: message)
        }
    }
}

private struct PreviewWindowSizingTestFailure: Error, CustomStringConvertible {
    let description: String
}

