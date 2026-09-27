import Foundation
import WatchConnectivity

/// Sends triggers to the iPhone. `sendMessage` wakes the iPhone app in the background.
@MainActor
final class WatchBridge: NSObject, ObservableObject {
    static let shared = WatchBridge()

    @Published var status = "准备就绪"
    @Published private(set) var isReachable = false

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Returns false when the phone cannot be reached, so the caller can ring the watch instead.
    @discardableResult
    func send(_ request: TriggerRequest) -> Bool {
        let session = WCSession.default
        guard session.activationState == .activated else {
            status = "未连接 iPhone"
            return false
        }
        guard session.isReachable else {
            // Queued delivery; it arrives when the phone next wakes the app, which may be late.
            session.transferUserInfo(WatchMessage.encode(request))
            status = "iPhone 暂时不可达，已排队"
            return false
        }
        status = "发送中…"
        session.sendMessage(WatchMessage.encode(request), replyHandler: { reply in
            let detail = reply[WatchMessage.detail] as? String ?? "已发送"
            Task { @MainActor in self.status = detail }
        }, errorHandler: { error in
            Task { @MainActor in self.status = "发送失败：\(error.localizedDescription)" }
        })
        return true
    }

    func cancel() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([WatchMessage.command: WatchMessage.cancel], replyHandler: { reply in
            let detail = reply[WatchMessage.detail] as? String ?? "已取消"
            Task { @MainActor in self.status = detail }
        }, errorHandler: nil)
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }
}
