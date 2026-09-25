@testable import SchreibtischUnterlageCore

enum VirtualDisplayModeTests {
    static func run() throws {
        try rejectsInvalidModes()
        try catalogContainsUniqueModes()
        try fallbackModeIsAvailable()
        try preferredModeIsAdvertisedFirst()
        try selectsModeMatchingHostDisplay()
        try selectsClosestAvailableMode()
        try persistedModeTakesPriority()
        try rejectsUnavailablePreferredMode()
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

    private static func fallbackModeIsAvailable() throws {
        try expect(
            VirtualDisplayModeCatalog.standard.contains(
                VirtualDisplayModeCatalog.fallbackMode
            ),
            "Expected fallback mode in catalog"
        )
    }

    private static func preferredModeIsAdvertisedFirst() throws {
        let preferredMode = VirtualDisplayModeCatalog.mode(
            width: 3440,
            height: 1440
        )!
        let configuration = VirtualDisplayModeCatalog.configuration(
            preferredMode: preferredMode
        )!

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

    private static func selectsModeMatchingHostDisplay() throws {
        try expect(
            VirtualDisplayModeCatalog.bestMode(
                forPixelWidth: 1920,
                pixelHeight: 1080
            ) == VirtualDisplayModeCatalog.mode(width: 1920, height: 1080),
            "Expected exact 1080p match"
        )
        try expect(
            VirtualDisplayModeCatalog.bestMode(
                forPixelWidth: 7680,
                pixelHeight: 2160
            ) == VirtualDisplayModeCatalog.mode(width: 5120, height: 1440),
            "Expected matching 32:9 mode"
        )
        try expect(
            VirtualDisplayModeCatalog.bestMode(
                forPixelWidth: 3024,
                pixelHeight: 1964
            ) == VirtualDisplayModeCatalog.mode(width: 2560, height: 1600),
            "Expected closest 16:10 mode"
        )
    }

    private static func rejectsUnavailablePreferredMode() throws {
        let unavailableMode = VirtualDisplayMode(
            width: 1000,
            height: 1000,
            refreshRate: 60
        )!
        try expect(
            VirtualDisplayModeCatalog.configuration(
                preferredMode: unavailableMode
            ) == nil,
            "Expected unavailable preferred mode to be rejected"
        )
    }

    private static func selectsClosestAvailableMode() throws {
        let candidates = [
            VirtualDisplayModeCatalog.mode(width: 1920, height: 1080)!,
            VirtualDisplayModeCatalog.mode(width: 2560, height: 720)!,
            VirtualDisplayModeCatalog.mode(width: 2560, height: 1080)!,
        ]
        try expect(
            VirtualDisplayModeCatalog.bestMode(
                among: candidates,
                forPixelWidth: 5120,
                pixelHeight: 1440
            ) == VirtualDisplayModeCatalog.mode(
                width: 2560,
                height: 720
            ),
            "Expected closest published 32:9 mode"
        )
    }

    private static func persistedModeTakesPriority() throws {
        let persistedMode = VirtualDisplayModeCatalog.mode(
            width: 3440,
            height: 1440
        )!
        let secondaryDisplay = PhysicalDisplaySnapshot(
            identity: PhysicalDisplayIdentity(
                vendorID: 1,
                modelID: 2,
                serialNumber: 3,
                unitNumber: 4
            ),
            pixelWidth: 1920,
            pixelHeight: 1080,
            refreshRate: 60,
            isMain: false,
            originX: 0,
            originY: 0
        )
        let mainDisplay = PhysicalDisplaySnapshot(
            identity: PhysicalDisplayIdentity(
                vendorID: 5,
                modelID: 6,
                serialNumber: 7,
                unitNumber: 8
            ),
            pixelWidth: 7680,
            pixelHeight: 2160,
            refreshRate: 120,
            isMain: true,
            originX: 1920,
            originY: 0
        )
        let physicalDisplays = [
            secondaryDisplay,
            mainDisplay,
        ]

        try expect(
            VirtualDisplayModeCatalog.preferredMode(
                persistedMode: persistedMode,
                physicalDisplays: physicalDisplays
            ) == persistedMode,
            "Expected persisted mode to take priority"
        )
        try expect(
            VirtualDisplayModeCatalog.preferredMode(
                persistedMode: nil,
                physicalDisplays: physicalDisplays
            ) == VirtualDisplayModeCatalog.mode(
                width: 5120,
                height: 1440
            ),
            "Expected the main physical display to determine the initial mode"
        )
        try expect(
            VirtualDisplayModeCatalog.preferredMode(
                persistedMode: nil,
                physicalDisplays: []
            ) == VirtualDisplayModeCatalog.fallbackMode,
            "Expected fallback without a physical display"
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
