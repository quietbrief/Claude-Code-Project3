import SwiftUI
import UIKit

enum CallerVoiceMode: String, CaseIterable, Identifiable {
    case none
    case recording
    case speech

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无声"
        case .recording: return "播放录音"
        case .speech: return "朗读文字"
        }
    }
}

enum IPhoneRingLayout: String, CaseIterable, Identifiable {
    case buttons
    case slider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .buttons: return "接听/拒绝按钮"
        case .slider: return "滑动来接听"
        }
    }
}

enum UILanguage: String, CaseIterable, Identifiable {
    case english
    case chinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

/// Everything the user can configure, persisted in UserDefaults.
@MainActor
final class CallSettings: ObservableObject {
    static let shared = CallSettings()

    // Caller identity
    @AppStorage("iphoneName") var iphoneName = ""
    @AppStorage("iphoneNumber") var iphoneNumber = "(021) 5871 3997"
    @AppStorage("iphoneSubtitle") var iphoneSubtitle = "Shanghai, China"
    @AppStorage("wechatName") var wechatName = "William"
    @AppStorage("wechatVideo") var wechatVideo = false

    // Behaviour
    @AppStorage("defaultStyle") var defaultStyleRaw = CallStyle.iphone.rawValue
    @AppStorage("defaultDirection") var defaultDirectionRaw = CallDirection.incoming.rawValue
    @AppStorage("defaultDelay") var defaultDelay: Double = 10
    @AppStorage("useCallKit") var useCallKit = true
    @AppStorage("addToRecents") var addToRecents = true
    @AppStorage("ringLayout") var ringLayoutRaw = IPhoneRingLayout.buttons.rawValue
    @AppStorage("iphoneLanguage") var iphoneLanguageRaw = UILanguage.english.rawValue
    @AppStorage("playRingtone") var playRingtone = true
    @AppStorage("vibrate") var vibrate = true
    @AppStorage("volumeSilences") var volumeSilences = true
    @AppStorage("proximityBlank") var proximityBlank = true
    @AppStorage("autoAnswerOutgoing") var autoAnswerOutgoing: Double = 6
    @AppStorage("maxRingSeconds") var maxRingSeconds: Double = 45

    // Caller voice
    @AppStorage("voiceMode") var voiceModeRaw = CallerVoiceMode.none.rawValue
    @AppStorage("voiceText") var voiceText = "喂，你现在方便吗？这边有点急事，需要你马上过来处理一下。"
    @AppStorage("voiceDelay") var voiceDelay: Double = 1.5

    @Published var avatar: UIImage?

    var defaultStyle: CallStyle {
        get { CallStyle(rawValue: defaultStyleRaw) ?? .iphone }
        set { defaultStyleRaw = newValue.rawValue }
    }

    var defaultDirection: CallDirection {
        get { CallDirection(rawValue: defaultDirectionRaw) ?? .incoming }
        set { defaultDirectionRaw = newValue.rawValue }
    }

    var ringLayout: IPhoneRingLayout {
        get { IPhoneRingLayout(rawValue: ringLayoutRaw) ?? .buttons }
        set { ringLayoutRaw = newValue.rawValue }
    }

    var iphoneLanguage: UILanguage {
        get { UILanguage(rawValue: iphoneLanguageRaw) ?? .english }
        set { iphoneLanguageRaw = newValue.rawValue }
    }

    var voiceMode: CallerVoiceMode {
        get { CallerVoiceMode(rawValue: voiceModeRaw) ?? .none }
        set { voiceModeRaw = newValue.rawValue }
    }

    /// The big line on the iPhone screen: the contact name if set, otherwise the number.
    var iphoneTitle: String {
        let name = iphoneName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? iphoneNumber : name
    }

    private init() {
        avatar = UIImage(contentsOfFile: Self.avatarURL.path)
    }

    // MARK: Files

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var avatarURL: URL { documents.appendingPathComponent("avatar.jpg") }
    static var voiceURL: URL { documents.appendingPathComponent("caller_voice.m4a") }

    static func customRingtoneURL(for style: CallStyle) -> URL {
        documents.appendingPathComponent("ringtone_\(style.rawValue).audio")
    }

    func saveAvatar(_ image: UIImage?) {
        avatar = image
        if let data = image?.jpegData(compressionQuality: 0.9) {
            try? data.write(to: Self.avatarURL)
        } else {
            try? FileManager.default.removeItem(at: Self.avatarURL)
        }
    }

    func hasCustomRingtone(_ style: CallStyle) -> Bool {
        FileManager.default.fileExists(atPath: Self.customRingtoneURL(for: style).path)
    }

    func importRingtone(from url: URL, for style: CallStyle) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let target = Self.customRingtoneURL(for: style)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: url, to: target)
        objectWillChange.send()
    }

    func removeRingtone(_ style: CallStyle) {
        try? FileManager.default.removeItem(at: Self.customRingtoneURL(for: style))
        objectWillChange.send()
    }

    var hasVoiceRecording: Bool {
        FileManager.default.fileExists(atPath: Self.voiceURL.path)
    }
}
