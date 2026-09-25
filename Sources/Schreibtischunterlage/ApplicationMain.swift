import AppKit
import Darwin

@main
enum ApplicationMain {
    @MainActor
    static func main() async {
        let application = NSApplication.shared

        if CommandLine.arguments.contains("--display-probe") {
            application.setActivationPolicy(.prohibited)
            do {
                try await DisplayProbe.run()
            } catch {
                fputs("display probe failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }

        let delegate = AppDelegate()

        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()

        withExtendedLifetime(delegate) {}
    }
}
