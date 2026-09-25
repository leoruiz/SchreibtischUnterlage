import Foundation

final class NewestFrameRelay: @unchecked Sendable {
    private let lock = NSLock()
    private let delivery: @MainActor @Sendable (CapturedFrame) -> Void
    private var latestFrame: CapturedFrame?
    private var deliveryScheduled = false

    init(delivery: @escaping @MainActor @Sendable (CapturedFrame) -> Void) {
        self.delivery = delivery
    }

    func submit(_ frame: CapturedFrame) {
        let shouldScheduleDelivery = lock.withLock {
            latestFrame = frame
            guard !deliveryScheduled else {
                return false
            }

            deliveryScheduled = true
            return true
        }

        guard shouldScheduleDelivery else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.deliverLatestFrame()
            }
        }
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
