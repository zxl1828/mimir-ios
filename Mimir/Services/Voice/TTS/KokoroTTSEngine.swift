import Foundation
import AVFoundation
import KokoroCoreML

/// 内置语音合成引擎（Kokoro-82M，CoreML）。
///
/// 模型随 App 一起打包在 Bundle 里，用户无需额外下载。
/// 模型缺失或设备不兼容时，调用方会回退到系统合成。
@MainActor
final class KokoroTTSEngine: SpeechSynthesisEngine {

    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private var kokoro: KokoroEngine?
    private var isGraphReady = false
    private var scheduledBuffers = 0
    private var streamFinished = true
    private var streamTask: Task<Void, Never>?
    private var levelTimer: Timer?
    private var latestLevel: Double = 0

    var onLevelUpdate: ((Double) -> Void)?
    var onFinish: (() -> Void)?
    /// 「音色」里选定的内置音色名；nil 或不可用时回落到默认优先级。
    var preferredVoiceName: String?
    private(set) var loadFailureText: String?

    var isSpeaking: Bool {
        player.isPlaying && !(streamFinished && scheduledBuffers == 0)
    }

    /// 模型是否已经加载完成并可以合成。
    var isReady: Bool {
        kokoro?.isReady ?? false
    }

    /// 模型是否随包提供。
    static var isBundled: Bool {
        bundledModelDirectory() != nil
    }

    // MARK: - 模型位置

    /// App 内置模型的目录（`Models/kokoro`）。
    static func bundledModelDirectory() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let candidates = [
            resources.appendingPathComponent("Models/kokoro", isDirectory: true),
            resources.appendingPathComponent("kokoro", isDirectory: true),
            resources.appendingPathComponent("Models", isDirectory: true)
        ]
        for candidate in candidates {
            let frontend = candidate.appendingPathComponent("kokoro_frontend.mlmodelc").path
            let voices = candidate.appendingPathComponent("voices").path
            if FileManager.default.fileExists(atPath: frontend),
               FileManager.default.fileExists(atPath: voices) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - 准备

    func prepare() throws {
        guard kokoro == nil else { return }
        guard let directory = Self.bundledModelDirectory() else {
            throw KokoroEngineError.modelsMissing
        }

        // 刻意不在这里启动音频图：语音模式打开时输入引擎刚起来，
        // 同时启动两个 AVAudioEngine 很容易崩。首次朗读时再建图。

        let forceCPU = Self.isSimulator
        Task { [weak self] in
            let result = await Self.loadModel(directory: directory, forceCPU: forceCPU)
            guard let self else { return }
            switch result {
            case .success(let engine):
                self.kokoro = engine
            case .failure(let error):
                self.loadFailureText = error.localizedDescription
            }
        }
    }

    /// 在后台线程完成模型加载，避免阻塞主线程首帧。
    private nonisolated static func loadModel(
        directory: URL,
        forceCPU: Bool
    ) async -> Result<KokoroEngine, Error> {
        await Task.detached(priority: .utility) {
            do {
                return .success(try KokoroEngine(modelDirectory: directory, forceCPU: forceCPU))
            } catch {
                return .failure(error)
            }
        }.value
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private func setupAudioGraph() {
        guard !isGraphReady else { return }
        let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(KokoroEngine.sampleRate),
            channels: 1
        )
        audioEngine.attach(player)
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
        audioEngine.prepare()
        try? audioEngine.start()
        isGraphReady = true
    }

    // MARK: - 合成

    func speak(_ text: String, rate: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let kokoro else { return }

        setupAudioGraph()
        if !audioEngine.isRunning { try? audioEngine.start() }

        let voice = preferredVoice(for: kokoro)
        let speed = Float(min(max(rate, 0.5), 2.0))

        guard let stream = try? kokoro.speak(
            trimmed,
            voice: voice,
            speed: speed,
            paceToRealtime: true
        ) else {
            loadFailureText = "内置模型合成失败，已回退。"
            onFinish?()
            return
        }

        streamFinished = false
        if !player.isPlaying { player.play() }
        startLevelTimer()

        streamTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .audio(let buffer):
                    self.schedule(buffer)
                case .chunkFailed(let error):
                    self.loadFailureText = error.localizedDescription
                }
            }
            guard let self else { return }
            self.streamFinished = true
            self.checkCompletion()
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        player.stop()
        scheduledBuffers = 0
        streamFinished = true
        stopLevelTimer()
        onLevelUpdate?(0)
    }

    // MARK: - 播放队列

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        scheduledBuffers += 1
        latestLevel = Self.level(of: buffer)
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.scheduledBuffers = max(self.scheduledBuffers - 1, 0)
                self.checkCompletion()
            }
        }
    }

    private func checkCompletion() {
        guard streamFinished, scheduledBuffers == 0 else { return }
        stopLevelTimer()
        onLevelUpdate?(0)
        onFinish?()
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?.pointee else { return 0.4 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0.4 }
        var sum: Float = 0
        for index in stride(from: 0, to: count, by: 8) {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(max(count / 8, 1)))
        return min(max(Double(rms) * 6, 0.12), 1.0)
    }

    private func startLevelTimer() {
        stopLevelTimer()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let jitter = Double.random(in: 0.82...1.18)
                self.onLevelUpdate?(min(max(self.latestLevel * jitter, 0.08), 1.0))
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func preferredVoice(for engine: KokoroEngine) -> String {
        if let preferredVoiceName, engine.availableVoices.contains(preferredVoiceName) {
            return preferredVoiceName
        }
        let preferences = ["af_heart", "af_bella", "af_nicole", "am_michael", "bf_emma"]
        for candidate in preferences where engine.availableVoices.contains(candidate) {
            return candidate
        }
        return engine.availableVoices.first ?? "af_heart"
    }
}

enum KokoroEngineError: LocalizedError {
    case modelsMissing

    var errorDescription: String? {
        switch self {
        case .modelsMissing:
            return "App 里没有找到内置语音模型，已改用系统语音合成。"
        }
    }
}
