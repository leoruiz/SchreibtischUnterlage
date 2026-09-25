@preconcurrency import AppKit
@preconcurrency import CoreGraphics
@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

public enum ScreenCaptureCoordinatorError: Error, LocalizedError, Sendable {
    case permissionDenied
    case displayNotFound(CGDirectDisplayID)
    case displayHasNoUsableMode(CGDirectDisplayID)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return """
            Screen Recording permission is required. Enable Schreibtischunterlage in \
            System Settings > Privacy & Security > Screen & System Audio Recording, \
            then start the virtual display again.
            """
        case let .displayNotFound(displayID):
            return "ScreenCaptureKit could not find virtual display \(displayID)."
        case let .displayHasNoUsableMode(displayID):
            return "Virtual display \(displayID) has no usable display mode."
        }
    }
}

public final class ScreenCaptureCoordinator:
    NSObject,
    SCStreamOutput,
    SCStreamDelegate,
    @unchecked Sendable
{
    private let outputQueue = DispatchQueue(
        label: "app.ruiz.Schreibtischunterlage.capture",
        qos: .userInteractive
    )
    private let relay: NewestFrameRelay
    private let failureHandler: @MainActor @Sendable (Error) -> Void
    private let latencyTracker: PreviewLatencyTracker?
    private let stateLock = NSLock()

    private var stream: SCStream?
    private var isStopping = false
    private var configuredPixelSize: CGSize?

    public convenience init(
        frameHandler: @escaping @MainActor @Sendable (CapturedFrame) -> Void,
        failureHandler: @escaping @MainActor @Sendable (Error) -> Void
    ) {
        self.init(
            frameHandler: frameHandler,
            failureHandler: failureHandler,
            latencyTracker: nil
        )
    }

    init(
        frameHandler: @escaping @MainActor @Sendable (CapturedFrame) -> Void,
        failureHandler: @escaping @MainActor @Sendable (Error) -> Void,
        latencyTracker: PreviewLatencyTracker?
    ) {
        relay = NewestFrameRelay(delivery: frameHandler)
        self.failureHandler = failureHandler
        self.latencyTracker = latencyTracker
        super.init()
    }

    public func start(displayID: CGDirectDisplayID) async throws {
        guard stream == nil else {
            return
        }

        guard requestScreenCaptureAccessIfNeeded() else {
            throw ScreenCaptureCoordinatorError.permissionDenied
        }

        let displayMode = try await waitForDisplayMode(displayID: displayID)
        let display = try await findDisplay(displayID: displayID)
        let configuration = makeConfiguration(displayMode: displayMode)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )

        try stream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: outputQueue
        )

        do {
            stateLock.withLock {
                isStopping = false
            }
            try await stream.startCapture()
            self.stream = stream
            configuredPixelSize = pixelSize(of: displayMode)
        } catch {
            try? stream.removeStreamOutput(self, type: .screen)
            throw error
        }
    }

    public func stop() async throws {
        guard let stream else {
            return
        }

        stateLock.withLock {
            isStopping = true
        }
        defer {
            self.stream = nil
            configuredPixelSize = nil
            stateLock.withLock {
                isStopping = false
            }
        }

        let stopResult: Result<Void, Error>
        do {
            try await stream.stopCapture()
            stopResult = .success(())
        } catch {
            stopResult = .failure(error)
        }
        try? stream.removeStreamOutput(self, type: .screen)
        try stopResult.get()
    }

    @discardableResult
    public func updateConfiguration(
        displayID: CGDirectDisplayID
    ) async throws -> Bool {
        guard let stream else {
            return false
        }

        let displayMode = try await waitForDisplayMode(displayID: displayID)
        let pixelSize = pixelSize(of: displayMode)
        guard pixelSize != configuredPixelSize else {
            return false
        }

        try await stream.updateConfiguration(
            makeConfiguration(displayMode: displayMode)
        )
        configuredPixelSize = pixelSize
        return true
    }

    public func invalidate() {
        stateLock.withLock {
            isStopping = true
        }
        stream = nil
        configuredPixelSize = nil
    }

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        let captureCallbackTime = HostTimeClock.now
        guard
            outputType == .screen,
            sampleBuffer.isValid,
            CMSampleBufferDataIsReady(sampleBuffer),
            let attachments = frameAttachments(sampleBuffer),
            isCompleteFrame(attachments),
            let pixelBuffer = sampleBuffer.imageBuffer
        else {
            return
        }

        let frame = CapturedFrame(
            pixelBuffer: pixelBuffer,
            sourceDisplayTime: sourceDisplayTime(attachments),
            captureCallbackTime: captureCallbackTime,
            latencyGeneration: latencyTracker?.measurementGeneration
        )
        latencyTracker?.recordCapturedFrame(frame)
        if let replacedFrame = relay.submit(frame) {
            latencyTracker?.recordCoalescedFrame(replacedFrame)
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        let isStopping = stateLock.withLock {
            isStopping
        }
        guard !isStopping else {
            return
        }

        Task { @MainActor [failureHandler] in
            failureHandler(error)
        }
    }

    private func requestScreenCaptureAccessIfNeeded() -> Bool {
        CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    private func makeConfiguration(
        displayMode: CGDisplayMode
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = displayMode.pixelWidth
        configuration.height = displayMode.pixelHeight
        let hostMaximumFramesPerSecond = max(
            NSScreen.main?.maximumFramesPerSecond ?? 60,
            1
        )
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: Int32(hostMaximumFramesPerSecond)
        )
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 2
        configuration.showsCursor = true
        configuration.capturesAudio = false
        return configuration
    }

    private func pixelSize(of displayMode: CGDisplayMode) -> CGSize {
        CGSize(
            width: displayMode.pixelWidth,
            height: displayMode.pixelHeight
        )
    }

    private func waitForDisplayMode(
        displayID: CGDirectDisplayID
    ) async throws -> CGDisplayMode {
        let timeout = ContinuousClock.now + .seconds(5)

        while ContinuousClock.now < timeout {
            try Task.checkCancellation()

            if let displayMode = CGDisplayCopyDisplayMode(displayID) {
                return displayMode
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw ScreenCaptureCoordinatorError.displayHasNoUsableMode(displayID)
    }

    private func findDisplay(
        displayID: CGDirectDisplayID
    ) async throws -> SCDisplay {
        let timeout = ContinuousClock.now + .seconds(10)

        while ContinuousClock.now < timeout {
            try Task.checkCancellation()

            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            if let display = content.displays.first(
                where: { $0.displayID == displayID }
            ) {
                return display
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        throw ScreenCaptureCoordinatorError.displayNotFound(displayID)
    }

    private func frameAttachments(
        _ sampleBuffer: CMSampleBuffer
    ) -> [SCStreamFrameInfo: Any]? {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]]
        else {
            return nil
        }

        return attachments.first
    }

    private func isCompleteFrame(
        _ attachments: [SCStreamFrameInfo: Any]
    ) -> Bool {
        guard
            let statusRawValue = attachments[.status] as? Int,
            let status = SCFrameStatus(rawValue: statusRawValue)
        else {
            return false
        }

        return status == .complete
    }

    private func sourceDisplayTime(
        _ attachments: [SCStreamFrameInfo: Any]
    ) -> CFTimeInterval? {
        guard let displayTime = attachments[.displayTime] as? UInt64 else {
            return nil
        }
        return HostTimeClock.seconds(fromMachAbsoluteTime: displayTime)
    }
}
