import SwiftUI

/// 模型档位与额度面板。
///
/// 从顶栏胶囊点开：260pt 底部 Sheet，顶部灰色拖拽条、档位标题 + 模型名、
/// 蓝 → 紫渐变滑块。滑块位置实时映射到 `ThinkingMode`，并回写对话的推理档位。
struct ModelSelectionSheet: View {

    @Binding var currentLevel: ThinkingMode
    /// Sheet 副标题显示的模型名。
    var modelName: String

    @Environment(\.dismiss) private var dismiss

    @State private var progress: Double = 0
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            SheetGrabber()

            header
                .padding(.bottom, 18)

            GradientLevelSlider(
                progress: $progress,
                isDragging: $isDragging,
                onChange: { level in
                    guard level != currentLevel else { return }
                    currentLevel = level
                },
                onSnap: { level in
                    currentLevel = level
                }
            )
            .frame(height: 34)
            .padding(.horizontal, 2)

            footer
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppUI.hPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppUI.canvas)
        .presentationDetents([.height(260)])
        .presentationCornerRadius(24)
        .presentationDragIndicator(.hidden)
        .onAppear { progress = Self.progress(for: currentLevel) }
        .onChange(of: currentLevel) { _, newValue in
            guard !isDragging else { return }
            withAnimation(AppUI.snap) { progress = Self.progress(for: newValue) }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - 标题区

    /// 档位名 + chevron；点一下切到下一档（循环），保证箭头始终有反馈。
    private var header: some View {
        Button {
            Haptics.impact(.light)
            let next = Self.nextLevel(after: currentLevel)
            withAnimation(AppUI.snap) {
                currentLevel = next
                progress = Self.progress(for: next)
            }
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Text(currentLevel.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppUI.label)
                        .contentTransition(.opacity)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppUI.label3)
                }

                Text(modelName)
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("当前档位 \(currentLevel.title)，点按切换下一档")
    }

    // MARK: - 底部说明

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("更快消耗使用额度")
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label3)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(ThinkingMode.ultra.title)
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label3)
        }
    }

    // MARK: - 档位映射

    /// 0...1 位置 → 档位：< 0.25 最低档，≥ 0.85 为 Max。
    static func level(for progress: Double) -> ThinkingMode {
        let p = min(max(progress, 0), 1)
        if p < 0.25 { return .quick }
        if p < 0.5 { return .thinking }
        if p < 0.85 { return .expert }
        return .ultra
    }

    /// 档位 → 滑块停靠位置（与 `level(for:)` 的分段一一对应）。
    static func progress(for level: ThinkingMode) -> Double {
        switch level {
        case .quick: return 0.12
        case .thinking: return 0.38
        case .expert: return 0.68
        case .ultra: return 1.0
        }
    }

    static func nextLevel(after level: ThinkingMode) -> ThinkingMode {
        let all = ThinkingMode.allCases
        guard let index = all.firstIndex(of: level) else { return all.first ?? .thinking }
        return all[(index + 1) % all.count]
    }
}

/// 标准 iOS 滑块外观 + 蓝紫渐变轨道的自绘实现（系统 `Slider` 不支持渐变轨道）。
struct GradientLevelSlider: View {

    @Binding var progress: Double
    @Binding var isDragging: Bool
    var onChange: (ThinkingMode) -> Void
    var onSnap: (ThinkingMode) -> Void

    private let trackHeight: CGFloat = 8
    private let thumbSize: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let usable = max(width - thumbSize, 1)
            let clamped = min(max(progress, 0), 1)
            let thumbX = thumbSize / 2 + usable * clamped

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .systemGray5))
                    .frame(height: trackHeight)

                Capsule(style: .continuous)
                    .fill(AppUI.levelGradient)
                    .frame(width: max(thumbX, trackHeight), height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(
                        color: Color.black.opacity(isDragging ? 0.22 : 0.14),
                        radius: isDragging ? 7 : 4,
                        y: 1
                    )
                    .scaleEffect(isDragging ? 1.06 : 1)
                    .offset(x: thumbX - thumbSize / 2)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            Haptics.impact(.light)
                        }
                        let raw = (value.location.x - thumbSize / 2) / usable
                        let next = min(max(raw, 0), 1)
                        let previousLevel = ModelSelectionSheet.level(for: progress)
                        progress = next
                        let level = ModelSelectionSheet.level(for: next)
                        if level != previousLevel {
                            Haptics.selectionChanged()
                        }
                        onChange(level)
                    }
                    .onEnded { _ in
                        isDragging = false
                        let level = ModelSelectionSheet.level(for: progress)
                        withAnimation(AppUI.snap) {
                            progress = ModelSelectionSheet.progress(for: level)
                        }
                        onSnap(level)
                    }
            )
        }
        .animation(AppUI.snap, value: isDragging)
        .accessibilityElement()
        .accessibilityLabel("推理档位")
        .accessibilityValue(currentValueLabel)
        .accessibilityAdjustableAction { direction in
            let all = ThinkingMode.allCases
            guard let index = all.firstIndex(where: { $0 == ModelSelectionSheet.level(for: progress) }) else { return }
            let nextIndex: Int
            switch direction {
            case .increment: nextIndex = min(index + 1, all.count - 1)
            case .decrement: nextIndex = max(index - 1, 0)
            @unknown default: return
            }
            let level = all[nextIndex]
            withAnimation(AppUI.snap) {
                progress = ModelSelectionSheet.progress(for: level)
            }
            onSnap(level)
        }
    }

    private var currentValueLabel: String {
        ModelSelectionSheet.level(for: progress).title
    }
}

#Preview {
    ModelSelectionSheetPreviewHost()
}

private struct ModelSelectionSheetPreviewHost: View {

    @State private var level: ThinkingMode = .ultra

    var body: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                ModelSelectionSheet(currentLevel: $level, modelName: "DeepSeek Chat")
            }
    }
}
