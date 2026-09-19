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
    ///
    /// 实测（iPhone 17 Pro / iOS 27，侧载安装）：无条件调用 `requestAuthorization`
    /// 会在「麦克风授权通过之后」把 App 直接干掉。因此这里三道保险：
    /// ① 已授权直接放行，已拒绝 / 受限直接返回 false，只有「未决定」才真正弹窗；
    /// ② 调用本身用 ObjC 的 @try/@catch 包住（`ObjCExceptionCatcher`）；
    /// ③ 弹窗 20 秒没有回调就当作未授权，不阻塞语音界面。
    func speechPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        AppDiagnostics.shared.log("voice: speech status = \(Self.describe(status))")
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            break
        @unknown default:
            return false
        }

        let box = PermissionBox()
        do {
            try ObjCExceptionCatcher.perform {
                SFSpeechRecognizer.requestAuthorization { status in
                    box.finish(status == .authorized)
                }
            }
        } catch {
            AppDiagnostics.shared.log("voice: speech request threw \(error.localizedDescription)")
            return false
        }

        let granted = await box.value(timeout: .seconds(20))
        AppDiagnostics.shared.log("voice: speech prompt = \(granted)")
        return granted
    }

    private static func describe(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
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

/// 授权回调可能来自任意线程：一次性投递 + 超时兜底，避免永久等待。
private final class PermissionBox: @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var stored: Bool?

    func finish(_ granted: Bool) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: granted)
        } else {
            stored = granted
            lock.unlock()
        }
    }

    func value(timeout: Duration) async -> Bool {
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.finish(false)
        }
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            lock.lock()
            if let stored {
                lock.unlock()
                continuation.resume(returning: stored)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
        timeoutTask.cancel()
        return granted
    }
}
