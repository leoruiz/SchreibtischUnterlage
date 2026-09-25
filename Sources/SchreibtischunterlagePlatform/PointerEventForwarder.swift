@preconcurrency import AppKit
@preconcurrency import CoreGraphics
import SchreibtischunterlageCore

public enum PreviewPointerButton: Equatable, Sendable {
    case left
    case right
    case center

    fileprivate var coreGraphicsButton: CGMouseButton {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        case .center:
            return .center
        }
    }

    fileprivate var mouseDownType: CGEventType {
        switch self {
        case .left:
            return .leftMouseDown
        case .right:
            return .rightMouseDown
        case .center:
            return .otherMouseDown
        }
    }

    fileprivate var mouseUpType: CGEventType {
        switch self {
        case .left:
            return .leftMouseUp
        case .right:
            return .rightMouseUp
        case .center:
            return .otherMouseUp
        }
    }
}

public struct PreviewPointerClick: Sendable {
    public let locationInView: CGPoint
    public let button: PreviewPointerButton
    public let clickCount: Int
    public let modifierFlags: NSEvent.ModifierFlags

    public init(
        locationInView: CGPoint,
        button: PreviewPointerButton,
        clickCount: Int,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        self.locationInView = locationInView
        self.button = button
        self.clickCount = clickCount
        self.modifierFlags = modifierFlags
    }
}

public enum PointerEventForwarderError: Error, LocalizedError, Sendable {
    case permissionDenied
    case cursorMoveFailed(CGError)
    case eventCreationFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return """
            Accessibility permission is required to forward clicks. Enable \
            Schreibtischunterlage in System Settings > Privacy & Security > \
            Accessibility, then click the preview again.
            """
        case let .cursorMoveFailed(error):
            return "The cursor could not move to the virtual display: \(error.rawValue)."
        case .eventCreationFailed:
            return "macOS could not create the forwarded mouse event."
        }
    }
}

@MainActor
public final class PointerEventForwarder {
    private let displayID: CGDirectDisplayID

    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    @discardableResult
    public func forward(
        _ click: PreviewPointerClick,
        previewSize: CGSize,
        sourceSize: CGSize
    ) async throws -> Bool {
        let displayBounds = CGDisplayBounds(displayID)
        guard let displayPoint = PreviewCoordinateMapper.displayLocalPoint(
            previewPoint: click.locationInView,
            previewSize: previewSize,
            sourceSize: sourceSize,
            displaySize: displayBounds.size
        ) else {
            return false
        }

        guard requestPostEventAccessIfNeeded() else {
            throw PointerEventForwarderError.permissionDenied
        }

        let cursorMoveResult = CGDisplayMoveCursorToPoint(
            displayID,
            displayPoint
        )
        guard cursorMoveResult == .success else {
            throw PointerEventForwarderError.cursorMoveFailed(cursorMoveResult)
        }

        try await Task.sleep(for: .milliseconds(20))

        let globalPoint = CGPoint(
            x: displayBounds.minX + displayPoint.x,
            y: displayBounds.minY + displayPoint.y
        )
        try postClick(click, at: globalPoint)
        return true
    }

    private func requestPostEventAccessIfNeeded() -> Bool {
        CGPreflightPostEventAccess() || CGRequestPostEventAccess()
    }

    private func postClick(
        _ click: PreviewPointerClick,
        at globalPoint: CGPoint
    ) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: click.button.mouseDownType,
                mouseCursorPosition: globalPoint,
                mouseButton: click.button.coreGraphicsButton
            ),
            let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: click.button.mouseUpType,
                mouseCursorPosition: globalPoint,
                mouseButton: click.button.coreGraphicsButton
            )
        else {
            throw PointerEventForwarderError.eventCreationFailed
        }

        let eventFlags = coreGraphicsFlags(from: click.modifierFlags)
        let clickCount = Int64(max(click.clickCount, 1))
        mouseDown.flags = eventFlags
        mouseUp.flags = eventFlags
        mouseDown.setIntegerValueField(.mouseEventClickState, value: clickCount)
        mouseUp.setIntegerValueField(.mouseEventClickState, value: clickCount)
        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
    }

    private func coreGraphicsFlags(
        from flags: NSEvent.ModifierFlags
    ) -> CGEventFlags {
        var result: CGEventFlags = []

        if flags.contains(.capsLock) {
            result.insert(.maskAlphaShift)
        }
        if flags.contains(.shift) {
            result.insert(.maskShift)
        }
        if flags.contains(.control) {
            result.insert(.maskControl)
        }
        if flags.contains(.option) {
            result.insert(.maskAlternate)
        }
        if flags.contains(.command) {
            result.insert(.maskCommand)
        }
        if flags.contains(.function) {
            result.insert(.maskSecondaryFn)
        }

        return result
    }
}
