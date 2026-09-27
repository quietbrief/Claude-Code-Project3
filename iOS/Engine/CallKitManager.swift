import AVFoundation
import CallKit
import UIKit

/// Shows a genuine system incoming-call screen through CallKit. This is the only way
/// to ring over the lock screen and on a paired Apple Watch, and in this mode the
/// phone plays the user's real system ringtone.
@MainActor
final class CallKitManager: NSObject {
    static let shared = CallKitManager()

    private var provider: CXProvider?
    private let controller = CXCallController()
    private var providerIncludesRecents: Bool?
    private(set) var activeCall: UUID?

    var onAnswered: (() -> Void)?
    var onEnded: (() -> Void)?
    var onAudioActivated: (() -> Void)?

    private func makeProvider(includeRecents: Bool) -> CXProvider {
        if let provider, providerIncludesRecents == includeRecents { return provider }
        provider?.invalidate()
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber, .generic]
        configuration.includesCallsInRecents = includeRecents
        // nil keeps the ringtone the user picked in Settings > Sounds & Haptics.
        configuration.ringtoneSound = nil
        if let glyph = UIImage(systemName: "phone.fill")?.pngData() {
            configuration.iconTemplateImageData = glyph
        }
        let newProvider = CXProvider(configuration: configuration)
        newProvider.setDelegate(self, queue: nil)
        provider = newProvider
        providerIncludesRecents = includeRecents
        return newProvider
    }

    /// Reports a fake incoming call. Calls `completion` with an error when CallKit is
    /// unavailable, for example on devices whose region is set to mainland China.
    func reportIncoming(name: String, number: String, includeRecents: Bool,
                        completion: @escaping (Error?) -> Void) {
        let provider = makeProvider(includeRecents: includeRecents)
        let uuid = UUID()
        let update = CXCallUpdate()
        let digits = number.filter { $0.isNumber || $0 == "+" }
        update.remoteHandle = CXHandle(type: digits.isEmpty ? .generic : .phoneNumber,
                                       value: digits.isEmpty ? name : digits)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        update.localizedCallerName = trimmed.isEmpty ? nil : trimmed
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = true

        activeCall = uuid
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            Task { @MainActor in
                if error != nil { self.activeCall = nil }
                completion(error)
            }
        }
    }

    func endActiveCall() {
        guard let uuid = activeCall else { return }
        let transaction = CXTransaction(action: CXEndCallAction(call: uuid))
        controller.request(transaction) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                self?.provider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
                self?.activeCall = nil
                self?.onEnded?()
            }
        }
    }

    /// Lets the "caller" hang up, e.g. when the call rang out.
    func remoteHangUp(unanswered: Bool) {
        guard let uuid = activeCall else { return }
        provider?.reportCall(with: uuid, endedAt: Date(), reason: unanswered ? .unanswered : .remoteEnded)
        activeCall = nil
        onEnded?()
    }
}

extension CallKitManager: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in
            self.activeCall = nil
            self.onEnded?()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        action.fulfill()
        Task { @MainActor in self.onAnswered?() }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
        Task { @MainActor in
            self.activeCall = nil
            self.onEnded?()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Task { @MainActor in self.onAudioActivated?() }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}
