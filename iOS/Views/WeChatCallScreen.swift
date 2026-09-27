import AVFoundation
import SwiftUI

/// Replica of the WeChat voice/video call screens. Proportions were measured from a
/// real WeChat screenshot ("等待对方接受邀请..").
struct WeChatCallScreen: View {
    @ObservedObject var engine: CallEngine
    @ObservedObject var settings: CallSettings
    @State private var micOn = true

    private var isVideoInvite: Bool {
        settings.wechatVideo && engine.phase == .ringing && engine.request.direction == .incoming
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                background

                topBar(size: size)

                avatar
                    .frame(width: size.width * 0.24, height: size.width * 0.24)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .at(0.5, 0.342, in: size)

                Text(settings.wechatName)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 30)
                    .frame(width: size.width)
                    .at(0.5, 0.431, in: size)

                statusLine
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.6))
                    .at(0.5, 0.605, in: size)

                controls(size: size)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: Background

    @ViewBuilder
    private var background: some View {
        ZStack {
            Color(hex: 0x1B1B1B)
            if isVideoInvite {
                CameraPreview()
            } else if let image = settings.avatar {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .scaleEffect(1.3)
            }
            Color.black.opacity(isVideoInvite ? 0.25 : 0.62)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var avatar: some View {
        if let image = settings.avatar {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            PlaceholderAvatar()
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusLine: some View {
        switch engine.phase {
        case .ringing:
            HStack(spacing: 0) {
                Text(settings.wechatVideo ? "邀请你视频通话" : "邀请你语音通话")
                AnimatedDots()
            }
        case .dialing:
            HStack(spacing: 0) {
                Text("等待对方接受邀请")
                AnimatedDots()
            }
        case .connected(let start):
            CallDurationText(start: start)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.85))
        case .ended:
            Text("通话已结束")
        default:
            EmptyView()
        }
    }

    // MARK: Top bar

    @ViewBuilder
    private func topBar(size: CGSize) -> some View {
        MinimizeGlyph()
            .frame(width: 28, height: 28)
            .at(0.098, 0.095, in: size)
        if engine.phase != .ringing {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white)
                .at(0.93, 0.092, in: size)
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private func controls(size: CGSize) -> some View {
        let diameter = size.width * 0.178
        if engine.phase == .ringing {
            if isVideoInvite {
                smallButton(icon: "phone.fill", label: "切到语音接听") { engine.answer() }
                    .at(0.73, 0.69, in: size)
            }
            circleButton(icon: "phone.down.fill", label: "挂断", fill: Color(hex: 0xFA5151),
                         iconColor: .white, diameter: diameter) { engine.decline() }
                .at(0.27, 0.828, in: size)
            circleButton(icon: settings.wechatVideo ? "video.fill" : "phone.fill", label: "接听",
                         fill: Color(hex: 0x07C160), iconColor: .white, diameter: diameter) { engine.answer() }
                .at(0.73, 0.828, in: size)
        } else {
            circleButton(icon: micOn ? "mic.fill" : "mic.slash.fill",
                         label: micOn ? "麦克风已开" : "麦克风已关",
                         fill: micOn ? .white : .white.opacity(0.14),
                         iconColor: micOn ? .black : .white, diameter: diameter) {
                micOn.toggle()
                engine.toggleMute()
            }
            .at(0.204, 0.828, in: size)

            circleButton(icon: "phone.down.fill", label: engine.phase == .dialing ? "取消" : "挂断",
                         fill: Color(hex: 0xFA5151), iconColor: .white, diameter: diameter) {
                engine.hangUp()
            }
            .at(0.5, 0.828, in: size)

            circleButton(icon: engine.isSpeakerOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                         label: engine.isSpeakerOn ? "扬声器已开" : "扬声器已关",
                         fill: engine.isSpeakerOn ? .white : .white.opacity(0.14),
                         iconColor: engine.isSpeakerOn ? .black : .white, diameter: diameter) {
                engine.toggleSpeaker()
            }
            .at(0.795, 0.828, in: size)
        }
    }

    private func circleButton(icon: String, label: String, fill: Color, iconColor: Color,
                              diameter: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(fill)
                    Image(systemName: icon)
                        .font(.system(size: diameter * 0.36, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                .frame(width: diameter, height: diameter)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
    }

    private func smallButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(.white.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
    }
}

/// WeChat's "minimize to floating window" icon: a rounded frame with a small tile.
struct MinimizeGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: w * 0.14, style: .continuous)
                    .strokeBorder(.white, lineWidth: w * 0.08)
                    .frame(width: w * 0.72, height: w * 0.82)
                RoundedRectangle(cornerRadius: w * 0.1, style: .continuous)
                    .fill(Color.black.opacity(0.001))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.1, style: .continuous)
                        .strokeBorder(.white, lineWidth: w * 0.08))
                    .frame(width: w * 0.48, height: w * 0.44)
                    .offset(x: w * 0.52, y: w * 0.56)
            }
        }
    }
}

/// Front camera preview, which WeChat shows behind an incoming video call.
struct CameraPreview: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        let session = AVCaptureSession()

        func start() {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            let session = self.session
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }

        deinit {
            let session = self.session
            DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.main.async { view.start() }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
