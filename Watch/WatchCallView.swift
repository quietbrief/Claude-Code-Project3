import SwiftUI
import WatchKit

/// The watch's own incoming call screen, modelled on the watchOS Phone app.
struct WatchCallView: View {
    @ObservedObject var ringer: WatchRinger
    @AppStorage("watchCallerName") private var callerName = "William"

    private var accent: Color {
        ringer.style == .wechat ? Color(red: 0.03, green: 0.76, blue: 0.38) : Color(red: 0.4, green: 0.77, blue: 0.4)
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(callerName)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            subtitle
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                circle(icon: "phone.down.fill", color: Color(red: 0.92, green: 0.3, blue: 0.24)) {
                    ringer.stop()
                }
                Spacer()
                if ringer.phase == .ringing {
                    circle(icon: "phone.fill", color: accent) { ringer.answer() }
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch ringer.phase {
        case .waiting(let date):
            Text(date, style: .timer)
        case .ringing:
            Text(ringer.style == .wechat ? "邀请你语音通话" : "iPhone")
        case .connected(let start):
            Text(start, style: .timer)
        case .idle:
            EmptyView()
        }
    }

    private func circle(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(color))
        }
        .buttonStyle(.plain)
    }
}
