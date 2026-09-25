import CoreGraphics
@testable import SchreibtischUnterlageCore

enum PreviewCoordinateMapperTests {
    static func run() throws {
        try mapsPreviewCenterToDisplayCenter()
        try flipsAppKitVerticalCoordinates()
        try ignoresLetterboxClicks()
        try mapsPillarboxedContent()
    }

    private static func mapsPreviewCenterToDisplayCenter() throws {
        let point = PreviewCoordinateMapper.displayLocalPoint(
            previewPoint: CGPoint(x: 480, y: 300),
            previewSize: CGSize(width: 960, height: 600),
            sourceSize: CGSize(width: 3360, height: 2100),
            displaySize: CGSize(width: 1680, height: 1050)
        )

        try expect(point == CGPoint(x: 840, y: 525), "Expected display center")
    }

    private static func flipsAppKitVerticalCoordinates() throws {
        let topLeft = PreviewCoordinateMapper.displayLocalPoint(
            previewPoint: CGPoint(x: 0, y: 599),
            previewSize: CGSize(width: 960, height: 600),
            sourceSize: CGSize(width: 3360, height: 2100),
            displaySize: CGSize(width: 1680, height: 1050)
        )
        let bottomLeft = PreviewCoordinateMapper.displayLocalPoint(
            previewPoint: CGPoint(x: 0, y: 0),
            previewSize: CGSize(width: 960, height: 600),
            sourceSize: CGSize(width: 3360, height: 2100),
            displaySize: CGSize(width: 1680, height: 1050)
        )

        try expect(
            approximatelyEqual(topLeft?.y, 1.75),
            "Expected preview top to map near display top"
        )
        try expect(
            bottomLeft?.y == 1049.5,
            "Expected preview bottom to map inside display bottom edge"
        )
    }

    private static func ignoresLetterboxClicks() throws {
        let point = PreviewCoordinateMapper.displayLocalPoint(
            previewPoint: CGPoint(x: 500, y: 900),
            previewSize: CGSize(width: 1000, height: 1000),
            sourceSize: CGSize(width: 2560, height: 1080),
            displaySize: CGSize(width: 2560, height: 1080)
        )

        try expect(point == nil, "Expected letterbox click to be ignored")
    }

    private static func mapsPillarboxedContent() throws {
        let point = PreviewCoordinateMapper.displayLocalPoint(
            previewPoint: CGPoint(x: 500, y: 250),
            previewSize: CGSize(width: 1000, height: 500),
            sourceSize: CGSize(width: 1000, height: 1600),
            displaySize: CGSize(width: 1000, height: 1600)
        )

        try expect(point == CGPoint(x: 500, y: 800), "Expected mapped content center")
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
            throw PreviewCoordinateMapperTestFailure(description: message)
        }
    }
}

private struct PreviewCoordinateMapperTestFailure:
    Error,
    CustomStringConvertible
{
    let description: String
}
