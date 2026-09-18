import Foundation
import AVFoundation
import Speech

/// 音频会话管理：同时播放与录音、处理中断与路由变化。
@MainActor
final class AudioSessionManager {

    static let shared = AudioSessionManager()

    /// 中断开始 / 结束（来电、其他 App 抢占麦克风）。
    var onInterruption: ((Bool) -> Void)?
    /// 输出路由变化（拔耳机、连蓝牙）。
    var onRouteChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var isActive = false

    private init() {}

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .duckOthers]
        )
        try session.setActive(true, options: [])
        isActive = true
        installObserversIfNeeded()
    }

    func deactivate() {
        guard isActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isActive = false
        removeObservers()
    }

    /// 是否已经授权麦克风（未决定时返回 nil 并触发请求）。
    func microphonePermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    /// 语音识别授权。
    func speechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - 通知

    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                Task { @MainActor in
                    self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.onRouteChange?()
                }
            }
        )
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt) {
        guard let typeRaw,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            onInterruption?(true)
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume) {
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            onInterruption?(false)
        @unknown default:
            break
        }
    }
}
