import SwiftUI
import UIKit
import UserNotifications

enum CallPhase: Equatable {
    case idle
    case scheduled(Date)
    case ringing
    case dialing
    case connected(Date)
    case ended
}

/// The state machine behind every fake call, whichever screen it is shown on.
@MainActor
final class CallEngine: ObservableObject {
    static let shared = CallEngine()

    @Published private(set) var phase: CallPhase = .idle
    @Published private(set) var request = TriggerRequest(style: .iphone, delay: 0)
    @Published var showsReplica = false
    @Published var isMuted = false
    @Published var isSpeakerOn = false
    @Published private(set) var isArmed = false
    @Published var notice: String?

    private let settings = CallSettings.shared
    private let audio = AudioController.shared
    private let callKit = CallKitManager.shared

    private var fireTimer: Timer?
    private var phaseTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var usingCallKit = false

    private init() {
        callKit.onAnswered = { [weak self] in self?.callKitAnswered() }
        callKit.onEnded = { [weak self] in self?.callKitEnded() }
        callKit.onAudioActivated = { [weak self] in
            guard let self else { return }
            self.audio.startCallerVoice(mode: self.settings.voiceMode, text: self.settings.voiceText,
                                        after: self.settings.voiceDelay, configureSession: false)
        }
        audio.onVolumeButton = { [weak self] in
            guard let self, self.phase == .ringing, self.settings.volumeSilences else { return }
            self.audio.silenceRinging()
        }
    }

    // MARK: Arming

    /// Keeps the app alive in the background so the watch and delayed calls work
    /// while the phone is locked in a pocket.
    func setArmed(_ armed: Bool) {
        isArmed = armed
        if armed {
            audio.startKeepAlive()
            requestNotificationPermission()
        } else if phase == .idle {
            audio.stopKeepAlive()
        }
    }

    // MARK: Scheduling

    @discardableResult
    func schedule(_ newRequest: TriggerRequest) -> String {
        guard phase == .idle || isScheduled else {
            return "已有通话进行中"
        }
        cancelTimers()
        request = newRequest
        if newRequest.delay <= 0 {
            fire()
            return "已触发 \(newRequest.style.title)"
        }
        let fireDate = Date().addingTimeInterval(newRequest.delay)
        phase = .scheduled(fireDate)
        beginBackgroundTask()
        fireTimer = Timer.scheduledTimer(withTimeInterval: newRequest.delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
        return "\(TriggerRequest.delayLabel(newRequest.delay))后\(newRequest.style.title)"
    }

    func cancelScheduled() {
        guard isScheduled else { return }
        cancelTimers()
        phase = .idle
        endBackgroundTask()
    }

    var isScheduled: Bool {
        if case .scheduled = phase { return true }
        return false
    }

    // MARK: Firing

    private func fire() {
        fireTimer = nil
        isMuted = false
        isSpeakerOn = false

        if request.direction == .outgoing {
            startOutgoing()
            return
        }

        if request.style == .iphone && settings.useCallKit {
            usingCallKit = true
            phase = .ringing
            audio.stopKeepAlive()
            callKit.reportIncoming(name: settings.iphoneName, number: settings.iphoneNumber,
                                   includeRecents: settings.addToRecents) { [weak self] error in
                guard let self else { return }
                if let error {
                    // CallKit is refused on some devices (mainland China region), so fall back.
                    self.usingCallKit = false
                    self.notice = "系统来电界面不可用，已切换为仿真界面（\(error.localizedDescription)）"
                    self.startReplicaRinging()
                } else {
                    self.startRingTimeout()
                }
                self.endBackgroundTask()
            }
            return
        }

        usingCallKit = false
        startReplicaRinging()
        endBackgroundTask()
    }

    private func startReplicaRinging() {
        phase = .ringing
        showsReplica = true
        audio.startRinging(style: request.style, sound: settings.playRingtone, vibrate: settings.vibrate)
        if UIApplication.shared.applicationState != .active {
            postCallNotification()
        }
        startRingTimeout()
    }

    private func startOutgoing() {
        usingCallKit = false
        phase = .dialing
        showsReplica = true
        audio.startRingback(style: request.style)
        let wait = settings.autoAnswerOutgoing
        if wait > 0 {
            phaseTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.connect() }
            }
        }
    }

    private func startRingTimeout() {
        phaseTimer?.invalidate()
        let limit = settings.maxRingSeconds
        guard limit > 0 else { return }
        phaseTimer = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.ringTimedOut() }
        }
    }

    private func ringTimedOut() {
        guard phase == .ringing else { return }
        if usingCallKit {
            callKit.remoteHangUp(unanswered: true)
        } else {
            finish(playCue: false)
        }
    }

    // MARK: User actions (replica screens)

    func answer() {
        guard phase == .ringing else { return }
        connect()
    }

    private func connect() {
        phaseTimer?.invalidate()
        phase = .connected(Date())
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        audio.startCallerVoice(mode: settings.voiceMode, text: settings.voiceText,
                               after: settings.voiceDelay)
        if settings.proximityBlank {
            UIDevice.current.isProximityMonitoringEnabled = true
        }
    }

    func decline() {
        hangUp()
    }

    func hangUp() {
        switch phase {
        case .ringing, .dialing, .connected:
            finish(playCue: true)
        default:
            break
        }
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        audio.setSpeaker(isSpeakerOn)
    }

    private func finish(playCue: Bool) {
        phaseTimer?.invalidate()
        UIDevice.current.isProximityMonitoringEnabled = false
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        let wasConnected: Bool
        if case .connected = phase { wasConnected = true } else { wasConnected = false }
        audio.endCall(restoreKeepAlive: false)
        if playCue && (wasConnected || phase == .dialing) {
            audio.playCue(request.style == .iphone ? "hangup_iphone" : "hangup_wechat")
        }
        phase = .ended
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reset() }
        }
    }

    private func reset() {
        showsReplica = false
        phase = .idle
        audio.stopKeepAlive()
        if isArmed { audio.startKeepAlive() }
    }

    // MARK: CallKit callbacks

    private func callKitAnswered() {
        phaseTimer?.invalidate()
        phase = .connected(Date())
        audio.configureForCallKit()
    }

    private func callKitEnded() {
        guard usingCallKit else { return }
        usingCallKit = false
        phaseTimer?.invalidate()
        audio.endCall(restoreKeepAlive: false)
        phase = .idle
        audio.stopKeepAlive()
        if isArmed { audio.startKeepAlive() }
    }

    // MARK: Background helpers

    private func cancelTimers() {
        fireTimer?.invalidate()
        fireTimer = nil
        phaseTimer?.invalidate()
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FakeCallDelay") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// When the phone is locked the replica cannot draw over the lock screen, so a
    /// banner appears instead, which is also how WeChat rings on phones in mainland China.
    private func postCallNotification() {
        let content = UNMutableNotificationContent()
        switch request.style {
        case .wechat:
            content.title = "微信"
            content.body = "\(settings.wechatName)邀请你进行\(settings.wechatVideo ? "视频" : "语音")通话"
        case .iphone:
            content.title = settings.iphoneTitle
            content.body = settings.iphoneLanguage == .english ? "Incoming call" : "来电"
        }
        // The ringtone already plays through the kept-alive audio session when armed.
        if !isArmed {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(
                request.style == .iphone ? "ring_iphone.wav" : "ring_wechat.wav"))
        }
        let note = UNNotificationRequest(identifier: "fakecall", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(note)
    }
}
