import SwiftUI

/// Labels for the iPhone replica in the phone's display language.
struct IPhoneStrings {
    let calling, ended, speaker, facetime, mute, more, end, keypad: String
    let decline, accept, remindMe, message, slideToAnswer, hide: String

    static func forLanguage(_ language: UILanguage) -> IPhoneStrings {
        switch language {
        case .english:
            return IPhoneStrings(calling: "Calling...", ended: "Call Ended", speaker: "Speaker",
                                 facetime: "FaceTime", mute: "Mute", more: "More", end: "End",
                                 keypad: "Keypad", decline: "Decline", accept: "Accept",
                                 remindMe: "Remind Me", message: "Message",
                                 slideToAnswer: "slide to answer", hide: "Hide")
        case .chinese:
            return IPhoneStrings(calling: "正在呼叫…", ended: "通话结束", speaker: "扬声器",
                                 facetime: "FaceTime", mute: "静音", more: "更多", end: "结束",
                                 keypad: "拨号键盘", decline: "拒绝", accept: "接听",
                                 remindMe: "提醒我", message: "信息",
                                 slideToAnswer: "滑动来接听", hide: "隐藏")
        }
    }
}

/// Replica of the iOS 26 Phone call screens (incoming, dialing, in call, ended).
/// Proportions were measured from a real iOS 26 screenshot.
struct IPhoneCallScreen: View {
    @ObservedObject var engine: CallEngine
    @ObservedObject var settings: CallSettings
    @State private var showsKeypad = false
    @State private var dialed = ""

    private var text: IPhoneStrings { .forLanguage(settings.iphoneLanguage) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                IPhoneBackground()

                header(size: size)

                if engine.phase == .ringing {
                    ringingControls(size: size)
                } else if showsKeypad {
                    keypad(size: size)
                } else {
                    callControls(size: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    @ViewBuilder
    private func header(size: CGSize) -> some View {
        let status: AnyView = {
            switch engine.phase {
            case .dialing: return AnyView(Text(text.calling))
            case .connected(let start): return AnyView(CallDurationText(start: start))
            case .ended: return AnyView(Text(text.ended))
            default: return AnyView(EmptyView())
            }
        }()
        let isRinging = engine.phase == .ringing

        VStack(spacing: 6) {
            if !isRinging {
                status
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(showsKeypad && !dialed.isEmpty ? dialed : settings.iphoneTitle)
                .font(.system(size: isRinging ? 38 : 34, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)
            if !settings.iphoneSubtitle.isEmpty && !(showsKeypad && !dialed.isEmpty) {
                Text(settings.iphoneSubtitle)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: size.width)
        .at(0.5, isRinging ? 0.17 : 0.187, in: size)
    }

    // MARK: Ringing

    @ViewBuilder
    private func ringingControls(size: CGSize) -> some View {
        let circle = size.width * 0.195
        smallAction(icon: "alarm.fill", label: text.remindMe)
            .at(0.2, 0.705, in: size)
        smallAction(icon: "message.fill", label: text.message)
            .at(0.8, 0.705, in: size)

        switch settings.ringLayout {
        case .buttons:
            labeledCircle(icon: "phone.down.fill", label: text.decline,
                          fill: Color(hex: 0xEB4E3D), diameter: circle) { engine.decline() }
                .at(0.2, 0.865, in: size)
            labeledCircle(icon: "phone.fill", label: text.accept,
                          fill: Color(hex: 0x65C466), diameter: circle) { engine.answer() }
                .at(0.8, 0.865, in: size)
        case .slider:
            SlideToAnswer(label: text.slideToAnswer) { engine.answer() }
                .frame(width: size.width * 0.84, height: circle)
                .at(0.5, 0.865, in: size)
        }
    }

    private func smallAction(icon: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
            Text(label)
                .font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(.white)
    }

    // MARK: In call

    @ViewBuilder
    private func callControls(size: CGSize) -> some View {
        let circle = size.width * 0.195
        let rowOne: CGFloat = 0.72
        let rowTwo: CGFloat = 0.865
        let ended = engine.phase == .ended

        glassButton(icon: "speaker.wave.3.fill", label: text.speaker, active: engine.isSpeakerOn,
                    diameter: circle) { engine.toggleSpeaker() }
            .at(0.2, rowOne, in: size)
        glassButton(icon: "questionmark.video.fill", label: text.facetime, active: false,
                    diameter: circle, dimmed: true) {}
            .at(0.5, rowOne, in: size)
        glassButton(icon: "mic.slash.fill", label: text.mute, active: engine.isMuted,
                    diameter: circle) { engine.toggleMute() }
            .at(0.8, rowOne, in: size)
        glassButton(icon: "ellipsis", label: text.more, active: false, diameter: circle) {}
            .at(0.2, rowTwo, in: size)
        labeledCircle(icon: "phone.down.fill", label: text.end,
                      fill: Color(hex: 0xEB3B30), diameter: circle) { engine.hangUp() }
            .at(0.5, rowTwo, in: size)
            .opacity(ended ? 0.5 : 1)
        glassButton(icon: "circle.grid.3x3.fill", label: text.keypad, active: false,
                    diameter: circle) { showsKeypad = true }
            .at(0.8, rowTwo, in: size)
    }

    @ViewBuilder
    private func keypad(size: CGSize) -> some View {
        let keys = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]
        let letters = ["1": "", "2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL", "6": "MNO",
                       "7": "PQRS", "8": "TUV", "9": "WXYZ", "*": "", "0": "+", "#": ""]
        let circle = size.width * 0.2
        VStack(spacing: size.height * 0.02) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: size.width * 0.08) {
                    ForEach(row, id: \.self) { key in
                        Button { dialed.append(key) } label: {
                            VStack(spacing: -2) {
                                Text(key).font(.system(size: 34, weight: .regular))
                                if let sub = letters[key], !sub.isEmpty {
                                    Text(sub).font(.system(size: 10, weight: .bold)).kerning(2)
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(width: circle, height: circle)
                            .background(Circle().fill(.white.opacity(0.14)))
                        }
                    }
                }
            }
        }
        .at(0.5, 0.56, in: size)

        labeledCircle(icon: "phone.down.fill", label: "", fill: Color(hex: 0xEB3B30),
                      diameter: circle) { engine.hangUp() }
            .at(0.5, 0.875, in: size)
        Button(text.hide) {
            showsKeypad = false
            dialed = ""
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.white)
        .at(0.8, 0.865, in: size)
    }

    // MARK: Buttons

    private func glassButton(icon: String, label: String, active: Bool, diameter: CGFloat,
                             dimmed: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(active ? Color.white : Color.white.opacity(0.13))
                    Circle().strokeBorder(Color.white.opacity(active ? 0 : 0.28), lineWidth: 1)
                    Image(systemName: icon)
                        .font(.system(size: diameter * 0.36, weight: .medium))
                        .foregroundStyle(active ? Color.black : Color.white.opacity(dimmed ? 0.55 : 1))
                }
                .frame(width: diameter, height: diameter)
                Text(label)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private func labeledCircle(icon: String, label: String, fill: Color, diameter: CGFloat,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(fill)
                    Image(systemName: icon)
                        .font(.system(size: diameter * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: diameter, height: diameter)
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// The warm, blurred gradient the Phone app draws behind a caller without a poster.
struct IPhoneBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3B3029), Color(hex: 0x4A3322), Color(hex: 0x2E2A27)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0x7A5230, opacity: 0.85), .clear],
                           center: UnitPoint(x: 0.68, y: 0.42), startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Color(hex: 0x1E1C1B, opacity: 0.7), .clear],
                           center: UnitPoint(x: 0.1, y: 0.95), startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

/// The lock-screen "slide to answer" control.
struct SlideToAnswer: View {
    let label: String
    let onAnswer: () -> Void
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let knob = geo.size.height - 8
            let travel = geo.size.width - knob - 8
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1)
                ShimmerText(text: label)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, knob * 0.7)
                    .opacity(1 - Double(offset / max(travel, 1)) * 1.6)
                Circle()
                    .fill(Color(hex: 0x65C466))
                    .overlay(Image(systemName: "phone.fill")
                        .font(.system(size: knob * 0.36, weight: .semibold))
                        .foregroundStyle(.white))
                    .frame(width: knob, height: knob)
                    .offset(x: 4 + offset)
                    .gesture(DragGesture()
                        .onChanged { value in
                            offset = min(max(0, value.translation.width), travel)
                        }
                        .onEnded { _ in
                            if offset > travel * 0.85 {
                                offset = travel
                                onAnswer()
                            } else {
                                withAnimation(.spring(duration: 0.3)) { offset = 0 }
                            }
                        })
            }
        }
    }
}

private struct ShimmerText: View {
    let text: String

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
            Text(text)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
                .overlay(
                    LinearGradient(colors: [.clear, .white, .clear],
                                   startPoint: UnitPoint(x: phase * 1.6 - 0.4, y: 0.5),
                                   endPoint: UnitPoint(x: phase * 1.6 - 0.1, y: 0.5))
                        .mask(Text(text).font(.system(size: 22, weight: .regular)))
                )
        }
    }
}
