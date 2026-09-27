import Foundation
import WatchConnectivity

/// Receives triggers from the Apple Watch app. A `sendMessage` from the watch wakes
/// this app in the background, which is enough time to report a CallKit call.
@MainActor
final class PhoneWatchBridge: NSObject, ObservableObject {
    static let shared = PhoneWatchBridge()

    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isReachable = false

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func refresh(_ session: WCSession) {
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }

    fileprivate func handle(_ message: [String: Any]) -> [String: Any] {
        let engine = CallEngine.shared
        switch message[WatchMessage.command] as? String {
        case WatchMessage.trigger:
            guard let request = WatchMessage.decode(message) else {
                return [WatchMessage.ok: false, WatchMessage.detail: "无法识别的请求"]
            }
            let detail = engine.schedule(request)
            return [WatchMessage.ok: true, WatchMessage.detail: detail]
        case WatchMessage.cancel:
            engine.cancelScheduled()
            return [WatchMessage.ok: true, WatchMessage.detail: "已取消"]
        default:
            let armed = engine.isArmed ? "iPhone 已待命" : "iPhone 未待命"
            return [WatchMessage.ok: true, WatchMessage.detail: armed]
        }
    }
}

extension PhoneWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.refresh(session) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh(session) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh(session) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            replyHandler(self.handle(message))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in _ = self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in _ = self.handle(userInfo) }
    }
}
