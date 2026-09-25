import AppKit
import Darwin

@main
enum ApplicationMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared

        if CommandLine.arguments.contains("--display-probe") {
            let probe = DisplayProbe()
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
}
