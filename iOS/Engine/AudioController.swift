import AVFoundation
import AudioToolbox
import UIKit

/// Owns every sound the fake call makes: ringtones, ringback, the caller's voice,
/// vibration and the silent keep-alive loop used while the app is armed.
@MainActor
final class AudioController: NSObject {
    static let shared = AudioController()

    private var loopPlayer: AVAudioPlayer?
    private var keepAlivePlayer: AVAudioPlayer?
    private var voicePlayer: AVAudioPlayer?
    private var cuePlayer: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var vibrationTimer: Timer?
    private var voiceTask: Task<Void, Never>?
    private var volumeObservation: NSKeyValueObservation?

    private(set) var isKeepingAlive = false
    var onVolumeButton: (() -> Void)?

    private var session: AVAudioSession { .sharedInstance() }

    // MARK: Keep-alive

    /// Plays a silent, mixable loop so iOS keeps the app running in the background.
    /// This is what lets a watch trigger or a delayed call fire while the phone is locked.
    func startKeepAlive() {
        guard !isKeepingAlive else { return }
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: bundled("silence"))
            player.numberOfLoops = -1
            player.volume = 0
            player.play()
            keepAlivePlayer = player
            isKeepingAlive = true
        } catch {
            print("Keep-alive failed: \(error)")
        }
    }

    func stopKeepAlive() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        isKeepingAlive = false
    }

    // MARK: Ringing

    func startRinging(style: CallStyle, sound: Bool, vibrate: Bool) {
        stopLoop()
        if sound {
            do {
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                let url = ringtoneURL(for: style)
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.volume = 1
                player.play()
                loopPlayer = player
            } catch {
                print("Ringtone failed: \(error)")
            }
        }
        if vibrate {
            startVibration(interval: style == .iphone ? 2.0 : 1.4)
        }
        observeVolumeButtons()
    }

    /// Quiets the ringer the way pressing a volume button does on a real iPhone.
    func silenceRinging() {
        loopPlayer?.stop()
        loopPlayer = nil
        stopVibration()
    }

    // MARK: Outgoing ringback

    func startRingback(style: CallStyle) {
        stopLoop()
        prepareCallSession(speaker: false)
        let name = style == .iphone ? "ringback_cn" : "wait_wechat"
        if let player = try? AVAudioPlayer(contentsOf: bundled(name)) {
            player.numberOfLoops = -1
            player.volume = 0.8
            player.play()
            loopPlayer = player
        }
    }

    // MARK: Connected call

    /// Routes audio to the earpiece like a real call. `playAndRecord` also lights
    /// the orange microphone dot, which is exactly what a real call shows.
    func prepareCallSession(speaker: Bool) {
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
            try session.setActive(true)
            try session.overrideOutputAudioPort(speaker ? .speaker : .none)
        } catch {
            print("Call session failed: \(error)")
        }
    }

    /// CallKit activates the session itself, so only the category is set here.
    func configureForCallKit() {
        stopKeepAlive()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
    }

    func setSpeaker(_ on: Bool) {
        try? session.overrideOutputAudioPort(on ? .speaker : .none)
    }

    /// Plays the caller's recorded clip or reads the script aloud after a short pause.
    /// Pass `configureSession: false` when CallKit already owns the audio session.
    func startCallerVoice(mode: CallerVoiceMode, text: String, after delay: TimeInterval,
                          configureSession: Bool = true) {
        stopLoop()
        if configureSession { prepareCallSession(speaker: false) }
        voiceTask?.cancel()
        guard mode != .none else { return }
        voiceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            switch mode {
            case .recording:
                if let player = try? AVAudioPlayer(contentsOf: CallSettings.voiceURL) {
                    player.play()
                    self.voicePlayer = player
                }
            case .speech:
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: Self.speechLanguage(for: text))
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
                self.synthesizer.speak(utterance)
            case .none:
                break
            }
        }
    }

    func playCue(_ name: String) {
        if let player = try? AVAudioPlayer(contentsOf: bundled(name)) {
            player.play()
            cuePlayer = player
        }
    }

    /// Stops everything the call started and gives the session back.
    func endCall(restoreKeepAlive: Bool) {
        stopLoop()
        voiceTask?.cancel()
        voicePlayer?.stop()
        voicePlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
        volumeObservation = nil
        if restoreKeepAlive {
            isKeepingAlive = false
            startKeepAlive()
        }
    }

    func stopLoop() {
        loopPlayer?.stop()
        loopPlayer = nil
        stopVibration()
    }

    // MARK: Helpers

    func ringtoneURL(for style: CallStyle) -> URL {
        let custom = CallSettings.customRingtoneURL(for: style)
        if FileManager.default.fileExists(atPath: custom.path) { return custom }
        return bundled(style == .iphone ? "ring_iphone" : "ring_wechat")
    }

    func bundled(_ name: String) -> URL {
        Bundle.main.url(forResource: name, withExtension: "wav")!
    }

    private func startVibration(interval: TimeInterval) {
        stopVibration()
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func stopVibration() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }

    private func observeVolumeButtons() {
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.onVolumeButton?() }
        }
    }

    private static func speechLanguage(for text: String) -> String {
        let hasChinese = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        return hasChinese ? "zh-CN" : "en-US"
    }
}
