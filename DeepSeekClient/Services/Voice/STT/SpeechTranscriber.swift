import Foundation
import Speech
import AVFoundation

/// 端侧语音识别。
///
/// 使用系统 Speech 框架并强制 `requiresOnDeviceRecognition`，
/// 音频不离开设备；识别结果以增量回调的形式输出。
///
/// 采集回调来自音频线程，因此内部可变状态用锁保护，
/// 对外的回调统一跳回主线程。
final class SpeechTranscriber: @unchecked Sendable {

    struct Update: Sendable {
        var text: String
        var isFinal: Bool
    }

    private let lock = NSLock()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestTranscript = ""

    var onUpdate: (@MainActor (Update) -> Void)?
    var onError: (@MainActor (Error) -> Void)?
    let locale: Locale

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.locale = locale
    }

    /// 当前语言是否支持完全离线的端侧识别。
    var supportsOnDeviceRecognition: Bool {
        let recognizer = SFSpeechRecognizer(locale: locale)
        return recognizer?.supportsOnDeviceRecognition ?? false
    }

    func start(allowCloudFallback: Bool = false) throws {
        cancel()

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechTranscriberError.localeUnsupported(locale.identifier)
        }
        guard recognizer.isAvailable else {
            throw SpeechTranscriberError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else if !allowCloudFallback {
            throw SpeechTranscriberError.onDeviceUnavailable
        }

        request.addsPunctuation = true
        request.contextualStrings = Self.technicalVocabulary

        lock.lock()
        self.recognizer = recognizer
        self.request = request
        latestTranscript = ""
        lock.unlock()

        let recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                self.lock.lock()
                self.latestTranscript = text
                self.lock.unlock()
                Task { @MainActor in
                    self.onUpdate?(Update(text: text, isFinal: isFinal))
                }
            }
            if let error {
                let nsError = error as NSError
                // 收尾阶段的取消不算错误。
                if nsError.code != 216 && nsError.code != 301 {
                    Task { @MainActor in
                        self.onError?(error)
                    }
                }
            }
        }
        lock.lock()
        task = recognitionTask
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.append(buffer)
    }

    /// 结束当前这句话并等待最终结果。
    func finishAudio() {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.endAudio()
    }

    func cancel() {
        lock.lock()
        let task = self.task
        let request = self.request
        self.task = nil
        self.request = nil
        self.recognizer = nil
        lock.unlock()
        task?.cancel()
        request?.endAudio()
    }

    var transcript: String {
        lock.lock()
        defer { lock.unlock() }
        return latestTranscript
    }

    /// 提高代码术语与专有名词的识别率。
    private static let technicalVocabulary = [
        "SwiftUI", "CoreML", "SwiftData", "DeepSeek", "API", "token",
        "MCP", "GitHub", "Actions", "Xcode", "Swift", "iOS"
    ]
}

enum SpeechTranscriberError: LocalizedError {
    case localeUnsupported(String)
    case recognizerUnavailable
    case onDeviceUnavailable

    var errorDescription: String? {
        switch self {
        case .localeUnsupported(let locale):
            return "当前语言（\(locale)）暂不支持语音识别。"
        case .recognizerUnavailable:
            return "语音识别服务暂时不可用，请稍后再试。"
        case .onDeviceUnavailable:
            return "这台设备还不支持离线语音识别。可以在设置里开启云端识别回退，或先在系统里下载对应语言的听写键盘。"
        }
    }
}
