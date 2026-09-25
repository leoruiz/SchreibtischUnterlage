import CoreGraphics
@testable import SchreibtischunterlageCore

@MainActor
enum DisplaySessionControllerTests {
    static func run() throws {
        try startsAndStopsOneDisplay()
        try refusesToStartWithoutBaselineDisplays()
        try refusesDuplicateManagedDisplay()
        try stopsWhenProtectedDisplayChanges()
        try ignoresAdditionalDisplays()
    }

    private static func startsAndStopsOneDisplay() throws {
        let physicalDisplay = makePhysicalDisplay()
        let provider = SnapshotProvider(snapshots: [physicalDisplay])
        let factory = DisplayFactory()
        let controller = DisplaySessionController(
            snapshotProvider: provider,
            displayFactory: factory
        )

        try controller.start(configuration: VirtualDisplayModeCatalog.standardConfiguration)
        try expect(controller.state == .active, "Expected active session")
        try expect(factory.sessions.count == 1, "Expected one virtual display")

        try controller.stop()
        try expect(controller.state == .inactive, "Expected inactive session")
        try expect(factory.sessions[0].didStop, "Expected virtual display teardown")
    }

    private static func refusesToStartWithoutBaselineDisplays() throws {
        let controller = DisplaySessionController(
            snapshotProvider: SnapshotProvider(snapshots: []),
            displayFactory: DisplayFactory()
        )

        do {
            try controller.start(configuration: VirtualDisplayModeCatalog.standardConfiguration)
            throw ControllerTestFailure(description: "Expected start to fail")
        } catch DisplaySessionControllerError.noBaselineDisplays {
            try expect(
                controller.state == .failed(.startFailed),
                "Expected visible start failure"
            )
        }
    }

    private static func refusesDuplicateManagedDisplay() throws {
        let factory = DisplayFactory()
        let existingDisplay = PhysicalDisplaySnapshot(
            identity: PhysicalDisplayIdentity(
                vendorID: factory.hardwareIdentity.vendorID,
                modelID: factory.hardwareIdentity.productID,
                serialNumber: factory.hardwareIdentity.serialNumber,
                unitNumber: 1
            ),
            pixelWidth: 2560,
            pixelHeight: 1600,
            refreshRate: 60,
            isMain: false,
            originX: -2560,
            originY: 0
        )
        let controller = DisplaySessionController(
            snapshotProvider: SnapshotProvider(snapshots: [
                makePhysicalDisplay(),
                existingDisplay,
            ]),
            displayFactory: factory
        )

        do {
            try controller.start(
                configuration: VirtualDisplayModeCatalog.standardConfiguration
            )
            throw ControllerTestFailure(description: "Expected duplicate start to fail")
        } catch DisplaySessionControllerError.managedDisplayAlreadyOnline(let identity) {
            try expect(
                identity == existingDisplay.identity,
                "Expected duplicate identity in error"
            )
            try expect(
                factory.sessions.isEmpty,
                "Expected no second virtual display creation"
            )
        }
    }

    private static func stopsWhenProtectedDisplayChanges() throws {
        let baseline = makePhysicalDisplay()
        let provider = SnapshotProvider(snapshots: [baseline])
        let factory = DisplayFactory()
        let controller = DisplaySessionController(
            snapshotProvider: provider,
            displayFactory: factory
        )

        try controller.start(configuration: VirtualDisplayModeCatalog.standardConfiguration)
        provider.currentSnapshots = [
            makePhysicalDisplay(pixelWidth: 5120, pixelHeight: 1440),
        ]

        let violations = try controller.handleDisplayConfigurationChange()

        try expect(!violations.isEmpty, "Expected physical display violation")
        try expect(controller.state == .inactive, "Expected automatic teardown")
        try expect(factory.sessions[0].didStop, "Expected display to stop")
    }

    private static func ignoresAdditionalDisplays() throws {
        let baseline = makePhysicalDisplay()
        let provider = SnapshotProvider(snapshots: [baseline])
        let factory = DisplayFactory()
        let controller = DisplaySessionController(
            snapshotProvider: provider,
            displayFactory: factory
        )

        try controller.start(configuration: VirtualDisplayModeCatalog.standardConfiguration)
        provider.currentSnapshots = [
            baseline,
            makePhysicalDisplay(unitNumber: 2, isMain: false, originX: 7680),
        ]

        let violations = try controller.handleDisplayConfigurationChange()

        try expect(violations.isEmpty, "Expected additional display to be ignored")
        try expect(controller.state == .active, "Expected session to remain active")
    }

    private static func makePhysicalDisplay(
        unitNumber: UInt32 = 1,
        pixelWidth: Int = 7680,
        pixelHeight: Int = 2160,
        isMain: Bool = true,
        originX: Double = 0
    ) -> PhysicalDisplaySnapshot {
        PhysicalDisplaySnapshot(
            identity: PhysicalDisplayIdentity(
                vendorID: 1,
                modelID: 2,
                serialNumber: 3,
                unitNumber: unitNumber
            ),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            refreshRate: 120,
            isMain: isMain,
            originX: originX,
            originY: 0
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw ControllerTestFailure(description: message)
        }
    }
}

private final class SnapshotProvider: PhysicalDisplaySnapshotProviding, @unchecked Sendable {
    var currentSnapshots: [PhysicalDisplaySnapshot]

    init(snapshots: [PhysicalDisplaySnapshot]) {
        currentSnapshots = snapshots
    }

    func snapshots() throws -> [PhysicalDisplaySnapshot] {
        currentSnapshots
    }
}

private final class DisplayFactory: VirtualDisplayCreating {
    let hardwareIdentity = VirtualDisplayHardwareIdentity(
        vendorID: 10,
        productID: 20,
        serialNumber: 30
    )
    private(set) var sessions: [DisplaySession] = []

    func create(
        configuration: VirtualDisplayConfiguration
    ) throws -> any VirtualDisplaySession {
        let session = DisplaySession()
        sessions.append(session)
        return session
    }
}

private final class DisplaySession: VirtualDisplaySession {
    let displayID: CGDirectDisplayID = 42
    private(set) var didStop = false

    func stop() throws {
        didStop = true
    }
}

private struct ControllerTestFailure: Error, CustomStringConvertible {
    let description: String
}
