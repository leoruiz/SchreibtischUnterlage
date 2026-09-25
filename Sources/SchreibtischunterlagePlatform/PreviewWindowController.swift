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

    public var latencySnapshot: PreviewLatencySnapshot? {
        latencyTracker?.snapshot()
    }

    public func resetLatencyMeasurements() {
        latencyTracker?.reset()
    }

    private let previewView: MetalPreviewView
    private let latencyTracker: PreviewLatencyTracker?
    private var captureCoordinator: ScreenCaptureCoordinator?
    private var cursorPortal: CursorPortal?
    private var displayID: CGDirectDisplayID?
    private var reconfigurationTask: Task<Void, Never>?
    private var displayConfigurationRevision = 0
    private var isClosingProgrammatically = false
    private var lastFrameSize: CGSize?
    private var hasAppliedInitialWindowSize = false

    public static func make(
        measuresLatency: Bool = false
    ) throws -> PreviewWindowController {
        let latencyTracker = measuresLatency ? PreviewLatencyTracker() : nil
        return try PreviewWindowController(
            previewView: MetalPreviewView.make(
                latencyTracker: latencyTracker
            ),
            latencyTracker: latencyTracker
        )
    }

    private init(
        previewView: MetalPreviewView,
        latencyTracker: PreviewLatencyTracker?
    ) {
        self.previewView = previewView
        self.latencyTracker = latencyTracker

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
        self.displayID = displayID
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
            },
            latencyTracker: latencyTracker
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

        reconfigurationTask?.cancel()
        reconfigurationTask = nil
        displayID = nil
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
        reconfigurationTask?.cancel()
        reconfigurationTask = nil
        displayID = nil
        captureCoordinator?.invalidate()
        captureCoordinator = nil
        cursorPortal = nil
        previewView.cursorPortalHandler = nil
        window?.orderOut(nil)
        isClosingProgrammatically = false
    }

    public func handleDisplayConfigurationChange() {
        guard
            displayID != nil,
            captureCoordinator != nil
        else {
            return
        }

        displayConfigurationRevision &+= 1
        guard reconfigurationTask == nil else {
            return
        }

        reconfigurationTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let revision = self.displayConfigurationRevision

                do {
                    try await Task.sleep(for: .milliseconds(100))
                    try Task.checkCancellation()

                    guard revision == self.displayConfigurationRevision else {
                        continue
                    }
                    guard
                        let displayID = self.displayID,
                        let captureCoordinator = self.captureCoordinator
                    else {
                        break
                    }

                    try await captureCoordinator.updateConfiguration(
                        displayID: displayID
                    )
                    guard revision != self.displayConfigurationRevision else {
                        break
                    }
                } catch is CancellationError {
                    break
                } catch {
                    self.failureHandler?(error)
                    break
                }
            }

            self?.reconfigurationTask = nil
        }
    }

    public func windowWillClose(_ notification: Notification) {
        guard !isClosingProgrammatically else {
            return
        }
        closeHandler?()
    }

    private func display(_ frame: CapturedFrame) {
        latencyTracker?.recordDeliveredFrame(
            frame,
            at: HostTimeClock.now
        )
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

        let previousFrameSize = lastFrameSize
        lastFrameSize = frameSize
        window?.contentAspectRatio = CGSize(
            width: frameSize.width / frameSize.height,
            height: 1
        )

        if !hasAppliedInitialWindowSize {
            hasAppliedInitialWindowSize = true
            applyInitialWindowSize(sourceSize: frameSize)
            return
        }

        if let previousFrameSize, previousFrameSize != frameSize {
            applyResolutionChangeWindowSize(sourceSize: frameSize)
        }
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

    private func applyResolutionChangeWindowSize(sourceSize: CGSize) {
        guard
            let window,
            let screen = window.screen ?? NSScreen.main,
            let currentContentSize = window.contentView?.bounds.size,
            let contentSize = PreviewWindowSizing.contentSizePreservingWidth(
                sourceSize: sourceSize,
                currentContentSize: currentContentSize,
                availableSize: CGSize(
                    width: screen.visibleFrame.width,
                    height: max(screen.visibleFrame.height - 40, 1)
                )
            )
        else {
            return
        }

        let previousCenter = CGPoint(
            x: window.frame.midX,
            y: window.frame.midY
        )
        window.setContentSize(contentSize)

        let visibleFrame = screen.visibleFrame
        let proposedOrigin = CGPoint(
            x: previousCenter.x - window.frame.width / 2,
            y: previousCenter.y - window.frame.height / 2
        )
        window.setFrameOrigin(
            CGPoint(
                x: min(
                    max(proposedOrigin.x, visibleFrame.minX),
                    visibleFrame.maxX - window.frame.width
                ),
                y: min(
                    max(proposedOrigin.y, visibleFrame.minY),
                    visibleFrame.maxY - window.frame.height
                )
            )
        )
    }
}
