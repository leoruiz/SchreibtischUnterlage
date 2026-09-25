@preconcurrency import AppKit
import CoreGraphics

@MainActor
public final class PreviewWindowController:
    NSWindowController,
    NSWindowDelegate
{
    public var closeHandler: (@MainActor @Sendable () -> Void)?
    public var failureHandler: (@MainActor @Sendable (Error) -> Void)?
    public private(set) var renderedFrameCount = 0

    private let previewView: MetalPreviewView
    private var captureCoordinator: ScreenCaptureCoordinator?
    private var isClosingProgrammatically = false
    private var lastFrameSize: CGSize?

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
        if let captureCoordinator {
            try await captureCoordinator.stop()
        }
    }

    public func invalidate() {
        isClosingProgrammatically = true
        captureCoordinator?.invalidate()
        captureCoordinator = nil
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

    private func updateWindowAspectRatioIfNeeded(_ frameSize: CGSize) {
        guard frameSize != lastFrameSize else {
            return
        }

        lastFrameSize = frameSize
        window?.contentAspectRatio = CGSize(
            width: frameSize.width / frameSize.height,
            height: 1
        )
    }
}
