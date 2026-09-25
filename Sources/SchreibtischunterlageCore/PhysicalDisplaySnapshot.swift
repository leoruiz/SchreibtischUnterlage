import CoreGraphics

public struct PhysicalDisplayIdentity: Equatable, Hashable, Sendable {
    public let vendorID: UInt32
    public let modelID: UInt32
    public let serialNumber: UInt32

    public init(vendorID: UInt32, modelID: UInt32, serialNumber: UInt32) {
        self.vendorID = vendorID
        self.modelID = modelID
        self.serialNumber = serialNumber
    }
}

public struct PhysicalDisplaySnapshot: Equatable, Sendable {
    public let identity: PhysicalDisplayIdentity
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isMain: Bool
    public let originX: Double
    public let originY: Double

    public init(
        identity: PhysicalDisplayIdentity,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        isMain: Bool,
        originX: Double,
        originY: Double
    ) {
        self.identity = identity
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.isMain = isMain
        self.originX = originX
        self.originY = originY
    }
}

public enum PhysicalDisplaySnapshotError: Error, Equatable, Sendable {
    case enumerationFailed(CGError)
    case modeUnavailable(CGDirectDisplayID)
}

public protocol PhysicalDisplaySnapshotProviding: Sendable {
    func snapshots() throws -> [PhysicalDisplaySnapshot]
}

public struct CoreGraphicsPhysicalDisplaySnapshotProvider: PhysicalDisplaySnapshotProviding {
    public init() {}

    public func snapshots() throws -> [PhysicalDisplaySnapshot] {
        var displayCount: UInt32 = 0
        let countResult = CGGetOnlineDisplayList(0, nil, &displayCount)
        guard countResult == .success else {
            throw PhysicalDisplaySnapshotError.enumerationFailed(countResult)
        }

        var displayIDs = Array(
            repeating: CGDirectDisplayID(),
            count: Int(displayCount)
        )
        let listResult = CGGetOnlineDisplayList(
            displayCount,
            &displayIDs,
            &displayCount
        )
        guard listResult == .success else {
            throw PhysicalDisplaySnapshotError.enumerationFailed(listResult)
        }

        return try displayIDs.prefix(Int(displayCount)).map(snapshot(for:))
    }

    private func snapshot(for displayID: CGDirectDisplayID) throws -> PhysicalDisplaySnapshot {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            throw PhysicalDisplaySnapshotError.modeUnavailable(displayID)
        }

        let bounds = CGDisplayBounds(displayID)
        return PhysicalDisplaySnapshot(
            identity: PhysicalDisplayIdentity(
                vendorID: CGDisplayVendorNumber(displayID),
                modelID: CGDisplayModelNumber(displayID),
                serialNumber: CGDisplaySerialNumber(displayID)
            ),
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate,
            isMain: CGDisplayIsMain(displayID) != 0,
            originX: bounds.origin.x,
            originY: bounds.origin.y
        )
    }
}

