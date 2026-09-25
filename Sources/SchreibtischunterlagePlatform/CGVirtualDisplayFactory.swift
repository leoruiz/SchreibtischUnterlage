import CGVirtualDisplayBridge
import CoreGraphics
import Foundation
import SchreibtischunterlageCore

public struct CGVirtualDisplayFactory: VirtualDisplayCreating {
    public let hardwareIdentity = VirtualDisplayHardwareIdentity(
        vendorID: 0x525A,
        productID: 0x5355,
        serialNumber: 1
    )

    public init() {}

    public func create(
        configuration: VirtualDisplayConfiguration
    ) throws -> any VirtualDisplaySession {
        let bridgeModes = configuration.modes.map {
            STUVirtualDisplayMode(
                width: UInt($0.width),
                height: UInt($0.height),
                refreshRate: $0.refreshRate
            )
        }
        let session = try STUVirtualDisplaySession(
            name: "Schreibtischunterlage Display",
            maxPixelsWide: UInt32(configuration.maxWidth),
            maxPixelsHigh: UInt32(configuration.maxHeight),
            sizeInMillimeters: CGSize(width: 1600, height: 1000),
            vendorID: hardwareIdentity.vendorID,
            productID: hardwareIdentity.productID,
            serialNumber: hardwareIdentity.serialNumber,
            modes: bridgeModes
        )

        return BridgeVirtualDisplaySession(session: session)
    }
}

private final class BridgeVirtualDisplaySession: VirtualDisplaySession {
    private var session: STUVirtualDisplaySession?

    var displayID: CGDirectDisplayID {
        session?.displayID ?? kCGNullDirectDisplay
    }

    init(session: STUVirtualDisplaySession) {
        self.session = session
    }

    func stop() throws {
        session?.stop()
        session = nil
    }
}
