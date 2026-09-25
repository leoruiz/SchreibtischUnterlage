import CoreVideo

public final class CapturedFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    let sourceDisplayTime: CFTimeInterval?
    let captureCallbackTime: CFTimeInterval
    let latencyGeneration: UInt64?

    public var width: Int {
        CVPixelBufferGetWidth(pixelBuffer)
    }

    public var height: Int {
        CVPixelBufferGetHeight(pixelBuffer)
    }

    init(
        pixelBuffer: CVPixelBuffer,
        sourceDisplayTime: CFTimeInterval?,
        captureCallbackTime: CFTimeInterval,
        latencyGeneration: UInt64?
    ) {
        self.pixelBuffer = pixelBuffer
        self.sourceDisplayTime = sourceDisplayTime
        self.captureCallbackTime = captureCallbackTime
        self.latencyGeneration = latencyGeneration
    }
}
