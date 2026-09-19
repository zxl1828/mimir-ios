import Foundation
import AVFoundation

/// 语音合成路由：按语言与用户偏好，在内置模型和系统合成之间选择。
///
/// 内置 Kokoro 模型使用英文音素引擎，因此中文内容交给系统合成，
/// 这样中文朗读质量和英文的自然度可以同时保住。
@MainActor
final class VoiceSynthesisRouter: SpeechSynthesisEngine {

    private let builtIn: KokoroTTSEngine
    private let system: SystemSpeechEngine
    private var preference: VoiceSynthesisPreference
    private var activeIsBuiltIn = false

    var onLevelUpdate: ((Double) -> Void)?
    var onFinish: (() -> Void)?
    /// 每次切换引擎时回调，用于在界面上显示当前使用的引擎。
    var onEngineChanged: ((Bool) -> Void)?
    /// 音色设置：内置音色名 + 显式选择的系统语音。
    var builtInVoiceName: String = "af_heart"
    var systemVoiceIdentifier: String?

    init(preference: VoiceSynthesisPreference) {
        self.preference = preference
        self.builtIn = KokoroTTSEngine()
        self.system = SystemSpeechEngine()
    }

    var isSpeaking: Bool {
        builtIn.isSpeaking || system.isSpeaking
    }

    var isBuiltInBundled: Bool { KokoroTTSEngine.isBundled }
    var isBuiltInReady: Bool { builtIn.isReady }
    var builtInFailure: String? { builtIn.loadFailureText }

    func update(preference: VoiceSynthesisPreference) {
        self.preference = preference
    }

    func prepare() throws {
        builtIn.preferredVoiceName = builtInVoiceName
        system.preferredVoiceIdentifier = systemVoiceIdentifier
        if KokoroTTSEngine.isBundled {
            try? builtIn.prepare()
        }
        try system.prepare()

        builtIn.onLevelUpdate = { [weak self] level in
            guard let self, self.activeIsBuiltIn else { return }
            self.onLevelUpdate?(level)
        }
        builtIn.onFinish = { [weak self] in
            guard let self, self.activeIsBuiltIn else { return }
            self.onFinish?()
        }
        system.onLevelUpdate = { [weak self] level in
            guard let self, !self.activeIsBuiltIn else { return }
            self.onLevelUpdate?(level)
        }
        system.onFinish = { [weak self] in
            guard let self, !self.activeIsBuiltIn else { return }
            self.onFinish?()
        }
    }

    func speak(_ text: String, rate: Double) {
        let useBuiltIn = shouldUseBuiltIn(for: text)
        activeIsBuiltIn = useBuiltIn
        onEngineChanged?(useBuiltIn)
        if useBuiltIn {
            builtIn.speak(text, rate: rate)
        } else {
            system.speak(text, rate: rate)
        }
    }

    func stop() {
        builtIn.stop()
        system.stop()
    }

    private func shouldUseBuiltIn(for text: String) -> Bool {
        guard KokoroTTSEngine.isBundled, builtIn.isReady else { return false }
        // 用户显式选了系统音色，就一律交给系统合成。
        if systemVoiceIdentifier != nil || builtInVoiceName == "system" { return false }
        switch preference {
        case .system:
            return false
        case .builtIn, .automatic:
            return Self.isLatinScript(text)
        }
    }

    /// 含中日韩字符时交给系统合成，避免英文音素引擎读中文。
    static func isLatinScript(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let isCJK = (0x4E00...0x9FFF).contains(value)
                || (0x3400...0x4DBF).contains(value)
                || (0x3040...0x30FF).contains(value)
                || (0xAC00...0xD7AF).contains(value)
                || (0xF900...0xFAFF).contains(value)
            if isCJK { return false }
        }
        return true
    }
}
