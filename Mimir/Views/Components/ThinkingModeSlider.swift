import SwiftUI
import UIKit

/// 思考程度滑块：完全手写的玻璃拟物滑块（不用原生 `Slider`，因为原生改不了
/// 手柄溢出与多层光晕）。
///
/// 交互：拖动 1:1 跟手 → 松手 spring 吸附到最近档位；
/// 文案：非 Max 显示档位名（浅灰白），Max 切换成「更快消耗使用额度」（淡紫），淡入淡出。
struct ThinkingModeSlider: View {

    @Binding var selection: ThinkingMode

    @State private var progress: Double = 0
    @State private var isDragging = false
    @State private var isPresented = false

    private let trackHeight: CGFloat = 60
    private let thumbSize: CGFloat = 64

    private var isMax: Bool { selection == .ultra }

    var body: some View {
        Button {
            Haptics.impact(.light)
            isPresented.toggle()
        } label: {
            collapsedLabel
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            panel
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.clear)
        }
        .onAppear { progress = selection.normalized }
        .onChange(of: selection) { _, newValue in
            guard !isDragging else { return }
            withAnimation(AppAnimation.thinkingSnap) { progress = newValue.normalized }
        }
    }

    // MARK: - 收起状态（输入框上方的小胶囊）

    private var collapsedLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: selection.systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(selection.title)
                .font(AppFont.chipCompact)
        }
        .foregroundStyle(selection.tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule(style: .continuous).fill(selection.tint.opacity(0.14)))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(selection.tint.opacity(0.38), lineWidth: 0.8)
        )
        .shadow(color: selection.tint.opacity(0.25), radius: 10)
    }

    // MARK: - 展开面板

    private var panel: some View {
        VStack(spacing: 14) {
            captionText

            CustomThinkingSlider(
                progress: $progress,
                isDragging: $isDragging,
                tint: selection.tint,
                isMax: isMax,
                trackHeight: trackHeight,
                thumbSize: thumbSize
            ) { snapped in
                selection = snapped
            }

            levelLabels
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(width: 330)
        .liquidGlass(.regular, in: .rect(cornerRadius: 26))
        .glassHairline(cornerRadius: 26)
        .padding(1)
    }

    /// 动态文案：档位名 + 该档位的速度 / 额度引导语；
    /// Max 时两行都换成淡紫（「更快消耗使用额度」），并做淡入淡出。
    private var captionText: some View {
        VStack(spacing: 4) {
            Text(selection.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isMax ? Color.purple.opacity(0.8) : Color.white.opacity(0.88))
                .shadow(color: .white.opacity(0.5), radius: 10)

            Text(selection.guidance)
                .font(.system(size: 12))
                .foregroundStyle(isMax ? Color.purple.opacity(0.8) : Color.white.opacity(0.58))
                .shadow(color: .white.opacity(0.35), radius: 8)
        }
        .multilineTextAlignment(.center)
        .shadow(color: selection.tint.opacity(0.3), radius: 18)
        .animation(.easeInOut(duration: 0.25), value: selection)
        .contentTransition(.opacity)
    }

    private var levelLabels: some View {
        HStack(spacing: 0) {
            ForEach(ThinkingMode.allCases) { mode in
                Button {
                    Haptics.selectionChanged()
                    withAnimation(AppAnimation.thinkingSnap) {
                        selection = mode
                        progress = mode.normalized
                    }
                } label: {
                    Text(mode.title)
                        .font(.system(size: 12, weight: selection == mode ? .semibold : .regular))
                        .foregroundStyle(
                            selection == mode
                                ? (mode == .ultra ? Color.purple.opacity(0.9) : .white)
                                : Color.white.opacity(0.45)
                        )
                        .shadow(color: .white.opacity(selection == mode ? 0.4 : 0), radius: 8)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 滑块本体

/// 自定义滑块：ZStack + GeometryReader + DragGesture 手写。
struct CustomThinkingSlider: View {

    @Binding var progress: Double
    @Binding var isDragging: Bool
    var tint: Color
    var isMax: Bool = false
    var trackHeight: CGFloat = 60
    var thumbSize: CGFloat = 64
    /// 松手吸附后回调（交给上层同步 enum 档位）。
    var onSnap: (ThinkingMode) -> Void

    @State private var stretch: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let travel = max(width - thumbSize, 1)

            ZStack(alignment: .leading) {
                TrackView(
                    progress: progress,
                    trackHeight: trackHeight,
                    thumbSize: thumbSize,
                    isMax: isMax
                )

                ThumbView(size: thumbSize, tint: tint, stretch: isDragging ? stretch : 0)
                    .offset(x: progress * travel)
                    .animation(AppAnimation.thinkingSnap, value: isDragging)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            Haptics.impact(.light)
                        }
                        let traveled = value.location.x - thumbSize / 2
                        progress = min(max(Double(traveled / travel), 0), 1)
                        stretch = min(abs(value.translation.width) / 220, 0.12)
                    }
                    .onEnded { _ in
                        isDragging = false
                        stretch = 0
                        let snapped = ThinkingMode.nearest(progress: progress)
                        withAnimation(AppAnimation.thinkingSnap) {
                            progress = snapped.normalized
                        }
                        if snapped == .ultra {
                            Haptics.impact(.heavy)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } else {
                            Haptics.selectionChanged()
                        }
                        onSnap(snapped)
                    }
            )
        }
        // 手柄比轨道大，外层绝不能 clipped，否则光晕会被切掉。
        .frame(height: thumbSize)
        .padding(.vertical, (thumbSize - trackHeight) / 2)
    }
}

// MARK: - 轨道

/// 轨道：蓝 → 紫水平渐变，左侧已选段更亮，右侧未选段半透明。
struct TrackView: View {

    var progress: Double
    var trackHeight: CGFloat
    var thumbSize: CGFloat
    var isMax: Bool

    private var gradient: LinearGradient {
        LinearGradient(
            colors: isMax
                ? [.blue, .purple, .orange.opacity(0.9)]
                : [.blue, .purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack(alignment: .leading) {
                // 未选段：同一渐变，压低透明度
                Capsule(style: .continuous)
                    .fill(gradient)
                    .opacity(0.28)

                // 已选段：满亮度 + 顶部高光，形成玻璃质感
                Capsule(style: .continuous)
                    .fill(gradient)
                    .frame(width: max(width * progress, trackHeight))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .purple.opacity(progress > 0.6 ? 0.45 : 0.2), radius: 14)

                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
            }
            .frame(height: trackHeight)
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - 手柄

/// 纯白圆球 + 多层光晕（白 → 紫 → 档位色），直径略大于轨道形成溢出感。
struct ThumbView: View {

    var size: CGFloat
    var tint: Color
    var stretch: CGFloat = 0

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: size, height: size)
            .overlay(
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1)
            )
            .scaleEffect(x: 1 + stretch, y: 1 - stretch * 0.5)
            .shadow(color: .white.opacity(0.8), radius: 15)
            .shadow(color: Color.purple.opacity(0.5), radius: 30)
            .shadow(color: tint.opacity(0.35), radius: 8)
            .animation(AppAnimation.thinkingSnap, value: stretch)
    }
}

/// 预览宿主：深色背景 + 滑块，方便直接看光晕与吸附效果。
struct ThinkingModeSliderPreviewHost: View {

    @State private var mode: ThinkingMode = .thinking

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.13),
                    Color(red: 0.12, green: 0.10, blue: 0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                ThinkingModeSlider(selection: $mode)
                Text("当前：\(mode.title)")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding()
        }
    }
}

#Preview {
    ThinkingModeSliderPreviewHost()
}
