import AVFoundation
import Foundation

/// 内置 Kokoro 音色目录（英文朗读）。
enum VoiceToneCatalog {

    struct BuiltInTone: Identifiable, Hashable {
        var id: String          // Kokoro 的 voice 名，存进 VoicePreferences.voiceIdentifier
        var title: String
        var detail: String
    }

    static let builtIn: [BuiltInTone] = [
        BuiltInTone(id: "af_heart", title: "Heart · 温柔女声", detail: "美式英语，语气柔和，默认音色"),
        BuiltInTone(id: "af_bella", title: "Bella · 明亮女声", detail: "美式英语，明亮清晰，适合朗读"),
        BuiltInTone(id: "af_nicole", title: "Nicole · 轻快女声", detail: "美式英语，语速偏快，适合播报"),
        BuiltInTone(id: "am_michael", title: "Michael · 沉稳男声", detail: "美式英语，低沉稳重"),
        BuiltInTone(id: "bf_emma", title: "Emma · 英式女声", detail: "英式英语，优雅清晰")
    ]

    static func builtInTitle(for identifier: String) -> String {
        builtIn.first { $0.id == identifier }?.title ?? identifier
    }

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
    static func summary(voiceIdentifier: String, systemVoiceIdentifier: String?) -> String {
        if let systemVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: systemVoiceIdentifier) {
            return "系统 · \(voice.name)"
        }
        switch voiceIdentifier {
        case "system": return "系统语音（自动）"
        default: return "内置 · \(builtInTitle(for: voiceIdentifier))"
        }
    }
}
