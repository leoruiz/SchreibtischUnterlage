import CoreGraphics

public protocol VirtualDisplaySession: AnyObject {
    var displayID: CGDirectDisplayID { get }
    func stop() throws
}

public protocol VirtualDisplayCreating {
    func create(
        configuration: VirtualDisplayConfiguration
    ) throws -> any VirtualDisplaySession
}

public enum DisplaySessionControllerError: Error, Equatable, Sendable {
    case noBaselineDisplays
}

@MainActor
public final class DisplaySessionController {
    public private(set) var stateMachine = DisplaySessionStateMachine()
    public private(set) var activeConfiguration: VirtualDisplayConfiguration?
    public private(set) var lastViolations: [PhysicalDisplayViolation] = []

    public var state: DisplaySessionState {
        stateMachine.state
    }

    public var activeDisplayID: CGDirectDisplayID? {
        displaySession?.displayID
    }

    private let snapshotProvider: any PhysicalDisplaySnapshotProviding
    private let displayFactory: any VirtualDisplayCreating
    private var displayGuard: PhysicalDisplayGuard?
    private var displaySession: (any VirtualDisplaySession)?

    public init(
        snapshotProvider: any PhysicalDisplaySnapshotProviding,
        displayFactory: any VirtualDisplayCreating
    ) {
        self.snapshotProvider = snapshotProvider
        self.displayFactory = displayFactory
    }

    public func start(configuration: VirtualDisplayConfiguration) throws {
        try stateMachine.handle(.requestStart)

        do {
            let baselines = try snapshotProvider.snapshots()
            guard !baselines.isEmpty else {
                throw DisplaySessionControllerError.noBaselineDisplays
            }

            displayGuard = PhysicalDisplayGuard(baselines: baselines)
            displaySession = try displayFactory.create(configuration: configuration)
            activeConfiguration = configuration
            lastViolations = []
            try stateMachine.handle(.didStart)
        } catch {
            try? displaySession?.stop()
            displaySession = nil
            displayGuard = nil
            activeConfiguration = nil
            try? stateMachine.handle(.startFailed)
            throw error
        }
    }

    public func stop() throws {
        try stateMachine.handle(.requestStop)

        do {
            try displaySession?.stop()
            displaySession = nil
            displayGuard = nil
            activeConfiguration = nil
            try stateMachine.handle(.didStop)
        } catch {
            try? stateMachine.handle(.stopFailed)
            throw error
        }
    }

    @discardableResult
    public func handleDisplayConfigurationChange() throws -> [PhysicalDisplayViolation] {
        guard state == .active, let displayGuard else {
            return []
        }

        do {
            let violations = displayGuard.violations(in: try snapshotProvider.snapshots())
            guard !violations.isEmpty else {
                return []
            }

            lastViolations = violations
            try stop()
            return violations
        } catch {
            try? stop()
            throw error
        }
    }

    public func stopIfNeeded() {
        guard state != .inactive else {
            return
        }
        try? stop()
    }
}
