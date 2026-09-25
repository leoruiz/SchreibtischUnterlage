import Foundation

public struct VirtualDisplayMode: Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let refreshRate: Double

    public init?(width: Int, height: Int, refreshRate: Double) {
        guard
            width > 0,
            height > 0,
            width <= UInt32.max,
            height <= UInt32.max,
            refreshRate > 0
        else {
            return nil
        }

        self.width = width
        self.height = height
        self.refreshRate = refreshRate
    }

    public var displayName: String {
        "\(width) × \(height) @ \(refreshRate.formatted(.number.precision(.fractionLength(0)))) Hz"
    }
}

public struct VirtualDisplayHardwareIdentity: Equatable, Sendable {
    public let vendorID: UInt32
    public let productID: UInt32
    public let serialNumber: UInt32

    public init(vendorID: UInt32, productID: UInt32, serialNumber: UInt32) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
    }

    public func matches(_ identity: PhysicalDisplayIdentity) -> Bool {
        identity.vendorID == vendorID
            && identity.modelID == productID
            && identity.serialNumber == serialNumber
    }
}

public struct VirtualDisplayConfiguration: Equatable, Sendable {
    public let preferredMode: VirtualDisplayMode
    public let modes: [VirtualDisplayMode]

    public init?(
        preferredMode: VirtualDisplayMode,
        modes: [VirtualDisplayMode]
    ) {
        let uniqueModes = Array(Set(modes))
        guard
            !uniqueModes.isEmpty,
            uniqueModes.contains(preferredMode)
        else {
            return nil
        }

        self.preferredMode = preferredMode
        let remainingModes = uniqueModes
            .filter { $0 != preferredMode }
            .sorted {
                ($0.width, $0.height, $0.refreshRate)
                    < ($1.width, $1.height, $1.refreshRate)
            }
        self.modes = [preferredMode] + remainingModes
    }

    public var maxWidth: Int {
        modes.map(\.width).max() ?? preferredMode.width
    }

    public var maxHeight: Int {
        modes.map(\.height).max() ?? preferredMode.height
    }
}

public enum VirtualDisplayModeCatalog {
    public static let fallbackMode = requiredMode(width: 1920, height: 1080)

    public static let standard: [VirtualDisplayMode] = [
        requiredMode(width: 1280, height: 720),
        requiredMode(width: 1280, height: 800),
        requiredMode(width: 1440, height: 900),
        requiredMode(width: 1600, height: 900),
        requiredMode(width: 1680, height: 1050),
        fallbackMode,
        requiredMode(width: 1920, height: 1200),
        requiredMode(width: 2560, height: 720),
        requiredMode(width: 2560, height: 1080),
        requiredMode(width: 2560, height: 1440),
        requiredMode(width: 2560, height: 1600),
        requiredMode(width: 3440, height: 1440),
        requiredMode(width: 3840, height: 1080),
        requiredMode(width: 3840, height: 1600),
        requiredMode(width: 3840, height: 2160),
        requiredMode(width: 5120, height: 1440),
    ]

    public static let fallbackConfiguration = VirtualDisplayConfiguration(
        preferredMode: fallbackMode,
        modes: standard
    )!

    public static func configuration(
        preferredMode: VirtualDisplayMode
    ) -> VirtualDisplayConfiguration? {
        VirtualDisplayConfiguration(
            preferredMode: preferredMode,
            modes: standard
        )
    }

    public static func mode(
        width: Int,
        height: Int
    ) -> VirtualDisplayMode? {
        standard.first {
            $0.width == width && $0.height == height
        }
    }

    public static func bestMode(
        forPixelWidth pixelWidth: Int,
        pixelHeight: Int
    ) -> VirtualDisplayMode {
        bestMode(
            among: standard,
            forPixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        ) ?? fallbackMode
    }

    public static func bestMode(
        among candidates: [VirtualDisplayMode],
        forPixelWidth pixelWidth: Int,
        pixelHeight: Int
    ) -> VirtualDisplayMode? {
        guard pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }

        return candidates.min {
            let leftScore = matchScore(
                mode: $0,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
            let rightScore = matchScore(
                mode: $1,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
            if abs(leftScore - rightScore) > 0.000_001 {
                return leftScore < rightScore
            }
            return $0.width * $0.height > $1.width * $1.height
        }
    }

    public static func preferredMode(
        persistedMode: VirtualDisplayMode?,
        physicalDisplays: [PhysicalDisplaySnapshot]
    ) -> VirtualDisplayMode {
        if let persistedMode, standard.contains(persistedMode) {
            return persistedMode
        }

        guard
            let hostDisplay =
                physicalDisplays.first(where: \.isMain)
                ?? physicalDisplays.first
        else {
            return fallbackMode
        }

        return bestMode(
            forPixelWidth: hostDisplay.pixelWidth,
            pixelHeight: hostDisplay.pixelHeight
        )
    }

    private static func matchScore(
        mode: VirtualDisplayMode,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> Double {
        let displayAspectRatio = Double(pixelWidth) / Double(pixelHeight)
        let modeAspectRatio = Double(mode.width) / Double(mode.height)
        let aspectRatioError = abs(log(modeAspectRatio / displayAspectRatio))

        let displayPixelCount = Double(pixelWidth * pixelHeight)
        let modePixelCount = Double(mode.width * mode.height)
        let pixelCountError = abs(log(modePixelCount / displayPixelCount))

        let exceedsDisplay =
            mode.width > pixelWidth || mode.height > pixelHeight
        return aspectRatioError * 8
            + pixelCountError
            + (exceedsDisplay ? 0.25 : 0)
    }

    private static func requiredMode(
        width: Int,
        height: Int,
        refreshRate: Double = 60
    ) -> VirtualDisplayMode {
        guard let mode = VirtualDisplayMode(
            width: width,
            height: height,
            refreshRate: refreshRate
        ) else {
            preconditionFailure("Invalid built-in virtual display mode")
        }
        return mode
    }
}
