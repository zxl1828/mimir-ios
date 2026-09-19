import AVFoundation
import SwiftUI

/// 音色选择窗口：内置 Kokoro 音色 + 系统语音音色，点一行即可试听。
@MainActor
struct VoiceTonePickerView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var preview = TonePreviewer()
    @State private var previewingID: String?

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            List {
                Section {
                    ForEach(VoiceToneCatalog.builtIn) { tone in
                        row(
                            id: tone.id,
                            title: tone.title,
                            detail: tone.detail,
                            selected: settings.voice.voiceIdentifier == tone.id,
                            trailing: nil
                        ) {
                            settings.voice.voiceIdentifier = tone.id
                            settings.voice.systemVoiceIdentifier = nil
                            previewTone(id: tone.id, text: "Hello, I am Mimi. This is my built-in voice.")
                        }
                    }
                } header: {
                    Text("内置音色 · Kokoro（英文）")
                } footer: {
                    Text("内置模型随 App 打包，首次试听需要几秒加载；中文朗读会自动改用下面的系统音色。")
                }

                Section {
                    row(
                        id: "system-auto",
                        title: "自动（推荐）",
                        detail: "跟随系统默认中文语音",
                        selected: settings.voice.systemVoiceIdentifier == nil
                            && settings.voice.voiceIdentifier == "system",
                        trailing: nil
                    ) {
                        settings.voice.voiceIdentifier = "system"
                        settings.voice.systemVoiceIdentifier = nil
                        previewTone(id: "system-auto", text: "你好，我是米米，这是当前的系统音色。")
                    }

                    ForEach(systemVoices.chinese, id: \.identifier) { voice in
                        systemRow(voice)
                    }
                } header: {
                    Text("系统音色 · 中文")
                }

                if !systemVoices.others.isEmpty {
                    Section("系统音色 · 其他语言") {
                        ForEach(systemVoices.others.prefix(12), id: \.identifier) { voice in
                            systemRow(voice)
                        }
                    }
                }
            }
            .navigationTitle("音色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        preview.stop()
                        dismiss()
                    }
                }
            }
            .onDisappear { preview.stop() }
        }
    }

    private var systemVoices: (chinese: [AVSpeechSynthesisVoice], others: [AVSpeechSynthesisVoice]) {
        VoiceToneCatalog.systemVoices()
    }

    private func systemRow(_ voice: AVSpeechSynthesisVoice) -> some View {
        row(
            id: voice.identifier,
            title: voice.name,
            detail: [voice.language, VoiceToneCatalog.qualityLabel(voice.quality)]
                .compactMap { $0 }
                .joined(separator: " · "),
            selected: settings.voice.systemVoiceIdentifier == voice.identifier,
            trailing: previewingID == voice.identifier ? "正在试听" : nil
        ) {
            // 只有显式选过系统音色时，中文朗读才完全交给它；否则保持「内置优先、中文转系统」。
            settings.voice.systemVoiceIdentifier = voice.identifier
            previewTone(id: voice.identifier, text: "你好，我是米米，这是当前的音色。")
        }
    }

    private func row(
        id: String,
        title: String,
        detail: String,
        selected: Bool,
        trailing: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selectionChanged()
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: selected ? .semibold : .regular))
                        .foregroundStyle(AppColor.primaryText)
                    Text(detail)
                        .font(AppFont.hint)
                        .foregroundStyle(AppColor.secondaryText)
                }
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(AppFont.chipCompact)
                        .foregroundStyle(AppColor.secondaryText)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColor.brandIndigo)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func previewTone(id: String, text: String) {
        previewingID = id
        let isBuiltIn = VoiceToneCatalog.builtIn.contains { $0.id == id }
        preview.speak(
            text,
            builtInVoice: isBuiltIn ? id : nil,
            systemVoiceIdentifier: isBuiltIn ? nil : settings.voice.systemVoiceIdentifier
        ) { previewingID = nil }
    }
}

/// 试听器：系统音色用 AVSpeechSynthesizer，内置音色用 Kokoro（懒加载）。
@MainActor
@Observable
final class TonePreviewer {

    private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var kokoro: KokoroTTSEngine?

    func speak(
        _ text: String,
        builtInVoice: String?,
        systemVoiceIdentifier: String?,
        completion: @escaping () -> Void
    ) {
        if let builtInVoice {
            let engine: KokoroTTSEngine
            if let kokoro {
                engine = kokoro
            } else {
                let created = KokoroTTSEngine()
                try? created.prepare()
                created.preferredVoiceName = builtInVoice
                kokoro = created
                engine = created
            }
            engine.preferredVoiceName = builtInVoice
            engine.onFinish = completion
            engine.speak(text, rate: 1.0)
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        if let systemVoiceIdentifier {
            utterance.voice = AVSpeechSynthesisVoice(identifier: systemVoiceIdentifier)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            completion()
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        kokoro?.stop()
    }
}
