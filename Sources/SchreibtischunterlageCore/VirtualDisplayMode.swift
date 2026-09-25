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
    public static let defaultMode = requiredMode(width: 2560, height: 1600)

    public static let standard: [VirtualDisplayMode] = [
        requiredMode(width: 1280, height: 720),
        requiredMode(width: 1280, height: 800),
        requiredMode(width: 1440, height: 900),
        requiredMode(width: 1600, height: 900),
        requiredMode(width: 1680, height: 1050),
        requiredMode(width: 1920, height: 1080),
        requiredMode(width: 1920, height: 1200),
        requiredMode(width: 2560, height: 1440),
        defaultMode,
        requiredMode(width: 3440, height: 1440),
        requiredMode(width: 3840, height: 1600),
        requiredMode(width: 3840, height: 2160),
        requiredMode(width: 5120, height: 1440),
    ]

    public static let standardConfiguration = VirtualDisplayConfiguration(
        preferredMode: defaultMode,
        modes: standard
    )!

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
