@preconcurrency import CoreGraphics
import Foundation
import SchreibtischUnterlageCore

public enum VirtualDisplayModeControllerError:
    Error,
    LocalizedError,
    Sendable
{
    case displayModesUnavailable(displayID: CGDirectDisplayID)
    case modeUnavailable(
        displayID: CGDirectDisplayID,
        width: Int,
        height: Int
    )
    case modeChangeFailed(
        displayID: CGDirectDisplayID,
        error: CGError
    )
    case modeDidNotChange(
        displayID: CGDirectDisplayID,
        width: Int,
        height: Int
    )

    public var errorDescription: String? {
        switch self {
        case let .displayModesUnavailable(displayID):
            return """
            Virtual display \(displayID) did not publish any usable modes.
            """
        case let .modeUnavailable(displayID, width, height):
            return """
            Virtual display \(displayID) did not publish its \(width) × \(height) mode.
            """
        case let .modeChangeFailed(displayID, error):
            return """
            Core Graphics could not change virtual display \(displayID)'s mode \
            (error \(error.rawValue)).
            """
        case let .modeDidNotChange(displayID, width, height):
            return """
            Virtual display \(displayID) did not switch to \(width) × \(height).
            """
        }
    }
}

@MainActor
public enum VirtualDisplayModeController {
    @discardableResult
    public static func apply(
        _ preferredMode: VirtualDisplayMode,
        to displayID: CGDirectDisplayID
    ) async throws -> VirtualDisplayMode {
        let publishedModes = try await waitForPublishedModes(
            displayID: displayID
        )
        let selectedMode = try selectMode(
            preferredMode: preferredMode,
            publishedModes: publishedModes,
            displayID: displayID
        )
        if currentModeMatches(selectedMode, displayID: displayID) {
            return selectedMode
        }

        let displayMode = closestPublishedMode(
            matching: selectedMode,
            publishedModes: publishedModes
        )
        let result = CGDisplaySetDisplayMode(
            displayID,
            displayMode,
            nil
        )
        guard result == .success else {
            throw VirtualDisplayModeControllerError.modeChangeFailed(
                displayID: displayID,
                error: result
            )
        }

        let timeout = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < timeout {
            try Task.checkCancellation()
            if currentModeMatches(
                selectedMode,
                displayID: displayID
            ) {
                return selectedMode
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        throw VirtualDisplayModeControllerError.modeDidNotChange(
            displayID: displayID,
            width: selectedMode.width,
            height: selectedMode.height
        )
    }

    private static func waitForPublishedModes(
        displayID: CGDirectDisplayID
    ) async throws -> [CGDisplayMode] {
        let timeout = ContinuousClock.now + .seconds(5)

        while ContinuousClock.now < timeout {
            try Task.checkCancellation()

            if
                CGDisplayCopyDisplayMode(displayID) != nil,
                let modes = CGDisplayCopyAllDisplayModes(
                    displayID,
                    nil
                ) as? [CGDisplayMode],
                !modes.isEmpty
            {
                return modes
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw VirtualDisplayModeControllerError.displayModesUnavailable(
            displayID: displayID
        )
    }

    private static func selectMode(
        preferredMode: VirtualDisplayMode,
        publishedModes: [CGDisplayMode],
        displayID: CGDirectDisplayID
    ) throws -> VirtualDisplayMode {
        let availableModes = publishedModes.compactMap { mode in
            VirtualDisplayMode(
                width: mode.pixelWidth,
                height: mode.pixelHeight,
                refreshRate: normalizedRefreshRate(mode.refreshRate)
            )
        }

        if let exactMode = availableModes.first(where: {
            $0.width == preferredMode.width
                && $0.height == preferredMode.height
        }) {
            return exactMode
        }

        guard let fallbackMode = VirtualDisplayModeCatalog.bestMode(
            among: availableModes,
            forPixelWidth: preferredMode.width,
            pixelHeight: preferredMode.height
        ) else {
            throw VirtualDisplayModeControllerError.modeUnavailable(
                displayID: displayID,
                width: preferredMode.width,
                height: preferredMode.height
            )
        }
        return fallbackMode
    }

    private static func closestPublishedMode(
        matching selectedMode: VirtualDisplayMode,
        publishedModes: [CGDisplayMode]
    ) -> CGDisplayMode? {
        publishedModes
            .filter {
                $0.pixelWidth == selectedMode.width
                    && $0.pixelHeight == selectedMode.height
            }
            .min {
                abs(normalizedRefreshRate($0.refreshRate) - selectedMode.refreshRate)
                    < abs(
                        normalizedRefreshRate($1.refreshRate)
                            - selectedMode.refreshRate
                    )
            }
    }

    private static func normalizedRefreshRate(
        _ refreshRate: Double
    ) -> Double {
        refreshRate > 0 ? refreshRate : 60
    }

    private static func currentModeMatches(
        _ preferredMode: VirtualDisplayMode,
        displayID: CGDirectDisplayID
    ) -> Bool {
        guard let currentMode = CGDisplayCopyDisplayMode(displayID) else {
            return false
        }
        return currentMode.pixelWidth == preferredMode.width
            && currentMode.pixelHeight == preferredMode.height
    }
}
