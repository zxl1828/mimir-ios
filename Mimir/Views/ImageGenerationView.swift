import SwiftUI
import UIKit

/// 独立的 AI 生图工作区，使用与聊天完全分离的服务配置。
struct ImageGenerationView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.appAccent) private var accent
    @State private var prompt = ""
    @State private var imageData: Data?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI 生图")
                        .font(.system(size: 30, weight: .bold))
                    Text("用文字生成图片，结果只保存在当前设备。")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }

                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.08)))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("描述画面")
                        .font(.system(size: 16, weight: .semibold))
                    TextEditor(text: $prompt)
                        .font(.system(size: 15))
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08)))
                    Button {
                        generate()
                    } label: {
                        HStack {
                            if isGenerating { ProgressView().tint(.white) }
                            Text(isGenerating ? "生成中" : "生成图片")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isConfigured)
                }
                .padding(16)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
                if !isConfigured {
                    Text("请在设置 > API 配置 > AI 生图中填写 Base URL、Key 和模型 ID。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .padding(.bottom, 100)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Color.clear)
    }

    private var isConfigured: Bool {
        let credential = settings.resolvedImageGenerationCredential
        return !credential.key.isEmpty && !credential.baseURL.isEmpty && !credential.modelID.isEmpty
    }

    private func generate() {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        isGenerating = true
        errorMessage = nil
        let credential = settings.resolvedImageGenerationCredential
        Task {
            do {
                let data = try await ImageGenerationService.generate(prompt: request, modelID: credential.modelID, credential: credential)
                imageData = data
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}
