import SwiftUI
import WatchKit

struct WatchHomeView: View {
    @ObservedObject var bridge: WatchBridge
    @ObservedObject var ringer: WatchRinger
    @AppStorage("watchDelay") private var delay: Double = 5
    @AppStorage("watchTarget") private var targetRaw = WatchTarget.phone.rawValue
    @AppStorage("watchCallerName") private var callerName = "William"

    static let delays: [TimeInterval] = [0, 5, 10, 30, 60, 300]

    var body: some View {
        if ringer.phase == .idle {
            home
        } else {
            WatchCallView(ringer: ringer)
        }
    }

    private var home: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    triggerButton(style: .iphone, color: .green, icon: "phone.fill")
                    triggerButton(style: .wechat, color: Color(red: 0.03, green: 0.76, blue: 0.38),
                                  icon: "message.fill")

                    Picker("延迟", selection: $delay) {
                        ForEach(Self.delays, id: \.self) { Text(TriggerRequest.delayLabel($0)).tag($0) }
                    }
                    .frame(height: 50)

                    Picker("在哪里响", selection: $targetRaw) {
                        ForEach(WatchTarget.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .frame(height: 50)

                    TextField("手表上显示的来电人", text: $callerName)

                    Button("取消待响的来电", role: .destructive) { bridge.cancel() }
                        .font(.footnote)

                    Text(bridge.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle("假装来电")
        }
    }

    private func triggerButton(style: CallStyle, color: Color, icon: String) -> some View {
        Button {
            Self.trigger(style: style, bridge: bridge, ringer: ringer)
        } label: {
            Label(style.title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .tint(color)
        .buttonStyle(.borderedProminent)
    }

    /// Shared by the buttons and the complications.
    static func trigger(style: CallStyle, bridge: WatchBridge, ringer: WatchRinger) {
        let defaults = UserDefaults.standard
        let delay = defaults.object(forKey: "watchDelay") as? Double ?? 5
        let target = WatchTarget(rawValue: defaults.string(forKey: "watchTarget") ?? "") ?? .phone
        let request = TriggerRequest(style: style, delay: delay)
        WKHaptic.confirm()

        var ringWatch = target != .phone
        if target != .watch {
            let delivered = bridge.send(request)
            // If the phone is out of reach, ring the wrist so there is still an excuse to leave.
            if !delivered { ringWatch = true }
        }
        if ringWatch {
            ringer.ring(style: style, after: delay)
        }
    }
}

private enum WKHaptic {
    static func confirm() {
        WKInterfaceDevice.current().play(.click)
    }
}
