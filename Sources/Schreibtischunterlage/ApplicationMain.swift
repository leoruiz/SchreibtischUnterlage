import AppKit

@main
enum ApplicationMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()

        withExtendedLifetime(delegate) {}
    }
}

