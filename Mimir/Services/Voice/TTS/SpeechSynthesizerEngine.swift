import Foundation
import AVFoundation

/// 语音合成引擎的统一接口。
@MainActor
protocol SpeechSynthesisEngine: AnyObject {
    var isSpeaking: Bool { get }
    /// 当前朗读进度（0...1），用于语音球的波形动画。
    var onLevelUpdate: ((Double) -> Void)? { get set }
    var onFinish: (() -> Void)? { get set }

    func prepare() throws
    func speak(_ text: String, rate: Double)
    func stop()
}

/// 系统合成回退：当内置模型不可用时，用 AVSpeechSynthesizer 逐句朗读。
@MainActor
final class SystemSpeechEngine: NSObject, SpeechSynthesisEngine, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private var levelTimer: Timer?

    var onLevelUpdate: ((Double) -> Void)?
    var onFinish: (() -> Void)?
    /// 「音色」里选定的系统语音；nil 表示跟随系统默认中文语音。
    var preferredVoiceIdentifier: String?

    var isSpeaking: Bool { synthesizer.isSpeaking }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func prepare() throws {
        // 系统合成器无需额外准备，保证音频会话已激活即可。
    }

    func speak(_ text: String, rate: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.preferredVoice(identifier: preferredVoiceIdentifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(min(max(rate, 0.5), 1.8))
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.02
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        stopLevelTimer()
        onLevelUpdate?(0)
    }

    /// 用户选过就用用户选的，否则优先中文语音。
    private static func preferredVoice(identifier: String?) -> AVSpeechSynthesisVoice? {
        if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        if let chinese = AVSpeechSynthesisVoice(language: "zh-CN") { return chinese }
        return AVSpeechSynthesisVoice(language: Locale.current.identifier)
    }

    private func startLevelTimer() {
        stopLevelTimer()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // 系统合成器不暴露实时音频电平，这里给出平滑的呼吸感波形。
                self.onLevelUpdate?(Double.random(in: 0.25...0.85))
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.startLevelTimer()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // 队列里还有内容时不触发结束回调。
            guard !self.synthesizer.isSpeaking else { return }
            self.stopLevelTimer()
            self.onLevelUpdate?(0)
            self.onFinish?()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.stopLevelTimer()
            self.onLevelUpdate?(0)
        }
    }
}
