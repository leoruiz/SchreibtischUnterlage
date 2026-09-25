@preconcurrency import CoreGraphics
import Foundation
import SchreibtischUnterlageCore

public enum CursorPortalError: Error, LocalizedError, Sendable {
    case cursorMoveFailed(CGError)

    public var errorDescription: String? {
        switch self {
        case let .cursorMoveFailed(error):
            return "The cursor could not move to the virtual display: \(error.rawValue)."
        }
    }
}

@MainActor
public final class CursorPortal {
    private let displayID: CGDirectDisplayID

    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    @discardableResult
    public func moveCursor(
        from previewPoint: CGPoint,
        previewSize: CGSize,
        sourceSize: CGSize
    ) throws -> Bool {
        let displayBounds = CGDisplayBounds(displayID)
        guard let displayPoint = PreviewCoordinateMapper.displayLocalPoint(
            previewPoint: previewPoint,
            previewSize: previewSize,
            sourceSize: sourceSize,
            displaySize: displayBounds.size
        ) else {
            return false
        }

        let result = CGDisplayMoveCursorToPoint(displayID, displayPoint)
        guard result == .success else {
            throw CursorPortalError.cursorMoveFailed(result)
        }

        return true
    }
}
