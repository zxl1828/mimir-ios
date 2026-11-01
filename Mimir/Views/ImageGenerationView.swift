import SwiftUI
import Photos
import UIKit

/// 独立 AI 生图工坊面板（ImageGenerationView）。
///
/// 严格满足次世代视觉与交互规范：
/// 1. 采用原生液态玻璃修饰符 `liquidGlass` / `glassEffect` 与 `GlassContainer`；
/// 2. 补齐提示词、画幅比例（1:1, 16:9, 9:16, 4:3）及加载重试状态；
/// 3. Mimir 核心品牌色：Iris Violet (`#7D52F4`), Deep Plum (`#120D1D`), Pale Lavender (`#F8F6FD`)，严禁使用 `Color.black`；
/// 4. 触控反馈回归 iOS 原生标准，杜绝非标准手写水波纹与异常紫色膨胀光晕。
public struct ImageGenerationView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @Environment(\.modelContext) private var modelContext

    @State private var promptText: String = ""
    @State private var selectedRatio: AspectRatioOption = .square
    @State private var generationState: GenerationState = .idle
    @State private var generationTask: Task<Void, Never>?
    @State private var showSettings: Bool = false
    @State private var toastMessage: String? = nil
    @State private var isSavingImage: Bool = false

    private let irisViolet = Color(hex: "7D52F4")
    private let deepPlumBase = Color(hex: "120D1D")
    private let paleLavender = Color(hex: "F8F6FD")

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            // 背景流体光晕
            AppBackgroundView(background: settings.background)
                .ignoresSafeArea()

            topAmbientGlow
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        previewViewportCard
                        ratioSelectorSection
                        promptEditorCard
                        inspirationTagsSection
                        actionButtonSection
                        Spacer(minLength: 100) // 避让悬浮底栏
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }

            // Toast 浮动提示
            if let toast = toastMessage {
                toastView(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(200)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(list: ConversationListViewModel(modelContext: modelContext, settings: settings))
        }
        .onAppear {
            if let pending = TabNavigationCoordinator.shared.pendingImageGenerationPromptToChat {
                if pending != "描述你想生成的图片：" {
                    promptText = pending
                }
                TabNavigationCoordinator.shared.pendingImageGenerationPromptToChat = nil
            }
        }
    }

    // MARK: - 顶栏 (Header Bar)

    private var headerBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(irisViolet)

                VStack(alignment: .leading, spacing: 1) {
                    Text("AI 生图工坊")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(scheme == .dark ? paleLavender : deepPlumBase)

                    Text(currentModelLabel)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(irisViolet.opacity(0.85))
                }
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(scheme == .dark ? paleLavender.opacity(0.8) : deepPlumBase.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background {
                        Circle().fill(Color.white.opacity(scheme == .dark ? 0.08 : 0.6))
                    }
                    .liquidGlass(.regular, in: .circle)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8))
            }
            .buttonStyle(StaticButtonFeedbackStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var currentModelLabel: String {
        let id = settings.imageGenerationModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? "DALL-E-3 · OPENAI" : id.uppercased()
    }

    // MARK: - 画布预览区 (Preview Viewport Card)

    private var previewViewportCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill((scheme == .dark ? deepPlumBase : Color.white).opacity(scheme == .dark ? 0.65 : 0.82))
                .liquidGlass(.regular.tint(irisViolet.opacity(0.08)), in: .rect(cornerRadius: 22))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.85),
                                    irisViolet.opacity(0.35),
                                    Color.white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                }

            switch generationState {
            case .idle:
                idlePlaceholderView
            case .loading:
                loadingShimmerView
            case .success(let image, let data):
                successImageView(image: image, data: data)
            case .failed(let error):
                failureStateView(error: error)
            }
        }
        .aspectRatio(selectedRatio.displayRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: irisViolet.opacity(0.12), radius: 18, y: 8)
    }

    private var idlePlaceholderView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(irisViolet.opacity(0.12))
                    .frame(width: 58, height: 58)
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(irisViolet)
            }

            VStack(spacing: 4) {
                Text("输入提示词并配置画幅，开启超流体绘图")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(scheme == .dark ? paleLavender.opacity(0.9) : deepPlumBase.opacity(0.9))

                Text("支持 1:1 · 16:9 · 9:16 · 4:3 多画幅智能渲染")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(scheme == .dark ? paleLavender.opacity(0.55) : deepPlumBase.opacity(0.55))
            }
        }
        .padding(24)
    }

    private var loadingShimmerView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
                .tint(irisViolet)

            VStack(spacing: 6) {
                Text("正在渲染次世代图像...")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(scheme == .dark ? paleLavender : deepPlumBase)

                Text("正在进行扩散去噪与材质焦散计算")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(irisViolet.opacity(0.85))
            }

            Button {
                generationTask?.cancel()
                generationState = .idle
                showToast("已取消图像生成")
            } label: {
                Text("取消生成")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(irisViolet)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(irisViolet.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(irisViolet.opacity(0.3), lineWidth: 0.8))
            }
            .buttonStyle(StaticButtonFeedbackStyle())
        }
        .padding(24)
    }

    private func successImageView(image: UIImage, data: Data) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            // 图像操作浮层
            HStack(spacing: 8) {
                Button {
                    saveImageToAlbum(image)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .bold))
                        Text(isSavingImage ? "保存中" : "保存")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(deepPlumBase.opacity(0.78)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.8))
                }
                .buttonStyle(StaticButtonFeedbackStyle())
                .disabled(isSavingImage)

                ShareLink(item: Image(uiImage: image), preview: SharePreview("Mimir AI 图像生成", image: Image(uiImage: image))) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(deepPlumBase.opacity(0.78)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.8))
                }
                .buttonStyle(StaticButtonFeedbackStyle())
            }
            .padding(12)
        }
    }

    private func failureStateView(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.orange)

            Text("生成图像遇到异常")
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(scheme == .dark ? paleLavender : deepPlumBase)

            Text(error)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(scheme == .dark ? paleLavender.opacity(0.65) : deepPlumBase.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 20)

            Button {
                startImageGeneration()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                    Text("重试生成")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(irisViolet))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 0.8))
                .shadow(color: irisViolet.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .padding(.top, 4)
        }
        .padding(24)
    }

    // MARK: - 画幅比例选择器 (Aspect Ratio Selector)

    private var ratioSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("画幅比例")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(scheme == .dark ? paleLavender.opacity(0.85) : deepPlumBase.opacity(0.85))

            HStack(spacing: 8) {
                ForEach(AspectRatioOption.allCases) { option in
                    let isSelected = selectedRatio == option
                    Button {
                        Haptics.selectionChanged()
                        selectedRatio = option
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.icon)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            Text(option.title)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        }
                        .foregroundStyle(isSelected ? Color.white : (scheme == .dark ? paleLavender.opacity(0.7) : deepPlumBase.opacity(0.7)))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? irisViolet : (scheme == .dark ? deepPlumBase.opacity(0.4) : Color.white.opacity(0.7)))
                        }
                        .liquidGlass(isSelected ? .regular.tint(irisViolet.opacity(0.3)) : .regular, in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isSelected ? Color.white.opacity(0.75) : Color.white.opacity(0.3), lineWidth: isSelected ? 1.0 : 0.6)
                        }
                    }
                    .buttonStyle(StaticButtonFeedbackStyle())
                }
            }
        }
    }

    // MARK: - 提示词编辑卡片 (Prompt Editor Card)

    private var promptEditorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("创作提示词")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(scheme == .dark ? paleLavender.opacity(0.85) : deepPlumBase.opacity(0.85))

                Spacer()

                if !promptText.isEmpty {
                    Button("清空") {
                        promptText = ""
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(irisViolet)
                    .buttonStyle(StaticButtonFeedbackStyle())
                }
            }

            ZStack(alignment: .topLeading) {
                if promptText.isEmpty {
                    Text("输入描述文字，如：深空悬浮的机械赛博猫头鹰，折射星轨微光与超流体玻璃焦散...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(scheme == .dark ? paleLavender.opacity(0.35) : deepPlumBase.opacity(0.35))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                TextField("", text: $promptText, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(scheme == .dark ? paleLavender : deepPlumBase)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill((scheme == .dark ? deepPlumBase : Color.white).opacity(scheme == .dark ? 0.6 : 0.85))
            }
            .liquidGlass(.regular, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
            }
        }
    }

    // MARK: - 灵感预设标签 (Inspiration Tags)

    private var inspirationTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("灵感预设")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(scheme == .dark ? paleLavender.opacity(0.65) : deepPlumBase.opacity(0.65))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(inspirationPresets, id: \.self) { tag in
                        Button {
                            Haptics.selectionChanged()
                            if promptText.isEmpty {
                                promptText = tag
                            } else {
                                promptText += "，\(tag)"
                            }
                        } label: {
                            Text(tag)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(irisViolet)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(irisViolet.opacity(0.12)))
                                .overlay(Capsule().strokeBorder(irisViolet.opacity(0.28), lineWidth: 0.7))
                        }
                        .buttonStyle(StaticButtonFeedbackStyle())
                    }
                }
            }
        }
    }

    private let inspirationPresets: [String] = [
        "赛博机械猫头鹰",
        "超流体玻璃折射",
        "未来主义晶体城市",
        "电影级丁达尔光晕",
        "梦幻星轨极光",
        "微距水滴焦散",
        "柔和霓虹质感"
    ]

    // MARK: - 核心操作按钮 (Action Button)

    private var actionButtonSection: some View {
        Button {
            startImageGeneration()
        } label: {
            HStack(spacing: 8) {
                if case .loading = generationState {
                    ProgressView()
                        .tint(Color.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                }

                Text(caseLoading ? "正在渲染..." : "开始生成图像")
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                Capsule()
                    .fill(irisViolet.opacity(isGenerateDisabled ? 0.45 : 1.0))
            }
            .liquidGlass(.regular.tint(irisViolet.opacity(0.25)), in: .capsule)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.0))
            .shadow(color: irisViolet.opacity(isGenerateDisabled ? 0 : 0.35), radius: 12, y: 4)
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .disabled(isGenerateDisabled)
        .padding(.top, 4)
    }

    private var caseLoading: Bool {
        if case .loading = generationState { return true }
        return false
    }

    private var isGenerateDisabled: Bool {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || caseLoading
    }

    // MARK: - 生成逻辑与保存

    private func startImageGeneration() {
        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let credential = settings.resolvedCredential
        guard credential.format == .openAI, !credential.key.isEmpty else {
            generationState = .failed("请在设置中配置有效的 OpenAI 兼容 API Key。")
            showSettings = true
            return
        }

        let modelID = settings.imageGenerationModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = modelID.isEmpty ? "dall-e-3" : modelID

        generationState = .loading
        generationTask = Task {
            do {
                let data = try await ImageGenerationService.generate(
                    prompt: prompt,
                    modelID: resolvedModel,
                    size: selectedRatio.apiDimension,
                    credential: credential
                )
                try Task.checkCancellation()
                guard let image = UIImage(data: data) else {
                    throw LLMError.decoding("无法解析生成的图像数据")
                }
                await MainActor.run {
                    generationState = .success(image, data)
                    showToast("图像生成完成！")
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        generationState = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func saveImageToAlbum(_ image: UIImage) {
        isSavingImage = true
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    isSavingImage = false
                    showToast("未获得相册写入权限，请在系统设置中允许。")
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                Task { @MainActor in
                    isSavingImage = false
                    if success {
                        showToast("已成功保存至系统相册！")
                    } else {
                        showToast("保存失败：\(error?.localizedDescription ?? "未知错误")")
                    }
                }
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.24)) {
                    if toastMessage == message {
                        toastMessage = nil
                    }
                }
            }
        }
    }

    private func toastView(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(irisViolet)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(scheme == .dark ? paleLavender : deepPlumBase)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill((scheme == .dark ? deepPlumBase : Color.white).opacity(0.92))
        }
        .liquidGlass(.regular, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.8), lineWidth: 0.8))
        .shadow(color: irisViolet.opacity(0.2), radius: 12, y: 4)
        .padding(.top, 56)
    }

    private var topAmbientGlow: some View {
        RadialGradient(
            colors: [
                irisViolet.opacity(scheme == .dark ? 0.22 : 0.12),
                irisViolet.opacity(0.04),
                .clear
            ],
            center: .top,
            startRadius: 0,
            endRadius: 280
        )
        .frame(height: 280)
        .allowsHitTesting(false)
    }
}

// MARK: - 辅助模型与枚举

private enum GenerationState: Sendable {
    case idle
    case loading
    case success(UIImage, Data)
    case failed(String)
}

private enum AspectRatioOption: String, CaseIterable, Identifiable, Sendable {
    case square = "1:1"
    case wide = "16:9"
    case portrait = "9:16"
    case standard = "4:3"

    var id: String { rawValue }

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .square: return "square"
        case .wide: return "rectangle.ratio.16.to.9"
        case .portrait: return "rectangle.portrait"
        case .standard: return "rectangle.ratio.4.to.3"
        }
    }

    var displayRatio: CGFloat {
        switch self {
        case .square: return 1.0
        case .wide: return 16.0 / 9.0
        case .portrait: return 9.0 / 16.0
        case .standard: return 4.0 / 3.0
        }
    }

    var apiDimension: String {
        switch self {
        case .square: return "1024x1024"
        case .wide: return "1792x1024"
        case .portrait: return "1024x1792"
        case .standard: return "1024x768"
        }
    }
}
