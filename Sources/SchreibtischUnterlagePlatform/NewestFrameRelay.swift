import Foundation

final class NewestFrameRelay: @unchecked Sendable {
    private let lock = NSLock()
    private let delivery: @MainActor @Sendable (CapturedFrame) -> Void
    private var latestFrame: CapturedFrame?
    private var deliveryScheduled = false

    init(delivery: @escaping @MainActor @Sendable (CapturedFrame) -> Void) {
        self.delivery = delivery
    }

    @discardableResult
    func submit(_ frame: CapturedFrame) -> CapturedFrame? {
        let result = lock.withLock {
            let replacedPendingFrame = latestFrame
            latestFrame = frame
            guard !deliveryScheduled else {
                return (false, replacedPendingFrame)
            }

            deliveryScheduled = true
            return (true, replacedPendingFrame)
        }

        guard result.0 else {
            return result.1
        }

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.deliverLatestFrame()
            }
        }
        return result.1
    }

    @MainActor
    private func deliverLatestFrame() {
        let frame = lock.withLock {
            let frame = latestFrame
            latestFrame = nil
            deliveryScheduled = false
            return frame
        }

        if let frame {
            delivery(frame)
        }
    }
}
