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
    private let stateLock = NSLock()

    private var stream: SCStream?
    private var isStopping = false

    public init(
        frameHandler: @escaping @MainActor @Sendable (CapturedFrame) -> Void,
        failureHandler: @escaping @MainActor @Sendable (Error) -> Void
    ) {
        relay = NewestFrameRelay(delivery: frameHandler)
        self.failureHandler = failureHandler
    }

    public func start(displayID: CGDirectDisplayID) async throws {
        guard stream == nil else {
            return
        }

        guard requestScreenCaptureAccessIfNeeded() else {
            throw ScreenCaptureCoordinatorError.permissionDenied
        }

        guard let displayMode = CGDisplayCopyDisplayMode(displayID) else {
            throw ScreenCaptureCoordinatorError.displayHasNoUsableMode(displayID)
        }

        let display = try await findDisplay(displayID: displayID)
        let configuration = SCStreamConfiguration()
        configuration.width = displayMode.pixelWidth
        configuration.height = displayMode.pixelHeight
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        configuration.showsCursor = true
        configuration.capturesAudio = false

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

    public func invalidate() {
        stateLock.withLock {
            isStopping = true
        }
        stream = nil
    }

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard
            outputType == .screen,
            sampleBuffer.isValid,
            CMSampleBufferDataIsReady(sampleBuffer),
            isCompleteFrame(sampleBuffer),
            let pixelBuffer = sampleBuffer.imageBuffer
        else {
            return
        }

        relay.submit(CapturedFrame(pixelBuffer: pixelBuffer))
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

    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let statusRawValue = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: statusRawValue)
        else {
            return false
        }

        return status == .complete
    }
}
