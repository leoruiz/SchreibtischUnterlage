import AppKit
import Darwin

@main
enum ApplicationMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared

        if let probeCycleCount = displayProbeCycleCount() {
            let probe = DisplayProbe(cycleCount: probeCycleCount)
            application.setActivationPolicy(.prohibited)
            application.delegate = probe
            application.run()
            withExtendedLifetime(probe) {}
            exit(probe.exitCode)
        }

        if let cursorProbeDuration = cursorProbeDuration() {
            let probe = PreviewProbe(
                visibleDuration: cursorProbeDuration,
                testsCursorPortal: true
            )
            application.setActivationPolicy(.accessory)
            application.delegate = probe
            application.run()
            withExtendedLifetime(probe) {}
            exit(probe.exitCode)
        }

        if let previewProbeDuration = previewProbeDuration() {
            let probe = PreviewProbe(visibleDuration: previewProbeDuration)
            application.setActivationPolicy(.accessory)
            application.delegate = probe
            application.run()
            withExtendedLifetime(probe) {}
            exit(probe.exitCode)
        }

        let delegate = AppDelegate()

        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()

        withExtendedLifetime(delegate) {}
    }

    private static func displayProbeCycleCount() -> Int? {
        for argument in CommandLine.arguments.dropFirst() {
            if argument == "--display-probe" {
                return 1
            }

            let prefix = "--display-probe-cycles="
            guard argument.hasPrefix(prefix) else {
                continue
            }

            let rawValue = argument.dropFirst(prefix.count)
            guard
                let cycleCount = Int(rawValue),
                (1...100).contains(cycleCount)
            else {
                fputs("display probe cycle count must be between 1 and 100\n", stderr)
                exit(EXIT_FAILURE)
            }
            return cycleCount
        }

        return nil
    }

    private static func previewProbeDuration() -> Duration? {
        probeDuration(
            prefix: "--preview-probe-seconds=",
            errorLabel: "preview probe"
        )
    }

    private static func cursorProbeDuration() -> Duration? {
        probeDuration(
            prefix: "--cursor-probe-seconds=",
            errorLabel: "cursor probe"
        )
    }

    private static func probeDuration(
        prefix: String,
        errorLabel: String
    ) -> Duration? {
        guard let argument = CommandLine.arguments.dropFirst().first(
            where: { $0.hasPrefix(prefix) }
        ) else {
            return nil
        }

        let rawValue = argument.dropFirst(prefix.count)
        guard
            let seconds = Int(rawValue),
            (3...60).contains(seconds)
        else {
            fputs("\(errorLabel) duration must be between 3 and 60 seconds\n", stderr)
            exit(EXIT_FAILURE)
        }

        return .seconds(seconds)
    }
}
