@testable import SchreibtischunterlageCore

enum PreviewSurfacingDebouncerTests {
    static func run() throws {
        try debouncesEntryAndExit()
        try ignoresBoundaryJitter()
        try supportsImmediateTransitions()
    }

    private static func debouncesEntryAndExit() throws {
        var debouncer = PreviewSurfacingDebouncer(
            requiredConsecutiveSamples: 2
        )

        try expect(
            debouncer.observe(isWithinVirtualDisplay: true) == nil,
            "Expected first entry sample to be pending"
        )
        try expect(
            debouncer.observe(isWithinVirtualDisplay: true) == true,
            "Expected second entry sample to surface the preview"
        )
        try expect(
            debouncer.observe(isWithinVirtualDisplay: false) == nil,
            "Expected first exit sample to be pending"
        )
        try expect(
            debouncer.observe(isWithinVirtualDisplay: false) == false,
            "Expected second exit sample to restore normal level"
        )
    }

    private static func ignoresBoundaryJitter() throws {
        var debouncer = PreviewSurfacingDebouncer(
            requiredConsecutiveSamples: 2
        )

        try expect(
            debouncer.observe(isWithinVirtualDisplay: true) == nil,
            "Expected entry candidate"
        )
        try expect(
            debouncer.observe(isWithinVirtualDisplay: false) == nil,
            "Expected return to stable state to cancel entry"
        )
        try expect(
            debouncer.isWithinVirtualDisplay == false,
            "Expected preview to remain at normal level"
        )
    }

    private static func supportsImmediateTransitions() throws {
        var debouncer = PreviewSurfacingDebouncer(
            requiredConsecutiveSamples: 0
        )

        try expect(
            debouncer.observe(isWithinVirtualDisplay: true) == true,
            "Expected invalid threshold to clamp to one sample"
        )
        debouncer.reset()
        try expect(
            debouncer.isWithinVirtualDisplay == false,
            "Expected reset to restore the initial state"
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw PreviewSurfacingDebouncerTestFailure(description: message)
        }
    }
}

private struct PreviewSurfacingDebouncerTestFailure:
    Error,
    CustomStringConvertible
{
    let description: String
}
