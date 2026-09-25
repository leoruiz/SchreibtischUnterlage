@testable import SchreibtischunterlageCore

enum CursorPortalActivationModeTests {
    static func run() throws {
        try singleClickActivatesImmediately()
        try doubleClickWaitsForSecondClick()
    }

    private static func singleClickActivatesImmediately() throws {
        try expect(
            CursorPortalActivationMode.singleClick.shouldActivate(
                clickCount: 1
            ),
            "Expected single click to activate the cursor portal"
        )
        try expect(
            !CursorPortalActivationMode.singleClick.shouldActivate(
                clickCount: 2
            ),
            "Expected later double-click events to be ignored"
        )
    }

    private static func doubleClickWaitsForSecondClick() throws {
        try expect(
            !CursorPortalActivationMode.doubleClick.shouldActivate(
                clickCount: 1
            ),
            "Expected first click to leave the cursor in the preview"
        )
        try expect(
            CursorPortalActivationMode.doubleClick.shouldActivate(
                clickCount: 2
            ),
            "Expected second click to activate the cursor portal"
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw CursorPortalActivationModeTestFailure(
                description: message
            )
        }
    }
}

private struct CursorPortalActivationModeTestFailure:
    Error,
    CustomStringConvertible
{
    let description: String
}
