import SwiftUI

@main
struct FakeCallApp: App {
    @StateObject private var engine = CallEngine.shared
    @StateObject private var settings = CallSettings.shared
    @StateObject private var watch = PhoneWatchBridge.shared

    init() {
        PhoneWatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            HomeView(engine: engine, settings: settings, watch: watch)
                .fullScreenCover(isPresented: $engine.showsReplica) {
                    CallScreen(engine: engine, settings: settings)
                }
                .onOpenURL(perform: handle)
        }
    }

    /// fakecall://call?style=wechat&delay=10&direction=incoming, handy for Shortcuts.
    private func handle(_ url: URL) {
        guard url.scheme == "fakecall" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let style = value("style").flatMap(CallStyle.init(rawValue:)) ?? settings.defaultStyle
        let delay = value("delay").flatMap(Double.init) ?? settings.defaultDelay
        let direction = value("direction").flatMap(CallDirection.init(rawValue:)) ?? .incoming
        engine.schedule(TriggerRequest(style: style, delay: delay, direction: direction))
    }
}

struct CallScreen: View {
    @ObservedObject var engine: CallEngine
    @ObservedObject var settings: CallSettings

    var body: some View {
        Group {
            switch engine.request.style {
            case .iphone: IPhoneCallScreen(engine: engine, settings: settings)
            case .wechat: WeChatCallScreen(engine: engine, settings: settings)
            }
        }
        .statusBarHidden(false)
    }
}
