import SwiftUI
import UIKit

/// 首次启动引导。
///
/// 首屏只保留三样东西：API Key 输入框、继续键、一行提示文字，
/// 三者作为一个整体严格垂直居中，并带浮入动画。
struct OnboardingView: View {

    @Environment(AppSettings.self) private var settings

    @State private var keyText: String = ""
    @State private var selectedFormat = APIKeyFormat.openAI
    @State private var baseURLText = APIKeyFormat.openAI.defaultBaseURL
    @State private var modelIDText = ""
    @State private var discoveredModels: [String] = []
    @State private var isRevealed: Bool = false
    @State private var phase: Phase = .idle
    @State private var noticeText: String?
    @State private var noticeIsError: Bool = false
    @State private var shakeOffset: CGFloat = 0
    @State private var hasAppeared: Bool = false
    @State private var burstProgress: Double = 0
    @FocusState private var fieldFocused: Bool

    private enum Phase: Equatable {
        case idle
        case validating
        case success
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    MimirMascot(size: 132, mood: phase == .success ? .happy : .calm)
                        .padding(.bottom, 34)

                    keyField

                    Picker("接口协议", selection: $selectedFormat) {
                        Text("OpenAI 兼容").tag(APIKeyFormat.openAI)
                        Text("DeepSeek").tag(APIKeyFormat.deepseekNative)
                        Text("Anthropic").tag(APIKeyFormat.anthropic)
                    }
                    .pickerStyle(.segmented)
                    .disabled(phase == .validating)
                    .padding(.top, 14)
                    .onChange(of: selectedFormat) { oldFormat, newFormat in
                        if baseURLText == oldFormat.defaultBaseURL || baseURLText.isEmpty {
                            baseURLText = newFormat.defaultBaseURL
                        }
                    }

                    baseURLField
                        .padding(.top, 10)

                    TextField("模型 ID（留空尝试读取 /models）", text: $modelIDText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(AppColor.primaryText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(phase == .validating)
                        .padding(.horizontal, 16)
                        .frame(width: fieldWidth, height: 42)
                        .liquidGlass(.clear, in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                                .allowsHitTesting(false)
                        }
                        .padding(.top, 8)

                    continueButton
                        .padding(.top, 16)

                    notice
                        .padding(.top, 12)
                }
                .frame(maxWidth: fieldWidth)
                .offset(y: hasAppeared ? 0 : 20)
                .opacity(hasAppeared ? 1 : 0)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.keyboard, edges: .bottom)

            burstLayer
        }
        .onAppear {
            withAnimation(AppAnimation.onboarding.delay(0.05)) {
                hasAppeared = true
            }
            fieldFocused = true
        }
    }

    // MARK: - 尺寸

    private var fieldWidth: CGFloat {
        let screen = UIScreen.main.bounds.width
        return min(screen * 0.85, 400)
    }

    // MARK: - 输入框

    private var keyField: some View {
        HStack(spacing: 10) {
            TextField("sk-...", text: $keyText)
                .textFieldStyle(.plain)
                .font(AppFont.onboardingField)
                .foregroundStyle(AppColor.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.continue)
                .focused($fieldFocused)
                .disabled(phase == .validating)
                .onChange(of: keyText) { _, value in
                    if value.hasPrefix("sk-ant-") {
                        selectedFormat = .anthropic
                    }
                    if noticeIsError {
                        noticeText = nil
                        noticeIsError = false
                    }
                }
                .onSubmit { Task { await validate() } }

            if keyText.isEmpty {
                pasteButton
            } else {
                revealButton
            }
        }
        .padding(.horizontal, 18)
        .frame(width: fieldWidth, height: 56)
        .liquidGlass(.regular, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(focusBorder, lineWidth: fieldFocused ? 1.4 : 0.8)
                .allowsHitTesting(false)
        }
        .shadow(color: focusGlow, radius: fieldFocused ? 18 : 5, y: 4)
        .scaleEffect(fieldFocused ? 1.02 : 1.0)
        .animation(AppAnimation.onboarding, value: fieldFocused)
        .animation(AppAnimation.onboarding, value: isRevealed)
    }

    private var baseURLField: some View {
        TextField("服务商 API Base URL", text: $baseURLText)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(AppColor.primaryText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .disabled(phase == .validating)
            .padding(.horizontal, 16)
            .frame(width: fieldWidth, height: 42)
            .liquidGlass(.clear, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
    }

    private var focusBorder: LinearGradient {
        if fieldFocused {
            return LinearGradient(
                colors: [AppColor.brandBlue, AppColor.brandPurple, AppColor.brandBlue],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            colors: [Color.white.opacity(0.22), Color.white.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var focusGlow: Color {
        fieldFocused ? AppColor.brandBlue.opacity(0.35) : Color(hex: "EADEFA").opacity(0.35)
    }

    private var revealButton: some View {
        Button {
            Haptics.impact(.light)
            isRevealed.toggle()
        } label: {
            Image(systemName: isRevealed ? "eye.slash" : "eye")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColor.secondaryText)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRevealed ? "隐藏 API Key" : "显示 API Key")
    }

    private var pasteButton: some View {
        Button {
            pasteFromClipboard()
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColor.secondaryText)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("粘贴 API Key")
    }

    // MARK: - 继续键

    private var continueButton: some View {
        Button {
            Task { await validate() }
        } label: {
            ZStack {
                Capsule(style: .continuous)
                    .fill(buttonFill)

                switch phase {
                case .idle:
                    Text("继续")
                        .font(AppFont.button)
                        .foregroundStyle(.white)
                case .validating:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.05)
                case .success:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                        Text("已连接")
                            .font(AppFont.button)
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(width: fieldWidth, height: 56)
            .shadow(color: phase == .success ? AppColor.success.opacity(0.4) : AppColor.brandIndigo.opacity(0.32),
                    radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(phase == .validating || keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
        .animation(AppAnimation.onboarding, value: phase)
        .offset(x: shakeOffset)
    }

    private var buttonFill: LinearGradient {
        switch phase {
        case .success:
            return LinearGradient(
                colors: [AppColor.success, AppColor.success.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return AppColor.accentGradient
        }
    }

    // MARK: - 提示文字

    private var notice: some View {
        Text(noticeText ?? "输入 API Key 与服务商地址，自动读取可用模型")
            .font(AppFont.hint)
            .foregroundStyle(noticeIsError ? AppColor.danger : AppColor.secondaryText)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: fieldWidth)
            .animation(.easeInOut(duration: 0.2), value: noticeText)
    }

    // MARK: - 成功粒子扩散

    private var burstLayer: some View {
        Canvas { context, size in
            guard burstProgress > 0 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for index in 0..<16 {
                let angle = Double(index) / 16 * 2 * .pi
                let distance = burstProgress * 170
                let radius = max((1 - burstProgress) * 6, 0.6)
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * distance,
                    y: center.y + CGFloat(sin(angle)) * distance
                )
                let rect = CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(AppColor.success.opacity(max(1 - burstProgress, 0)))
                )
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // MARK: - 行为

    private func pasteFromClipboard() {
        guard let value = UIPasteboard.general.string, !value.isEmpty else {
            noticeText = "剪贴板里没有内容"
            noticeIsError = true
            Haptics.notify(.warning)
            return
        }
        keyText = value.trimmingCharacters(in: .whitespacesAndNewlines)
        Haptics.impact(.light)
    }

    private func validate() async {
        let trimmed = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, phase != .validating else { return }

        fieldFocused = false
        phase = .validating
        noticeText = nil
        noticeIsError = false

        var credential = APICredential.inferred(from: trimmed)
        credential.format = selectedFormat
        let enteredBaseURL = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !enteredBaseURL.isEmpty { credential.baseURL = enteredBaseURL }
        do {
            discoveredModels = try await ModelDiscoveryService.fetchModels(credential: credential)
            let preferred = discoveredModels.first(where: Self.looksLikeChatModel) ?? discoveredModels.first
            if modelIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let preferred {
                credential.modelID = preferred
                modelIDText = preferred
            }
        } catch {
            discoveredModels = []
        }
        if !modelIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            credential.modelID = modelIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let client = LLMClientFactory.make(for: credential)
        let result = await client.validate(credential: credential)

        guard result.isReachable else {
            phase = .idle
            noticeText = result.message
            noticeIsError = true
            Haptics.notify(.error)
            triggerShake()
            return
        }

        phase = .success
        Haptics.notify(.success)
        withAnimation(AppAnimation.glow) { burstProgress = 1 }

        try? await Task.sleep(for: .milliseconds(680))

        do {
            try settings.storeCredential(credential)
            if !discoveredModels.isEmpty {
                settings.customModels.removeAll {
                    $0.baseURL == credential.baseURL && $0.format == credential.format
                }
                settings.customModels.append(contentsOf: discoveredModels.map { modelID in
                    CustomModelEntry(
                        displayName: modelID,
                        modelID: modelID,
                        baseURL: credential.baseURL,
                        format: credential.format,
                        source: credential.baseURL,
                        note: ""
                    )
                })
            }
            noticeText = discoveredModels.isEmpty
                ? "已连接，可以在设置中读取或更换模型。"
                : "已连接并解析 \(discoveredModels.count) 个模型。"
            withAnimation(AppAnimation.onboarding) {
                settings.hasCompletedOnboarding = true
            }
        } catch {
            phase = .idle
            noticeText = error.localizedDescription
            noticeIsError = true
            burstProgress = 0
        }
    }

    private static func looksLikeChatModel(_ modelID: String) -> Bool {
        let value = modelID.lowercased()
        guard !value.contains("embedding"), !value.contains("rerank"), !value.contains("moderation") else {
            return false
        }
        return ["chat", "gpt", "claude", "deepseek", "qwen", "llama", "mistral", "gemini", "sonnet", "opus", "haiku"]
            .contains { value.contains($0) }
    }

    private func triggerShake() {
        Task {
            for step in 0..<6 {
                withAnimation(.linear(duration: 0.05)) {
                    shakeOffset = step % 2 == 0 ? 10 : -10
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
                shakeOffset = 0
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppSettings())
}
