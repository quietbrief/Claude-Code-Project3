import SwiftUI
import WatchKit

enum WatchTarget: String, CaseIterable, Identifiable {
    case phone
    case watch
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone: return "iPhone"
        case .watch: return "手表"
        case .both: return "两者"
        }
    }
}

/// Rings on the watch itself. Third-party CallKit calls never reach the watch, so the
/// watch draws its own call screen and taps your wrist.
@MainActor
final class WatchRinger: NSObject, ObservableObject {
    static let shared = WatchRinger()

    enum Phase: Equatable {
        case idle
        case waiting(Date)
        case ringing
        case connected(Date)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var style: CallStyle = .iphone

    private var hapticTimer: Timer?
    private var delayTimer: Timer?
    private var alarmSession: WKExtendedRuntimeSession?

    func ring(style: CallStyle, after delay: TimeInterval) {
        stop()
        self.style = style
        guard delay > 0 else {
            startRinging()
            return
        }
        let date = Date().addingTimeInterval(delay)
        phase = .waiting(date)
        // A smart-alarm session keeps tapping the wrist even if the screen has turned off.
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start(at: date)
        alarmSession = session
        // Foreground fallback in case the alarm session is not allowed.
        delayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .waiting = self.phase else { return }
                self.startRinging(with: self.alarmSession)
            }
        }
    }

    fileprivate func startRinging(with session: WKExtendedRuntimeSession? = nil) {
        delayTimer?.invalidate()
        guard phase != .ringing else { return }
        phase = .ringing
        if let session, session.state == .running {
            session.notifyUser(hapticType: .notification) { _ in
                1.2
            }
        } else {
            WKInterfaceDevice.current().play(.notification)
            hapticTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
                Task { @MainActor in WKInterfaceDevice.current().play(.notification) }
            }
        }
    }

    func answer() {
        stopHaptics()
        phase = .connected(Date())
    }

    func stop() {
        stopHaptics()
        delayTimer?.invalidate()
        delayTimer = nil
        phase = .idle
    }

    private func stopHaptics() {
        hapticTimer?.invalidate()
        hapticTimer = nil
        alarmSession?.invalidate()
        alarmSession = nil
    }
}

extension WatchRinger: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            guard case .waiting = self.phase else { return }
            self.startRinging(with: extendedRuntimeSession)
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {}
}
