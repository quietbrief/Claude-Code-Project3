import AppIntents

extension CallStyle: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "通话样式" }
    static var caseDisplayRepresentations: [CallStyle: DisplayRepresentation] {
        [.iphone: "iPhone 电话", .wechat: "微信语音"]
    }
}

extension CallDirection: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "方向" }
    static var caseDisplayRepresentations: [CallDirection: DisplayRepresentation] {
        [.incoming: "来电", .outgoing: "去电"]
    }
}

/// Lets Shortcuts, Siri, Back Tap, the Action button and Control Center start a call.
struct StartFakeCallIntent: AppIntent {
    static var title: LocalizedStringResource = "开始假装来电"
    static var description = IntentDescription("在设定的延迟后显示一通假来电。")
    static var openAppWhenRun = true

    @Parameter(title: "样式", default: .iphone)
    var style: CallStyle

    @Parameter(title: "延迟（秒）", default: 10, inclusiveRange: (0, 600))
    var delay: Int

    @Parameter(title: "方向", default: .incoming)
    var direction: CallDirection

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$delay) 秒后 \(\.$style) \(\.$direction)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        CallEngine.shared.schedule(TriggerRequest(style: style, delay: TimeInterval(delay), direction: direction))
        return .result()
    }
}

struct FakeCallShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFakeCallIntent(),
                    phrases: ["用\(.applicationName)假装来电", "Start a fake call with \(.applicationName)"],
                    shortTitle: "假装来电",
                    systemImageName: "phone.arrow.down.left")
    }
}
