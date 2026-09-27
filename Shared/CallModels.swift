import Foundation

/// Which call screen the fake call imitates.
enum CallStyle: String, Codable, CaseIterable, Identifiable {
    case iphone
    case wechat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iphone: return "iPhone 电话"
        case .wechat: return "微信语音"
        }
    }
}

/// Whether someone "calls you" or you appear to be calling someone.
enum CallDirection: String, Codable, CaseIterable, Identifiable {
    case incoming
    case outgoing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incoming: return "来电"
        case .outgoing: return "去电"
        }
    }
}

/// A request to start a fake call, sent from the watch, a shortcut or the app itself.
struct TriggerRequest: Codable, Equatable {
    var style: CallStyle
    var delay: TimeInterval
    var direction: CallDirection = .incoming

    static let delayPresets: [TimeInterval] = [0, 5, 10, 30, 60, 180, 300]

    static func delayLabel(_ delay: TimeInterval) -> String {
        if delay <= 0 { return "立即" }
        if delay < 60 { return "\(Int(delay)) 秒" }
        return "\(Int(delay / 60)) 分钟"
    }
}

/// Keys and commands used over WatchConnectivity.
enum WatchMessage {
    static let command = "cmd"
    static let style = "style"
    static let delay = "delay"
    static let direction = "direction"

    static let trigger = "trigger"
    static let cancel = "cancel"
    static let status = "status"

    static let ok = "ok"
    static let detail = "detail"

    static func encode(_ request: TriggerRequest) -> [String: Any] {
        [command: trigger,
         style: request.style.rawValue,
         delay: request.delay,
         direction: request.direction.rawValue]
    }

    static func decode(_ message: [String: Any]) -> TriggerRequest? {
        guard message[command] as? String == trigger,
              let rawStyle = message[style] as? String,
              let callStyle = CallStyle(rawValue: rawStyle) else { return nil }
        let seconds = (message[delay] as? Double) ?? Double(message[delay] as? Int ?? 0)
        let rawDirection = message[direction] as? String ?? CallDirection.incoming.rawValue
        return TriggerRequest(style: callStyle,
                              delay: max(0, seconds),
                              direction: CallDirection(rawValue: rawDirection) ?? .incoming)
    }
}
