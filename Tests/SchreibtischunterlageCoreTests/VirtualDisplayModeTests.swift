@testable import SchreibtischunterlageCore

enum VirtualDisplayModeTests {
    static func run() throws {
        try rejectsInvalidModes()
        try catalogContainsUniqueModes()
        try defaultModeIsAvailable()
        try preferredModeIsAdvertisedFirst()
    }

    private static func rejectsInvalidModes() throws {
        try expect(
            VirtualDisplayMode(width: 0, height: 1080, refreshRate: 60) == nil,
            "Expected zero width to be rejected"
        )
        try expect(
            VirtualDisplayMode(width: 1920, height: -1, refreshRate: 60) == nil,
            "Expected negative height to be rejected"
        )
        try expect(
            VirtualDisplayMode(width: 1920, height: 1080, refreshRate: 0) == nil,
            "Expected zero refresh rate to be rejected"
        )
    }

    private static func catalogContainsUniqueModes() throws {
        try expect(
            Set(VirtualDisplayModeCatalog.standard).count
                == VirtualDisplayModeCatalog.standard.count,
            "Expected unique catalog modes"
        )
    }

    private static func defaultModeIsAvailable() throws {
        try expect(
            VirtualDisplayModeCatalog.standard.contains(VirtualDisplayModeCatalog.defaultMode),
            "Expected default mode in catalog"
        )
    }

    private static func preferredModeIsAdvertisedFirst() throws {
        let configuration = VirtualDisplayModeCatalog.standardConfiguration

        try expect(
            configuration.modes.first == configuration.preferredMode,
            "Expected preferred mode to be advertised first"
        )
        try expect(
            configuration.maxWidth == 5120,
            "Expected maximum catalog width"
        )
        try expect(
            configuration.maxHeight == 2160,
            "Expected maximum catalog height"
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw ModeTestFailure(description: message)
        }
    }
}

private struct ModeTestFailure: Error, CustomStringConvertible {
    let description: String
}
