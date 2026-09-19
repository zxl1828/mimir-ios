import Foundation

/// 语音会话状态机。
enum VoiceSessionState: String, Codable, Sendable {
    case idle
    case listening
    case transcribing
    case thinking
    case speaking
    case interrupted
    case unavailable

    var title: String {
        switch self {
        case .idle: return "准备就绪"
        case .listening: return "正在聆听"
        case .transcribing: return "识别中"
        case .thinking: return "思考中"
        case .speaking: return "正在回答"
        case .interrupted: return "已打断"
        case .unavailable: return "不可用"
        }
    }

    var usesMicrophone: Bool {
        switch self {
        case .listening, .transcribing, .interrupted: return true
        default: return false
        }
    }
}

/// 语音模式下的一条转写行（用户 / 助手）。
struct VoiceTranscriptLine: Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var isUser: Bool
    var text: String
    var isFinal: Bool
    var createdAt: Date = Date()
}

/// 语音相关设置。
enum VoiceSynthesisPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 中文用系统合成，英文用内置模型。
    case automatic
    /// 尽量使用内置模型。
    case builtIn
    /// 始终使用系统合成。
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "自动"
        case .builtIn: return "内置模型优先"
        case .system: return "系统语音"
        }
    }

    var detail: String {
        switch self {
        case .automatic: return "英文用内置模型，中文用系统语音，兼顾自然度和中文质量"
        case .builtIn: return "尽可能使用随包内置的语音模型"
        case .system: return "始终使用系统语音合成，体积占用最小"
        }
    }
}

struct VoicePreferences: Codable, Sendable, Equatable {
    /// TTS 引擎：内置 Kokoro 优先，失败回退系统合成。
    var prefersBuiltInTTS: Bool = true
    /// 合成引擎偏好（新增字段，旧数据缺失时为 nil 并按自动处理）。
    var synthesisPreference: VoiceSynthesisPreference?
    var voiceIdentifier: String = "af_heart"
    /// 用户显式选定的系统语音（AVSpeechSynthesisVoice.identifier）；nil = 跟随系统默认中文语音。
    var systemVoiceIdentifier: String?
    var speechRate: Double = 1.0
    /// VAD 参数（能量阈值）。
    var speechThreshold: Double = 0.02
    var silenceThreshold: Double = 0.01
    var silenceDuration: Double = 1.5
    /// 是否允许云端 STT 回退（默认关闭，且必须显式授权）。
    var allowsCloudSTTFallback: Bool = false
    var allowsBargeIn: Bool = true

    var resolvedSynthesisPreference: VoiceSynthesisPreference {
        synthesisPreference ?? .automatic
    }
}

/// 语音不可用的原因，用于给出可操作的提示。
enum VoiceUnavailableReason: Sendable, Equatable {
    case missingMicrophonePermission
    case missingSpeechPermission
    case offline
    case audioSessionFailure(String)
    case modelLoadFailure(String)

    var title: String {
        switch self {
        case .missingMicrophonePermission: return "还没有麦克风权限"
        case .missingSpeechPermission: return "还没有语音识别权限"
        case .offline: return "当前网络不可用"
        case .audioSessionFailure: return "音频设备被占用"
        case .modelLoadFailure: return "语音模型加载失败"
        }
    }

    var detail: String {
        switch self {
        case .missingMicrophonePermission:
            return "语音对话需要麦克风。音频只在本机处理，不会上传。"
        case .missingSpeechPermission:
            return "需要语音识别权限才能把你的话转成文字，识别在本机完成。"
        case .offline:
            return "语音模式需要连接云端模型，请先恢复网络后再试。"
        case .audioSessionFailure(let message):
            return message
        case .modelLoadFailure(let message):
            return message
        }
    }

    var canOpenSettings: Bool {
        switch self {
        case .missingMicrophonePermission, .missingSpeechPermission: return true
        default: return false
        }
    }
}
