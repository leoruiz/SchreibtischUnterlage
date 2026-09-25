import CoreGraphics
@testable import SchreibtischunterlageCore

enum PreviewWindowSizingTests {
    static func run() throws {
        try scalesWithLargeDesktops()
        try respectsAvailableHeight()
        try preservesUltrawideAspectRatio()
        try enlargesLowResolutionDisplays()
        try preservesWidthAcrossAspectChanges()
        try constrainsPreservedWidthToAvailableHeight()
        try rejectsInvalidSizes()
    }

    private static func scalesWithLargeDesktops() throws {
        let size = PreviewWindowSizing.initialContentSize(
            sourceSize: CGSize(width: 3360, height: 2100),
            availableSize: CGSize(width: 7680, height: 2100)
        )

        try expect(
            size == CGSize(width: 3024, height: 1890),
            "Expected preview size to scale with the available desktop"
        )
    }

    private static func respectsAvailableHeight() throws {
        let size = PreviewWindowSizing.initialContentSize(
            sourceSize: CGSize(width: 3360, height: 2100),
            availableSize: CGSize(width: 3840, height: 1080)
        )

        try expect(
            approximatelyEqual(size?.width, 1555.2),
            "Expected preview width to be constrained by available height"
        )
        try expect(size?.height == 972, "Expected 90 percent of available height")
    }

    private static func preservesUltrawideAspectRatio() throws {
        let size = PreviewWindowSizing.initialContentSize(
            sourceSize: CGSize(width: 5120, height: 1440),
            availableSize: CGSize(width: 7680, height: 2160)
        )

        try expect(size?.width == 6144, "Expected 80 percent of available width")
        try expect(
            approximatelyEqual(size?.height, 1728),
            "Expected ultrawide aspect ratio to be preserved"
        )
    }

    private static func enlargesLowResolutionDisplays() throws {
        let size = PreviewWindowSizing.initialContentSize(
            sourceSize: CGSize(width: 800, height: 600),
            availableSize: CGSize(width: 3840, height: 1080)
        )

        try expect(
            approximatelyEqual(size?.width, 1296),
            "Expected low-resolution display width to fill the startup target"
        )
        try expect(
            approximatelyEqual(size?.height, 972),
            "Expected low-resolution display height to fill the startup target"
        )
    }

    private static func preservesWidthAcrossAspectChanges() throws {
        let size = PreviewWindowSizing.contentSizePreservingWidth(
            sourceSize: CGSize(width: 3440, height: 1440),
            currentContentSize: CGSize(width: 1800, height: 1125),
            availableSize: CGSize(width: 7680, height: 2100)
        )

        try expect(size?.width == 1800, "Expected current width to be preserved")
        try expect(
            approximatelyEqual(size?.height, 753.488372),
            "Expected height to follow the new aspect ratio"
        )
    }

    private static func constrainsPreservedWidthToAvailableHeight() throws {
        let size = PreviewWindowSizing.contentSizePreservingWidth(
            sourceSize: CGSize(width: 1280, height: 1600),
            currentContentSize: CGSize(width: 1800, height: 1000),
            availableSize: CGSize(width: 1920, height: 900)
        )

        try expect(size?.height == 900, "Expected height to fit the screen")
        try expect(size?.width == 720, "Expected width to retain source aspect")
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
