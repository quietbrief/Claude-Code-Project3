import SwiftUI

@main
struct FakeCallWatchApp: App {
    @StateObject private var bridge = WatchBridge.shared
    @StateObject private var ringer = WatchRinger.shared

    init() {
        WatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(bridge: bridge, ringer: ringer)
                .onOpenURL(perform: handle)
        }
    }

    /// Complications open fakecall-watch://trigger?style=iphone so one tap on the
    /// watch face starts the call.
    private func handle(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let rawStyle = items.first { $0.name == "style" }?.value ?? CallStyle.iphone.rawValue
        let style = CallStyle(rawValue: rawStyle) ?? .iphone
        WatchHomeView.trigger(style: style, bridge: bridge, ringer: ringer)
    }
}
