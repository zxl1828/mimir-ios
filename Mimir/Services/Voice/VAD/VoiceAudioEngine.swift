import Foundation
import AVFoundation
import Accelerate

/// 麦克风采集 + 基于能量的语音活动检测（VAD）。
///
/// 采集回调运行在音频实时线程上，因此这里刻意标记为 `@unchecked Sendable`：
/// 内部只做数值计算并立刻把结果投递到主线程，不持有任何 UI 状态。
final class VoiceAudioEngine: @unchecked Sendable {

    /// 一次电平更新。
    struct Update: Sendable {
        var level: Double
        var isSpeech: Bool
        /// 本帧刚刚检测到说话开始。
        var speechStarted: Bool
        /// 本帧刚刚判定一句话结束（静音达到阈值时长）。
        var speechEnded: Bool
    }

    private let engine = AVAudioEngine()
    private var isRunning = false

    private var speechThreshold: Float
    private var silenceThreshold: Float
    private let silenceDuration: TimeInterval

    private var lastSpeechAt: Date = Date()
    private var hasDetectedSpeech = false
    private var isInSpeech = false

    /// 电平回调（主线程）。
    var onUpdate: (@MainActor (Update) -> Void)?
    /// 原始音频回调（音频线程），用于送进语音识别器。
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?

    init(preferences: VoicePreferences) {
        self.speechThreshold = Float(preferences.speechThreshold)
        self.silenceThreshold = Float(preferences.silenceThreshold)
        self.silenceDuration = preferences.silenceDuration
    }

    func update(preferences: VoicePreferences) {
        speechThreshold = Float(preferences.speechThreshold)
        silenceThreshold = Float(preferences.silenceThreshold)
    }

    var format: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func start() throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let busFormat = input.outputFormat(forBus: 0)
        guard busFormat.sampleRate > 0, busFormat.channelCount > 0 else {
            throw VoiceAudioError.noInputDevice
        }

        hasDetectedSpeech = false
        isInSpeech = false
        lastSpeechAt = Date()

        // 上一次启动失败可能残留 tap，重复安装会直接崩，先清掉。
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: busFormat) { [weak self] buffer, time in
            guard let self else { return }
            self.process(buffer: buffer, time: time)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw VoiceAudioError.engineFailure(error.localizedDescription)
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    /// 让 VAD 重新开始一句话（打断后使用）。
    func resetSpeechTracking() {
        hasDetectedSpeech = false
        isInSpeech = false
        lastSpeechAt = Date()
    }

    // MARK: - 音频线程

    private func process(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        onAudioBuffer?(buffer, time)

        guard let channel = buffer.floatChannelData?.pointee else { return }
        let count = vDSP_Length(buffer.frameLength)
        guard count > 0 else { return }

        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, count)

        let now = Date()
        let isSpeechFrame = rms >= speechThreshold
        var started = false
        var ended = false

        if isSpeechFrame {
            if !isInSpeech {
                isInSpeech = true
                started = true
            }
            hasDetectedSpeech = true
            lastSpeechAt = now
        } else {
            if isInSpeech && rms < silenceThreshold {
                isInSpeech = false
            }
            if hasDetectedSpeech, now.timeIntervalSince(lastSpeechAt) >= silenceDuration {
                hasDetectedSpeech = false
                ended = true
            }
        }

        let normalized = min(max(Double(rms) / Double(max(speechThreshold, 0.0001)) * 0.5, 0), 1)
        let update = Update(
            level: normalized,
            isSpeech: isSpeechFrame,
            speechStarted: started,
            speechEnded: ended
        )

        Task { @MainActor [weak self] in
            self?.onUpdate?(update)
        }
    }
}

enum VoiceAudioError: LocalizedError {
    case noInputDevice
    case engineFailure(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "没有检测到可用的麦克风输入。"
        case .engineFailure(let message):
            return "音频引擎启动失败：\(message)"
        }
    }
}
