import Foundation

@MainActor
final class CaptureScheduler {
    private var timer: Timer?
    private let intervalProvider: () -> TimeInterval
    private let action: () async -> Void

    init(
        intervalProvider: @escaping () -> TimeInterval,
        action: @escaping () async -> Void
    ) {
        self.intervalProvider = intervalProvider
        self.action = action
    }

    func start() {
        guard timer == nil else { return }
        trigger()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func trigger() {
        Task { [weak self] in
            await self?.action()
            self?.scheduleNext()
        }
    }

    private func scheduleNext() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(5, intervalProvider()), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.trigger()
            }
        }
    }
}
