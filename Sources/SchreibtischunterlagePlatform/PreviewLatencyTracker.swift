import Foundation
import SchreibtischunterlageCore

public struct PreviewLatencySnapshot: Sendable {
    public let capturedFrameCount: Int
    public let coalescedFrameCount: Int
    public let deliveredFrameCount: Int
    public let submittedFrameCount: Int
    public let renderDropCount: Int
    public let presentedFrameCount: Int
    public let presentationDropCount: Int
    public let sourceToCapture: PreviewMetricDistribution?
    public let captureToDelivery: PreviewMetricDistribution?
    public let captureToSubmit: PreviewMetricDistribution?
    public let gpuExecution: PreviewMetricDistribution?
    public let submitToPresentation: PreviewMetricDistribution?
    public let captureToPresentation: PreviewMetricDistribution?
    public let sourceToPresentation: PreviewMetricDistribution?
    public let presentationInterval: PreviewMetricDistribution?

    public var effectiveFramesPerSecond: Double? {
        guard
            let presentationInterval,
            presentationInterval.average > 0
        else {
            return nil
        }
        return 1_000 / presentationInterval.average
    }
}

final class PreviewLatencyTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var capturedFrameCount = 0
    private var coalescedFrameCount = 0
    private var deliveredFrameCount = 0
    private var submittedFrameCount = 0
    private var renderDropCount = 0
    private var presentedFrameCount = 0
    private var presentationDropCount = 0
    private var sourceToCapture = [Double]()
    private var captureToDelivery = [Double]()
    private var captureToSubmit = [Double]()
    private var gpuExecution = [Double]()
    private var submitToPresentation = [Double]()
    private var captureToPresentation = [Double]()
    private var sourceToPresentation = [Double]()
    private var presentationIntervals = [Double]()
    private var lastPresentationTime: CFTimeInterval?

    var measurementGeneration: UInt64 {
        lock.withLock {
            generation
        }
    }

    func recordCapturedFrame(_ frame: CapturedFrame) {
        lock.withLock {
            guard frame.latencyGeneration == generation else {
                return
            }
            capturedFrameCount += 1
            if let sourceDisplayTime = frame.sourceDisplayTime {
                sourceToCapture.append(
                    milliseconds(
                        from: sourceDisplayTime,
                        to: frame.captureCallbackTime
                    )
                )
            }
        }
    }

    func recordCoalescedFrame(_ frame: CapturedFrame) {
        lock.withLock {
            guard frame.latencyGeneration == generation else {
                return
            }
            coalescedFrameCount += 1
        }
    }

    func recordDeliveredFrame(
        _ frame: CapturedFrame,
        at deliveryTime: CFTimeInterval
    ) {
        lock.withLock {
            guard frame.latencyGeneration == generation else {
                return
            }
            deliveredFrameCount += 1
            captureToDelivery.append(
                milliseconds(
                    from: frame.captureCallbackTime,
                    to: deliveryTime
                )
            )
        }
    }

    func recordSubmittedFrame(
        _ frame: CapturedFrame,
        at submissionTime: CFTimeInterval
    ) {
        lock.withLock {
            guard frame.latencyGeneration == generation else {
                return
            }
            submittedFrameCount += 1
            captureToSubmit.append(
                milliseconds(
                    from: frame.captureCallbackTime,
                    to: submissionTime
                )
            )
        }
    }

    func recordRenderDrop(_ frame: CapturedFrame) {
        lock.withLock {
            guard frame.latencyGeneration == generation else {
                return
            }
            renderDropCount += 1
        }
    }

    func recordGPUExecution(
        frame: CapturedFrame,
        startTime: CFTimeInterval,
        endTime: CFTimeInterval
    ) {
        guard startTime > 0, endTime >= startTime else {
            return
        }

        lock.withLock {
            guard frame.latencyGeneration == generation else {
                return
            }
            gpuExecution.append(
                milliseconds(from: startTime, to: endTime)
            )
        }
    }

    func recordPresentation(
        frame: CapturedFrame,
        submissionTime: CFTimeInterval,
        presentationTime: CFTimeInterval
    ) {
        lock.withLock {
            guard frame.latencyGeneration == generation else {
                return
            }
            guard presentationTime > 0 else {
                presentationDropCount += 1
                return
            }

            presentedFrameCount += 1
            submitToPresentation.append(
                milliseconds(
                    from: submissionTime,
                    to: presentationTime
                )
            )
            captureToPresentation.append(
                milliseconds(
                    from: frame.captureCallbackTime,
                    to: presentationTime
                )
            )
            if let sourceDisplayTime = frame.sourceDisplayTime {
                sourceToPresentation.append(
                    milliseconds(
                        from: sourceDisplayTime,
                        to: presentationTime
                    )
                )
            }
            if let lastPresentationTime,
               presentationTime >= lastPresentationTime
            {
                presentationIntervals.append(
                    milliseconds(
                        from: lastPresentationTime,
                        to: presentationTime
                    )
                )
            }
            lastPresentationTime = presentationTime
        }
    }

    func snapshot() -> PreviewLatencySnapshot {
        lock.withLock {
            PreviewLatencySnapshot(
                capturedFrameCount: capturedFrameCount,
                coalescedFrameCount: coalescedFrameCount,
                deliveredFrameCount: deliveredFrameCount,
                submittedFrameCount: submittedFrameCount,
                renderDropCount: renderDropCount,
                presentedFrameCount: presentedFrameCount,
                presentationDropCount: presentationDropCount,
                sourceToCapture: PreviewMetricDistribution(
                    samples: sourceToCapture
                ),
                captureToDelivery: PreviewMetricDistribution(
                    samples: captureToDelivery
                ),
                captureToSubmit: PreviewMetricDistribution(
                    samples: captureToSubmit
                ),
                gpuExecution: PreviewMetricDistribution(
                    samples: gpuExecution
                ),
                submitToPresentation: PreviewMetricDistribution(
                    samples: submitToPresentation
                ),
                captureToPresentation: PreviewMetricDistribution(
                    samples: captureToPresentation
                ),
                sourceToPresentation: PreviewMetricDistribution(
                    samples: sourceToPresentation
                ),
                presentationInterval: PreviewMetricDistribution(
                    samples: presentationIntervals
                )
            )
        }
    }

    func reset() {
        lock.withLock {
            generation &+= 1
            capturedFrameCount = 0
            coalescedFrameCount = 0
            deliveredFrameCount = 0
            submittedFrameCount = 0
            renderDropCount = 0
            presentedFrameCount = 0
            presentationDropCount = 0
            sourceToCapture.removeAll(keepingCapacity: true)
            captureToDelivery.removeAll(keepingCapacity: true)
            captureToSubmit.removeAll(keepingCapacity: true)
            gpuExecution.removeAll(keepingCapacity: true)
            submitToPresentation.removeAll(keepingCapacity: true)
            captureToPresentation.removeAll(keepingCapacity: true)
            sourceToPresentation.removeAll(keepingCapacity: true)
            presentationIntervals.removeAll(keepingCapacity: true)
            lastPresentationTime = nil
        }
    }

    private func milliseconds(
        from startTime: CFTimeInterval,
        to endTime: CFTimeInterval
    ) -> Double {
        (endTime - startTime) * 1_000
    }
}
