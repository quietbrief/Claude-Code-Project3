import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject var engine: CallEngine
    @ObservedObject var settings: CallSettings
    @ObservedObject var watch: PhoneWatchBridge

    @State private var photoItem: PhotosPickerItem?
    @State private var importingStyle: CallStyle?
    @StateObject private var recorder = VoiceRecorder()

    var body: some View {
        NavigationStack {
            Form {
                triggerSection
                armSection
                callerSection
                screenSection
                soundSection
                voiceSection
                shortcutSection
            }
            .navigationTitle("假装来电")
            .alert("提示", isPresented: Binding(get: { engine.notice != nil },
                                              set: { if !$0 { engine.notice = nil } })) {
                Button("好") { engine.notice = nil }
            } message: {
                Text(engine.notice ?? "")
            }
            .fileImporter(isPresented: Binding(get: { importingStyle != nil },
                                               set: { if !$0 { importingStyle = nil } }),
                          allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result, let style = importingStyle {
                    do {
                        try settings.importRingtone(from: url, for: style)
                    } catch {
                        engine.notice = "导入失败：\(error.localizedDescription)"
                    }
                }
                importingStyle = nil
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        settings.saveAvatar(image)
                    }
                }
            }
        }
    }

    // MARK: Trigger

    private var triggerSection: some View {
        Section {
            Picker("样式", selection: Binding(get: { settings.defaultStyle },
                                            set: { settings.defaultStyle = $0 })) {
                ForEach(CallStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("方向", selection: Binding(get: { settings.defaultDirection },
                                            set: { settings.defaultDirection = $0 })) {
                ForEach(CallDirection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("延迟", selection: $settings.defaultDelay) {
                ForEach(TriggerRequest.delayPresets, id: \.self) {
                    Text(TriggerRequest.delayLabel($0)).tag($0)
                }
            }

            if case .scheduled(let date) = engine.phase {
                HStack {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(date.timeIntervalSince(context.date).rounded(.up)))
                        Label("\(left) 秒后响铃", systemImage: "timer")
                            .monospacedDigit()
                    }
                    Spacer()
                    Button("取消", role: .destructive) { engine.cancelScheduled() }
                }
            } else {
                Button {
                    engine.schedule(TriggerRequest(style: settings.defaultStyle,
                                                   delay: settings.defaultDelay,
                                                   direction: settings.defaultDirection))
                } label: {
                    Label("开始", systemImage: "phone.arrow.down.left.fill")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(settings.defaultStyle == .wechat ? Color(hex: 0x07C160) : .green)
            }
        } footer: {
            Text("设好延迟后锁屏或回到主屏幕即可。iPhone 样式配合“系统来电界面”能在锁屏上响起。")
        }
    }

    private var armSection: some View {
        Section {
            Toggle("待命模式", isOn: Binding(get: { engine.isArmed }, set: { engine.setArmed($0) }))
            LabeledContent("Apple Watch") {
                Text(watchStatus).foregroundStyle(.secondary)
            }
        } footer: {
            Text("开会前打开待命模式。它会用静音音频让 App 在后台保持运行，这样锁屏时手表触发和延时来电都能准时响起。关闭 App（上划清除）后待命失效。")
        }
    }

    private var watchStatus: String {
        if !watch.isPaired { return "未配对" }
        if !watch.isWatchAppInstalled { return "手表端未安装" }
        return watch.isReachable ? "已连接" : "已安装"
    }

    // MARK: Caller

    private var callerSection: some View {
        Section("来电人") {
            TextField("iPhone 联系人名（留空则显示号码）", text: $settings.iphoneName)
            TextField("号码", text: $settings.iphoneNumber)
                .keyboardType(.phonePad)
            TextField("号码下方的文字，如 Shanghai, China 或 mobile", text: $settings.iphoneSubtitle)
            TextField("微信昵称", text: $settings.wechatName)
            HStack {
                Group {
                    if let avatar = settings.avatar {
                        Image(uiImage: avatar).resizable().scaledToFill()
                    } else {
                        PlaceholderAvatar()
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                PhotosPicker("选择微信头像", selection: $photoItem, matching: .images)
                if settings.avatar != nil {
                    Spacer()
                    Button("移除", role: .destructive) { settings.saveAvatar(nil) }
                }
            }
            Toggle("微信视频通话邀请", isOn: $settings.wechatVideo)
        }
    }

    // MARK: Screen

    private var screenSection: some View {
        Section {
            Toggle("iPhone 样式使用系统来电界面", isOn: $settings.useCallKit)
            if settings.useCallKit {
                Toggle("记入电话 App 最近通话", isOn: $settings.addToRecents)
            }
            Picker("仿真响铃界面", selection: Binding(get: { settings.ringLayout },
                                                   set: { settings.ringLayout = $0 })) {
                ForEach(IPhoneRingLayout.allCases) { Text($0.title).tag($0) }
            }
            Picker("iPhone 界面语言", selection: Binding(get: { settings.iphoneLanguage },
                                                     set: { settings.iphoneLanguage = $0 })) {
                ForEach(UILanguage.allCases) { Text($0.title).tag($0) }
            }
            Toggle("贴近耳朵时黑屏", isOn: $settings.proximityBlank)
        } header: {
            Text("界面")
        } footer: {
            Text("系统来电界面由 iOS 自己绘制，外观、锁屏显示和铃声都与真实来电一致，铃声就是你在设置里选的铃声。若所在地区限制 CallKit，会自动改用仿真界面。锁屏时 iOS 真实来电只显示“滑动来接听”，解锁时显示按钮。")
        }
    }

    // MARK: Sound

    private var soundSection: some View {
        Section {
            Toggle("响铃声音", isOn: $settings.playRingtone)
            Toggle("振动", isOn: $settings.vibrate)
            Toggle("按音量键静音响铃", isOn: $settings.volumeSilences)
            ringtoneRow(.iphone)
            ringtoneRow(.wechat)
            Stepper("最长响铃 \(Int(settings.maxRingSeconds)) 秒", value: $settings.maxRingSeconds,
                    in: 15...120, step: 5)
            Stepper(settings.autoAnswerOutgoing > 0 ? "去电 \(Int(settings.autoAnswerOutgoing)) 秒后接通" : "去电不自动接通",
                    value: $settings.autoAnswerOutgoing, in: 0...30, step: 1)
        } header: {
            Text("声音")
        } footer: {
            Text("仿真界面自带合成铃声。想要与真机完全一样的铃声，可以把你自己录制或下载的铃声文件导入进来。")
        }
    }

    private func ringtoneRow(_ style: CallStyle) -> some View {
        HStack {
            Text("\(style.title)铃声")
            Spacer()
            if settings.hasCustomRingtone(style) {
                Button("恢复默认") { settings.removeRingtone(style) }
                    .buttonStyle(.borderless)
            }
            Button(settings.hasCustomRingtone(style) ? "已导入" : "导入") { importingStyle = style }
                .buttonStyle(.borderless)
        }
    }

    // MARK: Voice

    private var voiceSection: some View {
        Section {
            Picker("接通后对方", selection: Binding(get: { settings.voiceMode },
                                                 set: { settings.voiceMode = $0 })) {
                ForEach(CallerVoiceMode.allCases) { Text($0.title).tag($0) }
            }
            switch settings.voiceMode {
            case .recording:
                HStack {
                    Button(recorder.isRecording ? "停止录音" : "录一段对方的话") {
                        recorder.isRecording ? recorder.stop() : recorder.start()
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    if settings.hasVoiceRecording && !recorder.isRecording {
                        Button("试听") { recorder.play() }
                            .buttonStyle(.borderless)
                    }
                }
            case .speech:
                TextField("对方要说的话", text: $settings.voiceText, axis: .vertical)
            case .none:
                EmptyView()
            }
            if settings.voiceMode != .none {
                Stepper("接通 \(settings.voiceDelay, specifier: "%.1f") 秒后开口",
                        value: $settings.voiceDelay, in: 0...5, step: 0.5)
            }
        } header: {
            Text("对方声音")
        } footer: {
            Text("声音从听筒播放，旁人只能隐约听到有人在说话。")
        }
    }

    private var shortcutSection: some View {
        Section("更多触发方式") {
            Text("快捷指令 App 里有“开始假装来电”操作，可以绑定到轻点背面（设置 › 辅助功能 › 触控 › 轻点背面）、操作按钮或控制中心。也可以用链接 fakecall://call?style=wechat&delay=10 触发。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Records the fake caller's voice clip.
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?

    func start() {
        AVAudioApplication.requestRecordPermission { granted in
            guard granted else { return }
            Task { @MainActor in self.beginRecording() }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                       AVSampleRateKey: 44100,
                                       AVNumberOfChannelsKey: 1,
                                       AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        recorder = try? AVAudioRecorder(url: CallSettings.voiceURL, settings: settings)
        isRecording = recorder?.record() ?? false
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        CallSettings.shared.objectWillChange.send()
        if CallEngine.shared.isArmed {
            AudioController.shared.stopKeepAlive()
            AudioController.shared.startKeepAlive()
        }
    }

    func play() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(contentsOf: CallSettings.voiceURL)
        player?.play()
    }
}
