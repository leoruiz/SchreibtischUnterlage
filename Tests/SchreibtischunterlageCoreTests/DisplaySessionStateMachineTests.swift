@testable import SchreibtischunterlageCore

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum DisplaySessionStateMachineTests {
    static func main() throws {
        try successfulStartAndStop()
        try startFailureCanBeCleanedUp()
        try stopFailureRemainsVisible()
        try invalidTransitionDoesNotChangeState()
        try PhysicalDisplayGuardTests.run()

        print("SchreibtischunterlageCoreTests: PASS")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw TestFailure(description: message)
        }
    }

    private static func successfulStartAndStop() throws {
        var stateMachine = DisplaySessionStateMachine()

        try stateMachine.handle(.requestStart)
        try expect(stateMachine.state == .starting, "Expected starting state")

        try stateMachine.handle(.didStart)
        try expect(stateMachine.state == .active, "Expected active state")

        try stateMachine.handle(.requestStop)
        try expect(stateMachine.state == .stopping, "Expected stopping state")

        try stateMachine.handle(.didStop)
        try expect(stateMachine.state == .inactive, "Expected inactive state")
    }

    private static func startFailureCanBeCleanedUp() throws {
        var stateMachine = DisplaySessionStateMachine()

        try stateMachine.handle(.requestStart)
        try stateMachine.handle(.startFailed)
        try expect(
            stateMachine.state == .failed(.startFailed),
            "Expected visible start failure"
        )

        try stateMachine.handle(.requestStop)
        try stateMachine.handle(.didStop)
        try expect(stateMachine.state == .inactive, "Expected cleanup to reach inactive state")
    }

    private static func stopFailureRemainsVisible() throws {
        var stateMachine = DisplaySessionStateMachine(state: .active)

        try stateMachine.handle(.requestStop)
        try stateMachine.handle(.stopFailed)

        try expect(
            stateMachine.state == .failed(.stopFailed),
            "Expected visible stop failure"
        )
    }

    private static func invalidTransitionDoesNotChangeState() throws {
        var stateMachine = DisplaySessionStateMachine()

        do {
            try stateMachine.handle(.didStart)
            throw TestFailure(description: "Expected an invalid transition error")
        } catch let error as InvalidDisplaySessionTransition {
            try expect(
                error == InvalidDisplaySessionTransition(state: .inactive, event: .didStart),
                "Unexpected invalid transition details"
            )
        } catch {
            throw TestFailure(description: "Unexpected error: \(error)")
        }

        try expect(
            stateMachine.state == .inactive,
            "Invalid transition changed the state"
        )
    }
}
