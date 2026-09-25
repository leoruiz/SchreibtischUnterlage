@preconcurrency import AppKit
import CoreGraphics
import SchreibtischunterlageCore

@MainActor
public final class PreviewWindowController:
    NSWindowController,
    NSWindowDelegate
{
    public var closeHandler: (@MainActor @Sendable () -> Void)?
    public var failureHandler: (@MainActor @Sendable (Error) -> Void)?
    public var interactionFailureHandler: (@MainActor @Sendable (Error) -> Void)?
    public private(set) var renderedFrameCount = 0
    public var previewContentSize: CGSize {
        previewView.bounds.size
    }

    public var currentSourceSize: CGSize? {
        lastFrameSize
    }

    private let previewView: MetalPreviewView
    private var captureCoordinator: ScreenCaptureCoordinator?
    private var cursorPortal: CursorPortal?
    private var isClosingProgrammatically = false
    private var lastFrameSize: CGSize?
    private var hasAppliedInitialWindowSize = false

    public static func make() throws -> PreviewWindowController {
        PreviewWindowController(previewView: try MetalPreviewView.make())
    }

    private init(previewView: MetalPreviewView) {
        self.previewView = previewView

        let contentViewController = NSViewController()
        contentViewController.view = previewView

        let window = NSWindow(contentViewController: contentViewController)
        window.title = "Schreibtischunterlage"
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
        ]
        window.setContentSize(CGSize(width: 960, height: 600))
        window.minSize = CGSize(width: 480, height: 300)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public func start(displayID: CGDirectDisplayID) async throws {
        let cursorPortal = CursorPortal(displayID: displayID)
        self.cursorPortal = cursorPortal
        previewView.cursorPortalHandler = { [weak self] location in
            self?.moveCursor(to: location)
        }

        let coordinator = ScreenCaptureCoordinator(
            frameHandler: { [weak self] frame in
                self?.display(frame)
            },
            failureHandler: { [weak self] error in
                self?.failureHandler?(error)
            }
        )
        captureCoordinator = coordinator

        do {
            try await coordinator.start(displayID: displayID)
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
        } catch {
            captureCoordinator = nil
            throw error
        }
    }

    public func stop() async throws {
        isClosingProgrammatically = true
        defer {
            window?.orderOut(nil)
            isClosingProgrammatically = false
        }

        let captureCoordinator = captureCoordinator
        self.captureCoordinator = nil
        cursorPortal = nil
        previewView.cursorPortalHandler = nil
        if let captureCoordinator {
            try await captureCoordinator.stop()
        }
    }

    public func invalidate() {
        isClosingProgrammatically = true
        captureCoordinator?.invalidate()
        captureCoordinator = nil
        cursorPortal = nil
        previewView.cursorPortalHandler = nil
        window?.orderOut(nil)
        isClosingProgrammatically = false
    }

    public func windowWillClose(_ notification: Notification) {
        guard !isClosingProgrammatically else {
            return
        }
        closeHandler?()
    }

    private func display(_ frame: CapturedFrame) {
        updateWindowAspectRatioIfNeeded(
            CGSize(width: frame.width, height: frame.height)
        )
        if previewView.display(frame) {
            renderedFrameCount += 1
        }
    }

    private func moveCursor(to previewPoint: CGPoint) {
        guard
            let cursorPortal,
            let sourceSize = lastFrameSize
        else {
            return
        }

        do {
            try cursorPortal.moveCursor(
                from: previewPoint,
                previewSize: previewView.bounds.size,
                sourceSize: sourceSize
            )
        } catch {
            interactionFailureHandler?(error)
        }
    }

    private func updateWindowAspectRatioIfNeeded(_ frameSize: CGSize) {
        guard frameSize != lastFrameSize else {
            return
        }

        lastFrameSize = frameSize
        window?.contentAspectRatio = CGSize(
            width: frameSize.width / frameSize.height,
            height: 1
        )

        guard !hasAppliedInitialWindowSize else {
            return
        }
        hasAppliedInitialWindowSize = true
        applyInitialWindowSize(sourceSize: frameSize)
    }

    private func applyInitialWindowSize(sourceSize: CGSize) {
        guard
            let window,
            let screen = window.screen ?? NSScreen.main,
            let contentSize = PreviewWindowSizing.initialContentSize(
                sourceSize: sourceSize,
                availableSize: screen.visibleFrame.size
            )
        else {
            return
        }

        window.setContentSize(contentSize)
        let frame = window.frame
        let visibleFrame = screen.visibleFrame
        window.setFrameOrigin(
            CGPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: visibleFrame.midY - frame.height / 2
            )
        )
    }
}
