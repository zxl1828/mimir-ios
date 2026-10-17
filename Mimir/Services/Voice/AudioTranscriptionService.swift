import Foundation
import Observation
import AVFoundation
import Speech

/// 专用于代码工坊与交互视窗的端侧语音转写服务（Swift 6 并发安全）。
@Observable
@MainActor
public final class AudioTranscriptionService: NSObject, Sendable {
    public static let shared = AudioTranscriptionService()

    public private(set) var isRecording: Bool = false
    public private(set) var transcript: String = ""
    public private(set) var audioLevel: Float = 0.0
    public private(set) var errorMessage: String?

    @ObservationIgnored
    private var audioEngine: AVAudioEngine?
    @ObservationIgnored
    private var speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored
    private var recognitionTask: SFSpeechRecognitionTask?

    public override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    }

    /// 开始录制并实时流式转写用户语音指令
    public func startRecording() async throws {
        guard !isRecording else { return }

        errorMessage = nil
        transcript = ""

        // 麦克风与语音识别授权检查
        let micAllowed = await AudioSessionManager.shared.microphonePermission()
        guard micAllowed else {
            errorMessage = "未获得麦克风使用权限"
            throw NSError(domain: "AudioTranscriptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "未获得麦克风权限"])
        }

        let speechAllowed = await AudioSessionManager.shared.speechPermission()
        guard speechAllowed else {
            errorMessage = "未获得语音识别权限"
            throw NSError(domain: "AudioTranscriptionService", code: 2, userInfo: [NSLocalizedDescriptionKey: "未获得语音识别权限"])
        }

        // 配置 AVAudioSession
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        recognitionRequest = request
        audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            // 提取实时音量包络
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames { sum += abs(channelData[i]) }
            let avg = sum / Float(max(frames, 1))

            Task { @MainActor [weak self] in
                self?.audioLevel = min(max(avg * 4.0, 0.05), 1.0)
            }
        }

        engine.prepare()
        try engine.start()

        isRecording = true

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil {
                    self.stopRecording()
                }
            }
        }
    }

    /// 停止录制并返回已转写的完整文本
    @discardableResult
    public func stopRecording() -> String {
        isRecording = false
        audioLevel = 0.0

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 取消并重置录音状态
    public func cancel() {
        _ = stopRecording()
        transcript = ""
    }
}
