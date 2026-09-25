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
}
