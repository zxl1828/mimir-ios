import AVFoundation
import SwiftUI

/// 音色选择窗口：列出系统语音音色，点一行即可试听。
@MainActor
struct VoiceTonePickerView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent

    @State private var preview = TonePreviewer()
    @State private var previewingID: String?

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            List {
                Section {
                    row(
                        id: "system-auto",
                        title: "自动（推荐）",
                        detail: "跟随系统默认中文语音",
                        selected: settings.voice.systemVoiceIdentifier == nil,
                        trailing: nil
                    ) {
                        settings.voice.systemVoiceIdentifier = nil
                        previewTone(id: "system-auto", text: "你好，我是米米，这是当前的系统音色。")
                    }

                    ForEach(systemVoices.chinese, id: \.identifier) { voice in
                        systemRow(voice)
                    }
                } header: {
                    Text("系统音色 · 中文")
                } footer: {
                    Text("朗读由系统语音合成完成；在 iOS 设置 → 辅助功能 → 语音内容里可以下载更多高质量中文语音。")
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
                        .foregroundStyle(AppUI.label)
                    Text(detail)
                        .font(AppUI.footnote)
                        .foregroundStyle(AppUI.label2)
                }
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(AppUI.caption)
                        .foregroundStyle(AppUI.label2)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func previewTone(id: String, text: String) {
        previewingID = id
        preview.speak(
            text,
            systemVoiceIdentifier: settings.voice.systemVoiceIdentifier
        ) { previewingID = nil }
    }
}

/// 试听器：用 AVSpeechSynthesizer 念一句示例文本。
@MainActor
@Observable
final class TonePreviewer {

    private let synthesizer = AVSpeechSynthesizer()

    func speak(
        _ text: String,
        systemVoiceIdentifier: String?,
        completion: @escaping () -> Void
    ) {
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
    }
}
