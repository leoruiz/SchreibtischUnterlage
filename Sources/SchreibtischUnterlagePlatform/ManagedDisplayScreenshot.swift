import CoreGraphics
import Foundation
import ImageIO
import SchreibtischUnterlageCore
import ScreenCaptureKit
import UniformTypeIdentifiers

public enum ManagedDisplayScreenshotError: Error, LocalizedError {
    case permissionDenied
    case displayNotRunning
    case multipleManagedDisplays
    case destinationExists
    case pngEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return """
            Screen Recording permission is required. Grant access to \
            SchreibtischUnterlage through the app before using --screenshot.
            """
        case .displayNotRunning:
            return "No SU virtual display is running. Start it in the app first."
        case .multipleManagedDisplays:
            return "More than one SU virtual display is online; refusing ambiguous capture."
        case .destinationExists:
            return "The screenshot destination already exists; choose a new path."
        case .pngEncodingFailed:
            return "The captured image could not be encoded as PNG."
        }
    }
}

public struct ScreenshotResult: Encodable, Sendable {
    public let path: String
    public let displayID: CGDirectDisplayID
    public let width: Int
    public let height: Int
}

struct ScreenshotDisplay {
    let displayID: CGDirectDisplayID
    let identity: PhysicalDisplayIdentity
}

public enum ManagedDisplayScreenshot {
    @MainActor
    public static func capture(to destination: URL) async throws -> ScreenshotResult {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ManagedDisplayScreenshotError.destinationExists
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw ManagedDisplayScreenshotError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        let displayID = try selectDisplay(from: content.displays.map { display in
            ScreenshotDisplay(
                displayID: display.displayID,
                identity: PhysicalDisplayIdentity(
                    vendorID: CGDisplayVendorNumber(display.displayID),
                    modelID: CGDisplayModelNumber(display.displayID),
                    serialNumber: CGDisplaySerialNumber(display.displayID),
                    unitNumber: CGDisplayUnitNumber(display.displayID)
                )
            )
        })
        guard
            let display = content.displays.first(where: { $0.displayID == displayID }),
            let mode = CGDisplayCopyDisplayMode(displayID)
        else {
            throw ScreenCaptureCoordinatorError.displayNotFound(displayID)
        }

        let configuration = SCStreamConfiguration()
        configuration.width = mode.pixelWidth
        configuration.height = mode.pixelHeight
        configuration.showsCursor = true
        configuration.capturesAudio = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: []),
            configuration: configuration
        )
        try writePNG(image, to: destination)
        return ScreenshotResult(
            path: destination.path,
            displayID: displayID,
            width: image.width,
            height: image.height
        )
    }

    static func selectDisplay(from displays: [ScreenshotDisplay]) throws -> CGDirectDisplayID {
        let identity = CGVirtualDisplayFactory().hardwareIdentity
        let matches = displays.filter { identity.matches($0.identity) }
        guard let display = matches.first else {
            throw ManagedDisplayScreenshotError.displayNotRunning
        }
        guard matches.count == 1 else {
            throw ManagedDisplayScreenshotError.multipleManagedDisplays
        }
        return display.displayID
    }

    static func writePNG(_ image: CGImage, to destination: URL) throws {
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ManagedDisplayScreenshotError.pngEncodingFailed
        }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else {
            throw ManagedDisplayScreenshotError.pngEncodingFailed
        }
        try (data as Data).write(to: destination, options: .withoutOverwriting)
    }
}
