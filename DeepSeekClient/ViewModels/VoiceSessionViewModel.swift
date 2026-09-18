import Foundation
import Observation
import SwiftData
import AVFoundation
import UIKit

/// 语音会话状态机：端侧识别 → 云端推理 → 端侧合成，支持随时打断。
@MainActor
@Observable
final class VoiceSessionViewModel {

    // MARK: - 可观察状态

    var state: VoiceSessionState = .idle
    var inputLevel: Double = 0
    var outputLevel: Double = 0
    var lines: [VoiceTranscriptLine] = []
    var partialText: String = ""
    var unavailable: VoiceUnavailableReason?
    var isPreparing: Bool = false
    var infoText: String?
    var usesBuiltInVoice: Bool = false

    // MARK: - 依赖

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private var conversation: Conversation?
    @ObservationIgnored private var audioEngine: VoiceAudioEngine?
    @ObservationIgnored private var transcriber: SpeechTranscriber?
    @ObservationIgnored private var ttsEngine: (any SpeechSynthesisEngine)?
    @ObservationIgnored private var chunker = SentenceChunker()
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSpeech: [String] = []
    @ObservationIgnored private var isSpeakingQueue = false
    @ObservationIgnored private var currentAssistantText = ""
    @ObservationIgnored private var didHandleUserTurn = false

    init(settings: AppSettings, modelContext: ModelContext) {
        self.settings = settings
        self.modelContext = modelContext
    }

    var isActive: Bool {
        state.usesMicrophone || state == .thinking || state == .speaking || state == .transcribing
    }

    // MARK: - 生命周期

    func start(conversation: Conversation?) async {
        guard !isActive, !isPreparing else { return }
        self.conversation = conversation
        unavailable = nil
        infoText = nil
        isPreparing = true
        defer { isPreparing = false }

        guard settings.hasUsableCredential else {
            unavailable = .offline
            state = .unavailable
            return
        }

        let micGranted = await AudioSessionManager.shared.microphonePermission()
        guard micGranted else {
            unavailable = .missingMicrophonePermission
            state = .unavailable
            return
        }

        let speechGranted = await AudioSessionManager.shared.speechPermission()
        guard speechGranted else {
            unavailable = .missingSpeechPermission
            state = .unavailable
            return
        }

        do {
            try AudioSessionManager.shared.activate()
        } catch {
            unavailable = .audioSessionFailure(error.localizedDescription)
            state = .unavailable
            return
        }

        AudioSessionManager.shared.onInterruption = { [weak self] began in
            guard let self, began else { return }
            self.stopAll()
            self.state = .idle
            self.infoText = "音频被其他应用占用，已暂停。"
        }

        prepareSynthesisEngine()
        startCapture()
    }

    func stopAll() {
        streamTask?.cancel()
        streamTask = nil
        ttsEngine?.stop()
        pendingSpeech.removeAll()
        isSpeakingQueue = false
        audioEngine?.stop()
        audioEngine = nil
        transcriber?.cancel()
        transcriber = nil
        AudioSessionManager.shared.deactivate()
        inputLevel = 0
        outputLevel = 0
        partialText = ""
    }

    func end() {
        stopAll()
        state = .idle
    }

    // MARK: - 采集与识别

    private func startCapture() {
        let engine = VoiceAudioEngine(preferences: settings.voice)

        let transcriber = SpeechTranscriber(locale: Locale(identifier: "zh-CN"))
        transcriber.onUpdate = { [weak self] update in
            guard let self else { return }
            self.partialText = update.text
            if update.isFinal, !update.text.isEmpty {
                self.completeUserTurn(with: update.text)
            }
        }
        transcriber.onError = { [weak self] error in
            guard let self else { return }
            self.infoText = error.localizedDescription
        }

        do {
            try transcriber.start(allowCloudFallback: settings.voice.allowsCloudSTTFallback)
        } catch {
            unavailable = .modelLoadFailure(error.localizedDescription)
            state = .unavailable
            stopAll()
            return
        }

        engine.onAudioBuffer = { buffer, _ in
            transcriber.append(buffer)
        }

        engine.onUpdate = { [weak self] update in
            guard let self else { return }
            self.inputLevel = update.level

            if update.speechStarted {
                // 用户开口说话时立刻打断正在播放的回答。
                if self.state == .speaking, self.settings.voice.allowsBargeIn {
                    self.interrupt()
                } else if self.state == .listening {
                    self.transcriber?.cancel()
                    try? self.transcriber?.start(allowCloudFallback: self.settings.voice.allowsCloudSTTFallback)
                    self.didHandleUserTurn = false
                }
            }

            if update.speechEnded {
                self.handleSpeechEnded()
            }
        }

        do {
            try engine.start()
        } catch {
            unavailable = .audioSessionFailure(error.localizedDescription)
            state = .unavailable
            transcriber.cancel()
            return
        }

        audioEngine = engine
        self.transcriber = transcriber
        state = .listening
    }

    private func handleSpeechEnded() {
        guard state == .listening || state == .transcribing else { return }
        state = .transcribing
        audioEngine?.resetSpeechTracking()
        transcriber?.finishAudio()

        // 识别器通常会在结束录音后很快给出最终结果；
        // 超时未回调就用当前的部分结果兜底，避免卡在“识别中”。
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard let self, self.state == .transcribing else { return }
            let fallback = self.transcriber?.transcript ?? self.partialText
            if fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.state = .listening
            } else {
                self.completeUserTurn(with: fallback)
            }
        }
    }

    private func completeUserTurn(with text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .listening
            return
        }
        guard state != .thinking, state != .speaking else { return }

        partialText = ""
        lines.append(VoiceTranscriptLine(isUser: true, text: trimmed, isFinal: true))
        persistUserMessage(trimmed)
        requestResponse(for: trimmed)
    }

    // MARK: - 推理

    private func requestResponse(for userText: String) {
        state = .thinking
        chunker.reset()
        currentAssistantText = ""
        pendingSpeech.removeAll()
        isSpeakingQueue = false

        let credential = settings.resolvedCredential
        var parameters = settings.parameters.applying(conversation?.thinkingMode ?? .thinking)
        parameters.streamsResponse = true
        if let modelID = conversation?.modelID, !modelID.isEmpty {
            parameters.modelID = modelID
        }

        let history = conversationHistory()
        let client = LLMClientFactory.make(for: credential)

        streamTask = Task { [weak self] in
            var accumulated = ""
            do {
                let stream = client.streamChat(
                    messages: history,
                    parameters: parameters,
                    credential: credential,
                    tools: []
                )
                for try await event in stream {
                    if Task.isCancelled { break }
                    guard case .textDelta(let chunk) = event else { continue }
                    accumulated += chunk
                    self?.consumeAssistantChunk(chunk)
                }
            } catch {
                self?.infoText = (error as? LLMError)?.errorDescription ?? error.localizedDescription
            }

            guard let self else { return }
            self.finishAssistantTurn(with: accumulated)
        }
    }

    private func consumeAssistantChunk(_ chunk: String) {
        currentAssistantText += chunk

        // 助手文本增量地写进最后一条助手转写行。
        if let index = lines.lastIndex(where: { !$0.isUser }) {
            lines[index].text = currentAssistantText
            lines[index].isFinal = false
        } else {
            lines.append(VoiceTranscriptLine(isUser: false, text: currentAssistantText, isFinal: false))
        }

        let sentences = chunker.append(chunk)
        guard !sentences.isEmpty else { return }
        enqueueSpeech(sentences)
    }

    private func finishAssistantTurn(with text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = chunker.flush()
        if !remainder.isEmpty { enqueueSpeech(remainder) }

        if !trimmed.isEmpty {
            if let index = lines.lastIndex(where: { !$0.isUser }) {
                lines[index].text = trimmed
                lines[index].isFinal = true
            } else {
                lines.append(VoiceTranscriptLine(isUser: false, text: trimmed, isFinal: true))
            }
            persistAssistantMessage(trimmed)
        }

        streamTask = nil

        // 没有可播报内容时直接回到聆听。
        if pendingSpeech.isEmpty && !(ttsEngine?.isSpeaking ?? false) {
            state = .listening
        }
    }

    // MARK: - 合成与播放

    private func prepareSynthesisEngine() {
        let engine = SystemSpeechEngine()
        engine.onLevelUpdate = { [weak self] level in
            self?.outputLevel = level
        }
        engine.onFinish = { [weak self] in
            self?.handleSpeechQueueDrained()
        }
        try? engine.prepare()
        ttsEngine = engine
        usesBuiltInVoice = false
    }

    private func enqueueSpeech(_ sentences: [String]) {
        pendingSpeech.append(contentsOf: sentences)
        drainSpeechQueueIfNeeded()
    }

    private func drainSpeechQueueIfNeeded() {
        guard !isSpeakingQueue, !pendingSpeech.isEmpty else { return }
        isSpeakingQueue = true
        speakNext()
    }

    private func speakNext() {
        guard let sentence = pendingSpeech.first else {
            isSpeakingQueue = false
            handleSpeechQueueDrained()
            return
        }
        pendingSpeech.removeFirst()
        state = .speaking
        ttsEngine?.speak(sentence, rate: settings.voice.speechRate)
    }

    private func handleSpeechQueueDrained() {
        if pendingSpeech.isEmpty {
            isSpeakingQueue = false
            outputLevel = 0
            if state == .speaking {
                state = .listening
                audioEngine?.resetSpeechTracking()
                restartRecognitionIfNeeded()
            }
        } else {
            speakNext()
        }
    }

    /// 播放结束后重新开始一轮识别，保证可以连续对话。
    private func restartRecognitionIfNeeded() {
        guard let transcriber else { return }
        transcriber.cancel()
        try? transcriber.start(allowCloudFallback: settings.voice.allowsCloudSTTFallback)
        didHandleUserTurn = false
    }

    // MARK: - 打断

    func interrupt() {
        guard state == .speaking || state == .thinking else { return }
        streamTask?.cancel()
        streamTask = nil
        ttsEngine?.stop()
        pendingSpeech.removeAll()
        isSpeakingQueue = false
        chunker.reset()
        outputLevel = 0
        if state == .thinking {
            lines.append(VoiceTranscriptLine(isUser: false, text: currentAssistantText, isFinal: true))
            persistAssistantMessage(currentAssistantText, interrupted: true)
        }
        state = .interrupted
        Haptics.notify(.warning)
        audioEngine?.resetSpeechTracking()
        restartRecognitionIfNeeded()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard let self, self.state == .interrupted else { return }
            self.state = .listening
        }
    }

    /// 手动停止聆听 / 继续聆听。
    func toggleListening() {
        switch state {
        case .listening:
            state = .idle
            audioEngine?.stop()
        case .idle, .interrupted:
            if audioEngine == nil {
                startCapture()
            } else {
                try? audioEngine?.start()
                restartRecognitionIfNeeded()
                state = .listening
            }
        default:
            interrupt()
        }
    }

    // MARK: - 对话历史

    private func conversationHistory() -> [LLMChatMessage] {
        var messages: [LLMChatMessage] = []
        let system = settings.parameters.systemPrompt
        if !system.isEmpty {
            messages.append(LLMChatMessage(role: .system, text: system + "\n\n当前的对话通过语音进行，请用适合朗读的口语化短句回答，避免列表和代码块。"))
        }

        if let conversation {
            for message in conversation.orderedMessages.suffix(12) {
                switch message.role {
                case .user: messages.append(LLMChatMessage(role: .user, text: message.text))
                case .assistant:
                    if !message.text.isEmpty {
                        messages.append(LLMChatMessage(role: .assistant, text: message.text))
                    }
                default: break
                }
            }
        }

        if let lastUser = lines.last(where: { $0.isUser }) {
            if messages.last?.text != lastUser.text {
                messages.append(LLMChatMessage(role: .user, text: lastUser.text))
            }
        }
        return messages
    }

    // MARK: - 落盘

    private func persistUserMessage(_ text: String) {
        guard let conversation else { return }
        let message = ChatMessage(
            role: .user,
            text: text,
            orderIndex: conversation.nextOrderIndex,
            thinkingMode: conversation.thinkingMode
        )
        modelContext.insert(message)
        message.conversation = conversation
        conversation.updatedAt = Date()
        conversation.regenerateTitleIfNeeded()
        try? modelContext.save()
    }

    private func persistAssistantMessage(_ text: String, interrupted: Bool = false) {
        guard let conversation, !text.isEmpty else { return }
        let message = ChatMessage(
            role: .assistant,
            text: text,
            orderIndex: conversation.nextOrderIndex,
            thinkingMode: conversation.thinkingMode
        )
        message.isInterrupted = interrupted
        modelContext.insert(message)
        message.conversation = conversation
        conversation.updatedAt = Date()
        try? modelContext.save()

        if settings.memoryEnabled && settings.backgroundMemoryReview {
            Task { [weak self] in
                guard let self else { return }
                _ = await MemoryExtractor.review(
                    conversation: conversation,
                    context: self.modelContext,
                    store: MemoryStore.shared
                )
            }
        }
    }
}
