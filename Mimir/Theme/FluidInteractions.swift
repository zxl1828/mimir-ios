import SwiftUI
import UIKit

// MARK: - 2. 胶囊按钮向弹窗面板的流体形态变换 (Fluid Morph from Capsule to Panel)

/// 胶囊按钮与弹出面板之间的流体形态过渡容器。
/// 尺寸与圆角采用高阻尼流体曲线（response: 0.42, dampingFraction: 0.82）进行无缝连续几何变换。
struct FluidMorphCapsuleToPanelContainer<CollapsedContent: View, ExpandedContent: View>: View {

    @Binding var isExpanded: Bool
    @ViewBuilder let collapsed: () -> CollapsedContent
    @ViewBuilder let expanded: () -> ExpandedContent

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if isExpanded {
                expanded()
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.90, anchor: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: 10)),
                            removal: .scale(scale: 0.92, anchor: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: 8))
                        )
                    )
            } else {
                collapsed()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isExpanded)
    }
}

// MARK: - 3. 共享元素转场 (Shared Element Transition)

/// 全屏大图查看器（带共享元素连续缩放与背景连续渐变）。
struct SharedElementImageViewer: View {

    let image: UIImage
    var onDismiss: @Sendable () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDismissing = false

    private var dragProgress: CGFloat {
        let distance = sqrt(dragOffset.width * dragOffset.width + dragOffset.height * dragOffset.height)
        return min(max(distance / 280.0, 0), 1.0)
    }

    private var currentScale: CGFloat {
        max(1.0 - dragProgress * 0.35, 0.65)
    }

    var body: some View {
        ZStack {
            // 背景连续平滑缩放与透明度渐变（使用极深紫，严禁纯黑）
            Color(hex: "120D1D")
                .opacity((1.0 - Double(dragProgress) * 0.85) * (isDismissing ? 0 : 0.96))
                .ignoresSafeArea()
                .onTapGesture { dismissWithAnimation() }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismissWithAnimation()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .padding(16)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                // 图片主体：连续平滑平移与阻尼缩放
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18 * currentScale, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18 * currentScale, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.24 * (1 - dragProgress)), lineWidth: 1)
                    )
                    .shadow(color: Color(hex: "120D1D").opacity(0.6 * (1 - dragProgress)), radius: 24, y: 12)
                    .scaleEffect(currentScale)
                    .offset(dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                let velocity = value.velocity.height
                                if abs(dragOffset.height) > 120 || abs(velocity) > 600 {
                                    dismissWithAnimation()
                                } else {
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                        dragOffset = .zero
                                    }
                                }
                            }
                    )

                Spacer()
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private func dismissWithAnimation() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            isDismissing = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            onDismiss()
        }
    }
}

// MARK: - 4. 支持阻尼橡皮筋回弹的底部抽屉 (Rubber-Banding Bottom Drawer with Velocity-Based Snap)

/// 支持真实对数阻尼橡皮筋回弹与松手滑动速度吸附的液态玻璃底部抽屉。
struct FluidRubberBandDrawer<Content: View>: View {

    @Binding var isPresented: Bool
    var minHeight: CGFloat = 160
    var maxHeight: CGFloat = 460
    @ViewBuilder let content: () -> Content

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    @State private var currentHeight: CGFloat = 320
    @State private var dragTranslationY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                (scheme == .dark ? Color(hex: "120D1D") : accent)
                    .opacity(scheme == .dark ? 0.36 : 0.12)
                    .ignoresSafeArea()
                    .onTapGesture { closeWithAnimation() }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    // 抽屉顶部液态抓握条（Grabber）
                    Capsule(style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.26) : accent.opacity(0.25))
                        .frame(width: 40, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    content()
                        .frame(maxWidth: .infinity)
                }
                .frame(height: effectiveHeight)
                .liquidGlass(.regular, in: .rect(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1.1)
                        .allowsHitTesting(false)
                )
                .shadow(color: accent.opacity(scheme == .dark ? 0.35 : 0.12), radius: 20, y: -6)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragTranslationY = value.translation.height
                        }
                        .onEnded { value in
                            let velocityY = value.velocity.height
                            let targetHeight = currentHeight - dragTranslationY - velocityY * 0.16
                            dragTranslationY = 0

                            if velocityY > 700 || targetHeight < minHeight * 0.85 {
                                closeWithAnimation()
                            } else {
                                let snappedHeight = min(max(targetHeight, minHeight), maxHeight)
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                                    currentHeight = snappedHeight
                                }
                            }
                        }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.40, dampingFraction: 0.82), value: isPresented)
    }

    /// 应用苹果标准对数阻尼公式（Logarithmic Rubber Banding）计算的高度。
    private var effectiveHeight: CGFloat {
        let raw = currentHeight - dragTranslationY
        if raw > maxHeight {
            let over = raw - maxHeight
            return maxHeight + (1.0 - (1.0 / (over * 0.006 + 1.0))) * 64.0
        } else if raw < minHeight {
            let under = minHeight - raw
            return minHeight - (1.0 - (1.0 / (under * 0.006 + 1.0))) * 64.0
        }
        return max(raw, 0)
    }

    private func closeWithAnimation() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            isPresented = false
        }
    }
}

// MARK: - 5. 旋转渐变折射描边 (Rotating Gradient Border)

/// 为大型卡片窗口提供 360° 平滑慢速旋转的渐变折射描边。
/// 严格作为内部 strokeBorder 运行，杜绝外部未裁切矩形底色溢出。
struct RotatingGlowBorderModifier: ViewModifier {

    var cornerRadius: CGFloat = 22
    var lineWidth: CGFloat = 1.4
    var isAnimated: Bool = true
    var glowRadius: CGFloat = 24

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimated)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let angle = (time * 42.0).truncatingRemainder(dividingBy: 360)

            content
                // 顶部 360° 旋转渐变折射描边（纯内边框 strokeBorder，不外溢）
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(scheme == .dark ? 0.88 : 0.95),
                                    accent,
                                    Color.white.opacity(scheme == .dark ? 0.45 : 0.70),
                                    accent.opacity(0.60),
                                    Color.white.opacity(scheme == .dark ? 0.88 : 0.95)
                                ]),
                                center: .center,
                                angle: .degrees(angle)
                            ),
                            lineWidth: lineWidth
                        )
                        .allowsHitTesting(false)
                }
        }
    }
}

extension View {
    /// 添加 360° 旋转渐变折射描边。
    func rotatingGlowBorder(
        cornerRadius: CGFloat = 22,
        lineWidth: CGFloat = 1.4,
        isAnimated: Bool = true,
        glowRadius: CGFloat = 24
    ) -> some View {
        modifier(
            RotatingGlowBorderModifier(
                cornerRadius: cornerRadius,
                lineWidth: lineWidth,
                isAnimated: isAnimated,
                glowRadius: glowRadius
            )
        )
    }
}

// MARK: - 6. 列表元素交错弹性滑入 (Staggered Slide-Up Entrance Animation)

/// 列表元素入场交错滑入修饰器：每个子项按索引顺序以微弱弹性（Spring）向上滑入。
struct StaggeredEntranceModifier: ViewModifier {

    let index: Int
    var baseDelay: Double = 0.035
    var distance: CGFloat = 18

    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : distance)
            .animation(
                .spring(response: 0.44, dampingFraction: 0.76)
                .delay(Double(min(index, 16)) * baseDelay),
                value: hasAppeared
            )
            .onAppear {
                hasAppeared = true
            }
    }
}

extension View {
    /// 列表元素入场交错弹性滑入。
    func staggeredSlideEntrance(
        index: Int,
        baseDelay: Double = 0.035,
        distance: CGFloat = 18
    ) -> some View {
        modifier(
            StaggeredEntranceModifier(
                index: index,
                baseDelay: baseDelay,
                distance: distance
            )
        )
    }
}

// MARK: - 7. Static button feedback

struct StaticButtonFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.035 : 0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { Haptics.impact(.light) }
            }
    }
}

// MARK: - 8. 真实卡片交互与液态玻璃操作层 (Interactive Glass Card & Action Overlay)

/// 卡片浮动操作按钮定义。
struct GlassCardAction: Identifiable, Sendable {
    let id: String
    let title: String
    let icon: String
    let role: ButtonRole?
    let action: @MainActor @Sendable () -> Void

    init(
        title: String,
        icon: String,
        role: ButtonRole? = nil,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = title
        self.title = title
        self.icon = icon
        self.role = role
        self.action = action
    }
}

/// 交互式磨砂卡片修饰器：
/// - 按压时触发居中光学微缩与触感反馈；
/// - 长按或触发时弹起主题色液态玻璃操作蒙版与极细折射描边；
/// - 展示操作图标按钮，点击后平滑收起或点击外部收起。
struct GlassCardInteractiveModifier: ViewModifier {

    var cornerRadius: CGFloat
    var actions: [GlassCardAction]
    var onPrimaryTap: (() -> Void)?

    @State private var showActionOverlay: Bool = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent

    init(
        cornerRadius: CGFloat = AppUI.cardRadius,
        actions: [GlassCardAction] = [],
        onPrimaryTap: (() -> Void)? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.actions = actions
        self.onPrimaryTap = onPrimaryTap
    }

    public func body(content: Content) -> some View {
        content
            .overlay {
                if showActionOverlay && !actions.isEmpty {
                    actionOverlay
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.92)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            )
                        )
                }
            }
            .onLongPressGesture(minimumDuration: 0.42) {
                Haptics.impact(.medium)
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                    showActionOverlay.toggle()
                }
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    if showActionOverlay {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                            showActionOverlay = false
                        }
                    } else if let onPrimaryTap {
                        Haptics.impact(.light)
                        onPrimaryTap()
                    }
                }
            )
    }

    private var actionOverlay: some View {
        ZStack {
            // 紫色通透半透明液态磨砂玻璃底（彻底清除黑色）
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(scheme == .dark ? Color(hex: "120D1D").opacity(0.78) : Color(hex: "F8F6FD").opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(hex: "EADEFA").opacity(0.16))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.70),
                                    accent.opacity(0.85),
                                    Color.white.opacity(0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
                .shadow(color: accent.opacity(0.35), radius: 12)

            // 操作图标按钮列表
            HStack(spacing: 12) {
                ForEach(actions) { item in
                    Button {
                        Haptics.impact(.medium)
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                            showActionOverlay = false
                        }
                        item.action()
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(
                                        item.role == .destructive
                                            ? Color.red.opacity(0.28)
                                            : (scheme == .dark ? Color.white.opacity(0.18) : accent.opacity(0.12))
                                    )
                                    .frame(width: 38, height: 38)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                item.role == .destructive
                                                    ? Color.red.opacity(0.60)
                                                    : (scheme == .dark ? Color.white.opacity(0.40) : accent.opacity(0.32)),
                                                lineWidth: 0.8
                                            )
                                    }

                                Image(systemName: item.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(
                                        item.role == .destructive
                                            ? Color.red
                                            : (scheme == .dark ? Color.white : accent)
                                    )
                            }

                            Text(item.title)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(scheme == .dark ? Color.white.opacity(0.92) : AppUI.label)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(StaticButtonFeedbackStyle())
                }
            }
            .padding(.horizontal, 10)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                showActionOverlay = false
            }
        }
    }
}

extension View {
    /// 为卡片添加轻微物理按压触感与长按弹出的浅紫液态玻璃操作层。
    func interactiveGlassCard(
        cornerRadius: CGFloat = AppUI.cardRadius,
        actions: [GlassCardAction] = [],
        onPrimaryTap: (() -> Void)? = nil
    ) -> some View {
        modifier(
            GlassCardInteractiveModifier(
                cornerRadius: cornerRadius,
                actions: actions,
                onPrimaryTap: onPrimaryTap
            )
        )
    }
}

