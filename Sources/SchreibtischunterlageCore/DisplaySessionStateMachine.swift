public enum DisplaySessionState: Equatable, Sendable {
    case inactive
    case starting
    case active
    case stopping
    case failed(DisplaySessionFailure)
}

public enum DisplaySessionFailure: Error, Equatable, Sendable {
    case startFailed
    case stopFailed
}

public enum DisplaySessionEvent: Equatable, Sendable {
    case requestStart
    case didStart
    case startFailed
    case requestStop
    case didStop
    case stopFailed
}

public struct InvalidDisplaySessionTransition: Error, Equatable, Sendable {
    public let state: DisplaySessionState
    public let event: DisplaySessionEvent

    public init(state: DisplaySessionState, event: DisplaySessionEvent) {
        self.state = state
        self.event = event
    }
}

public struct DisplaySessionStateMachine: Sendable {
    public private(set) var state: DisplaySessionState

    public init(state: DisplaySessionState = .inactive) {
        self.state = state
    }

    public mutating func handle(_ event: DisplaySessionEvent) throws {
        switch (state, event) {
        case (.inactive, .requestStart):
            state = .starting
        case (.starting, .didStart):
            state = .active
        case (.starting, .startFailed):
            state = .failed(.startFailed)
        case (.active, .requestStop), (.failed, .requestStop):
            state = .stopping
        case (.stopping, .didStop):
            state = .inactive
        case (.stopping, .stopFailed):
            state = .failed(.stopFailed)
        default:
            throw InvalidDisplaySessionTransition(state: state, event: event)
        }
    }
}

