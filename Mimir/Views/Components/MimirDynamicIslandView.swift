import SwiftUI

/// Tab 1 扩展：灵动岛常驻面板（MimirDynamicIslandView）。
///
/// 具备双态流体变换：
/// - **紧凑态（Compact）**：Leading 呈现 Mimir 动态微缩猫头鹰（带呼吸微光），Trailing 呈现实时状态小图标。
/// - **展开态（Expanded）**：长按或点按平滑流体展开，包含环境状态条、自动聚焦的胶囊输入框、2~4 行精炼打字机文本回复区及关闭动作。
struct MimirDynamicIslandView: View {

    var onSendPrompt: ((String) -> Void)? = nil
    var activeModelName: String = "DeepSeek-Reasoner"

    @State private var isExpanded: Bool = false
    @State private var quickText: String = ""
    @State private var isBreathing: Bool = false
    @FocusState private var isInputFocused: Bool

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if isExpanded {
                expandedView
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.75, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.85, anchor: .top).combined(with: .opacity)
                        )
                    )
            } else {
                compactView
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 1.15, anchor: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.90, anchor: .top).combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isExpanded)
    }

    // MARK: - 紧凑态 (Compact)

    private var compactView: some View {
        HStack(spacing: 8) {
            // Leading: Mimir 动态微缩猫头鹰（带呼吸微光）
            ZStack {
                Circle()
                    .fill(accent.opacity(isBreathing ? 0.35 : 0.15))
                    .frame(width: 26, height: 26)
                    .blur(radius: 4)

                Image(systemName: "bird.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
            }

            Text("Mimir")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppUI.textTitle(scheme: scheme))

            Spacer()

            // Trailing: 实时环境状态指示
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: "34D399"))
                    .frame(width: 6, height: 6)
                    .shadow(color: Color(hex: "34D399").opacity(0.6), radius: 3)

                Text("Ready")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))

                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 218, height: 38)
        .liquidGlass(.regular.interactive(), in: .capsule)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(scheme == .dark ? 0.40 : 0.85),
                            accent.opacity(scheme == .dark ? 0.35 : 0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
                .allowsHitTesting(false)
        }
        .shadow(color: accent.opacity(scheme == .dark ? 0.28 : 0.12), radius: 10, y: 3)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            Haptics.impact(.medium)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                isExpanded = true
                isInputFocused = true
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            Haptics.impact(.medium)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                isExpanded = true
                isInputFocused = true
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    // MARK: - 展开态 (Expanded)

    private var expandedView: some View {
        VStack(spacing: 12) {
            // 1. 顶栏：环境状态条与关闭动作
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.25))
                        .frame(width: 28, height: 28)
                    Image(systemName: "bird.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Mimir 智能助理常驻流")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    Text(activeModelName)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(accent)
                }

                Spacer()

                // 关闭按钮（保证 44x44pt 热区）
                Button {
                    Haptics.impact(.light)
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        isInputFocused = false
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PhysicalElasticCircleButtonStyle(scale: 0.92))
            }

            // 2. 精炼回复/状态摘要区（2~4 行打字机文案）
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(accent)
                    .padding(.top, 2)

                Text("全机环境与上下文已就绪，当前模型处于高智力推理状态。你可以随时在下方输入快速指令或提问。")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .lineSpacing(3)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            }

            // 3. 自动聚焦的胶囊输入框
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    .padding(.leading, 4)

                TextField("快速指令或向 Mimir 提问…", text: $quickText)
                    .font(.system(size: 13.5))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        submitQuickText()
                    }

                if !quickText.isEmpty {
                    Button {
                        submitQuickText()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PhysicalElasticCircleButtonStyle(scale: 0.90))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .background(
                Capsule(style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(accent.opacity(0.35), lineWidth: 0.9)
            )
        }
        .padding(14)
        .frame(width: 342)
        .liquidGlass(.regular.interactive(), in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(scheme == .dark ? 0.45 : 0.85),
                            accent.opacity(scheme == .dark ? 0.40 : 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .allowsHitTesting(false)
        }
        .shadow(color: accent.opacity(scheme == .dark ? 0.35 : 0.16), radius: 20, y: 8)
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.50 : 0.10), radius: 14, y: 5)
    }

    private func submitQuickText() {
        let trimmed = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Haptics.impact(.medium)
        onSendPrompt?(trimmed)
        quickText = ""
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            isInputFocused = false
            isExpanded = false
        }
    }
}
