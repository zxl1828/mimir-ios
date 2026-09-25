import AVFoundation
import Foundation

/// 系统语音音色目录。
///
/// 以前这里还列过随包内置的 Kokoro 英文音色，那个模型占 78MB，
/// 已经整个移除了；现在语音朗读统一交给系统合成（AVSpeechSynthesizer）。
enum VoiceToneCatalog {

    /// 系统音色的分组：中文优先，其余按语言排列。
    static func systemVoices() -> (chinese: [AVSpeechSynthesisVoice], others: [AVSpeechSynthesisVoice]) {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let chinese = all
            .filter { $0.language.hasPrefix("zh") }
            .sorted { $0.name < $1.name }
        let others = all
            .filter { !$0.language.hasPrefix("zh") }
            .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
        return (chinese, others)
    }

    static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String? {
        switch quality {
        case .premium: return "优质"
        case .enhanced: return "增强"
        default: return nil
        }
    }

    /// 设置页 / 语音页上显示的当前音色摘要。
    static func summary(systemVoiceIdentifier: String?) -> String {
        guard let systemVoiceIdentifier,
              let voice = AVSpeechSynthesisVoice(identifier: systemVoiceIdentifier) else {
            return "系统默认语音"
        }
        return "系统 · \(voice.name)"
    }
}
