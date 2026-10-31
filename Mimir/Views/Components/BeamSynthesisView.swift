import SwiftUI

struct BeamSynthesisView: View {
    let responses: [BeamResponse]
    let isStreaming: Bool
    let synthesis: String
    let synthesisError: String?
    let isSynthesizing: Bool
    let onSynthesize: () -> Void
    let onCommit: (BeamResponse, Bool) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @AppStorage("mimir.cost.usdToCNY") private var usdToCNY = 7.2

    var body: some View {
        VStack(spacing: 10) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(responses) { response in
                        responseCard(response)
                    }
                    if !synthesis.isEmpty || isSynthesizing { synthesisCard }
                    if let synthesisError {
                        Text(synthesisError)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            if !isStreaming {
                HStack(spacing: 10) {
                    Button(action: onSynthesize) {
                        Label(isSynthesizing ? "正在融合…" : "Beam 智能融合", systemImage: "diamond.inset.filled")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(LinearGradient(colors: [accent, Color(hex: "A98AFF")], startPoint: .leading, endPoint: .trailing), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.68), lineWidth: 0.9))
                    }
                    .disabled(isSynthesizing || responses.allSatisfy { $0.text.isEmpty })
                    Spacer(minLength: 0)
                    if !synthesis.isEmpty {
                        Button("保存综合答复") {
                            onCommit(responses.first ?? BeamResponse(modelID: "Beam"), true)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .disabled(isSynthesizing)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "120D1D").opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1))
        .padding(.horizontal, 8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "diamond.inset.filled").foregroundStyle(accent)
            Text("BEAM / \(responses.count) MODELS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "F8F6FD"))
            Spacer()
            if isStreaming || isSynthesizing { ProgressView().tint(accent).controlSize(.small) }
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color.white.opacity(0.72))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭 Beam")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private func responseCard(_ response: BeamResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(response.modelID)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Spacer()
                if let cost = ModelPricingCatalog.costUSD(
                    modelID: response.modelID,
                    promptTokens: response.usage.promptTokens,
                    outputTokens: response.usage.completionTokens + response.usage.reasoningTokens
                ) {
                        Text(String(format: "$%.5f · ¥%.4f", cost, cost * usdToCNY))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
                if !response.text.isEmpty {
                    Button("采用") { onCommit(response, false) }
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            if let error = response.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
            } else {
                Text(response.text.isEmpty ? "等待模型响应…" : response.text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hex: "EDE5FA"))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
    }

    private var synthesisCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("综合答复", systemImage: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: "C6B4FF"))
            Text(synthesis.isEmpty ? "正在汇总候选回答…" : synthesis)
                .font(.system(size: 11.5))
                .foregroundStyle(Color(hex: "F8F6FD"))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.42), lineWidth: 0.8))
    }
}
