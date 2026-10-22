import Foundation

public enum ScreenshotCommand: Equatable, Sendable {
    case help
    case capture(path: String)

    public static let usage = """
    Usage: SchreibtischUnterlage --screenshot <output.png>
           SchreibtischUnterlage --help

    Save the running SU virtual display as a native-resolution PNG.
    Prints JSON with path, displayID, width, and height on success.
    The destination must not already exist; its parent directory must exist.
    Requires existing Screen Recording permission. Does not prompt for access,
    start a display, move the pointer, or activate any windows.
    """

    public static func parse(_ arguments: [String]) throws -> Self? {
        guard arguments.contains(where: {
            $0.hasPrefix("--screenshot") || $0 == "--help"
        }) else {
            return nil
        }

        if arguments == ["--help"] {
            return .help
        }

        let path: String
        if arguments.count == 2, arguments[0] == "--screenshot" {
            path = arguments[1]
        } else if arguments.count == 1, arguments[0].hasPrefix("--screenshot=") {
            path = String(arguments[0].dropFirst("--screenshot=".count))
        } else {
            throw ScreenshotCommandError.invalidArguments
        }

        guard !path.isEmpty, !path.hasPrefix("-"), !path.utf8.contains(0) else {
            throw ScreenshotCommandError.invalidArguments
        }
        guard
            !path.hasSuffix("/"),
            URL(fileURLWithPath: path).pathExtension.lowercased() == "png"
        else {
            throw ScreenshotCommandError.requiresPNG
        }
        return .capture(path: path)
    }
}

public enum ScreenshotCommandError: Error, LocalizedError {
    case invalidArguments
    case requiresPNG

    public var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Use --screenshot <output.png> without other options, or --help."
        case .requiresPNG:
            return "The screenshot destination must have a .png extension."
        }
    }
}
