import SwiftUI
import UIKit

// MARK: - Mimir 物理微动效引擎 (Mimir Motion Engine)
//
// 封装 6 大核心物理微动效：
// 1. 物理弹簧交错流 (Stagger Cascade)
// 2. 流体胶囊形态过渡 (Fluid Morph)
// 3. 共享元素无缝展开 (Shared Element Transition)
// 4. 弹性微缩与超调触觉反馈 (Press Scale & Spring Overshoot)
// 5. 阻尼弹性速度吸附抽屉 (Velocity-Snapping Bottom Sheet)

// MARK: - 1. 物理弹簧交错流 (Stagger Cascade)

/// 列表与网格交错弹簧入场修饰器（外部受控状态）。
public struct StaggerCascadeModifier: ViewModifier {
    public let index: Int
    public let isAppeared: Bool
    public var baseDelay: Double
    public var distance: CGFloat
    public var initialScale: CGFloat

    public init(
        index: Int,
        isAppeared: Bool,
        baseDelay: Double = 0.08,
        distance: CGFloat = 28,
        initialScale: CGFloat = 0.95
    ) {
        self.index = index
        self.isAppeared = isAppeared
        self.baseDelay = baseDelay
        self.distance = distance
        self.initialScale = initialScale
    }

    public func body(content: Content) -> some View {
        let delay = Double(index) * baseDelay
        content
            .offset(y: isAppeared ? 0 : distance)
            .opacity(isAppeared ? 1.0 : 0.0)
            .scaleEffect(isAppeared ? 1.0 : initialScale)
            .animation(
                .spring(response: 0.42, dampingFraction: 0.72).delay(delay),
                value: isAppeared
            )
    }
}

/// 自动在 onAppear 时触发的交错弹簧入场修饰器。
public struct AutoStaggerCascadeModifier: ViewModifier {
    public let index: Int
    public var baseDelay: Double
    public var distance: CGFloat
    public var initialScale: CGFloat

    @State private var hasAppeared: Bool = false

    public init(
        index: Int,
        baseDelay: Double = 0.08,
        distance: CGFloat = 28,
        initialScale: CGFloat = 0.95
    ) {
        self.index = index
        self.baseDelay = baseDelay
        self.distance = distance
        self.initialScale = initialScale
    }

    public func body(content: Content) -> some View {
        let delay = Double(index) * baseDelay
        content
            .offset(y: hasAppeared ? 0 : distance)
            .opacity(hasAppeared ? 1.0 : 0.0)
            .scaleEffect(hasAppeared ? 1.0 : initialScale)
            .animation(
                .spring(response: 0.42, dampingFraction: 0.72).delay(delay),
                value: hasAppeared
            )
            .onAppear {
                hasAppeared = true
            }
    }
}

extension View {
    /// 应用物理弹簧交错流（Stagger Cascade）：每个子项延时 0.08s * index，弹性滑入归位。
    public func staggerCascade(
        index: Int,
        baseDelay: Double = 0.08,
        distance: CGFloat = 28,
        initialScale: CGFloat = 0.95
    ) -> some View {
        modifier(
            AutoStaggerCascadeModifier(
                index: index,
                baseDelay: baseDelay,
                distance: distance,
                initialScale: initialScale
            )
        )
    }

    /// 应用物理弹簧交错流（外部绑定 isAppeared 控制）。
    public func staggerCascade(
        index: Int,
        isAppeared: Bool,
        baseDelay: Double = 0.08,
        distance: CGFloat = 28,
        initialScale: CGFloat = 0.95
    ) -> some View {
        modifier(
            StaggerCascadeModifier(
                index: index,
                isAppeared: isAppeared,
                baseDelay: baseDelay,
                distance: distance,
                initialScale: initialScale
            )
        )
    }
}

// MARK: - 2. 流体胶囊形态变换 (Fluid Morph)

/// 胶囊按钮向独立面板流体变换容器（无生硬弹窗，几何连贯过渡）。
public struct FluidMorphContainer<Collapsed: View, Expanded: View>: View {
    @Binding public var isExpanded: Bool
    @ViewBuilder public let collapsed: () -> Collapsed
    @ViewBuilder public let expanded: () -> Expanded

    public init(
        isExpanded: Binding<Bool>,
        @ViewBuilder collapsed: @escaping () -> Collapsed,
        @ViewBuilder expanded: @escaping () -> Expanded
    ) {
        self._isExpanded = isExpanded
        self.collapsed = collapsed
        self.expanded = expanded
    }

    public var body: some View {
        ZStack {
            if isExpanded {
                expanded()
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.90, anchor: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: 8)),
                            removal: .scale(scale: 0.92, anchor: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: 6))
                        )
                    )
            } else {
                collapsed()
                    .transition(
                        .scale(scale: 0.96)
                            .combined(with: .opacity)
                    )
            }
        }
        .animation(
            .interpolatingSpring(stiffness: 280, damping: 24),
            value: isExpanded
        )
    }
}

// MARK: - 3. 共享元素转场 (Shared Element Transition)

/// 共享元素无缝缩放查看容器（连续平滑缩放 1.0 -> 1.08 -> 全屏，背景液态玻璃无缝拉伸）。
public struct SharedElementTransitionView<Content: View>: View {
    public let image: UIImage?
    public var onDismiss: @Sendable () -> Void
    @ViewBuilder public let overlayContent: () -> Content

    @State private var dragOffset: CGSize = .zero
    @State private var isDismissing: Bool = false

    public init(
        image: UIImage?,
        onDismiss: @escaping @Sendable () -> Void,
        @ViewBuilder overlayContent: @escaping () -> Content = { EmptyView() }
    ) {
        self.image = image
        self.onDismiss = onDismiss
        self.overlayContent = overlayContent
    }

    private var dragProgress: CGFloat {
        let distance = sqrt(dragOffset.width * dragOffset.width + dragOffset.height * dragOffset.height)
        return min(max(distance / 280.0, 0), 1.0)
    }

    private var currentScale: CGFloat {
        max(1.0 - dragProgress * 0.35, 0.65)
    }

    public var body: some View {
        ZStack {
            // 背景连续平滑透明度渐变，杜绝白屏闪烁
            Color.black
                .opacity((1.0 - Double(dragProgress) * 0.85) * (isDismissing ? 0 : 0.94))
                .ignoresSafeArea()
                .onTapGesture { dismissWithSpring() }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        dismissWithSpring()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .padding(18)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 20 * currentScale, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20 * currentScale, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.24 * (1 - dragProgress)), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.60 * (1 - dragProgress)), radius: 32, y: 16)
                        .scaleEffect(currentScale)
                        .offset(dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                }
                                .onEnded { value in
                                    let velocity = value.velocity.height
                                    if abs(dragOffset.height) > 130 || abs(velocity) > 650 {
                                        dismissWithSpring()
                                    } else {
                                        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                                            dragOffset = .zero
                                        }
                                    }
                                }
                        )
                }

                overlayContent()

                Spacer()
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private func dismissWithSpring() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            isDismissing = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            onDismiss()
        }
    }
}

// MARK: - 4. 弹性微缩与超调触觉反馈 (Press Scale & Spring Overshoot)

/// 矩形 / 卡片物理弹性按钮样式（带 0.96 深度内阴影与 1.02 -> 1.0 释放超调）。
public struct PressScaleOvershootButtonStyle: ButtonStyle {
    public var scale: CGFloat = 0.96
    public var cornerRadius: CGFloat = 16
    public var enableHaptics: Bool = true

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    public init(scale: CGFloat = 0.96, cornerRadius: CGFloat = 16, enableHaptics: Bool = true) {
        self.scale = scale
        self.cornerRadius = cornerRadius
        self.enableHaptics = enableHaptics
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    accent.opacity(scheme == .dark ? 0.45 : 0.35),
                                    accent.opacity(scheme == .dark ? 0.20 : 0.12),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2.0
                        )
                        .blur(radius: 0.8)
                        .allowsHitTesting(false)
                }
            }
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.10)
                    : .spring(response: 0.28, dampingFraction: 0.58), // 释放瞬间 1.02 超调归位
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                guard enableHaptics else { return }
                if isPressed {
                    Haptics.impact(.rigid)
                } else {
                    Haptics.impact(.light)
                }
            }
    }
}

/// 胶囊形态物理弹性按钮样式（用于输入框上方胶囊与 Tab 项）。
public struct PressScaleOvershootCapsuleButtonStyle: ButtonStyle {
    public var scale: CGFloat = 0.96
    public var enableHaptics: Bool = true

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    public init(scale: CGFloat = 0.96, enableHaptics: Bool = true) {
        self.scale = scale
        self.enableHaptics = enableHaptics
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .overlay {
                if configuration.isPressed {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    accent.opacity(scheme == .dark ? 0.45 : 0.35),
                                    accent.opacity(scheme == .dark ? 0.20 : 0.12),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2.0
                        )
                        .blur(radius: 0.8)
                        .allowsHitTesting(false)
                }
            }
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.10)
                    : .spring(response: 0.28, dampingFraction: 0.58),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                guard enableHaptics else { return }
                if isPressed {
                    Haptics.impact(.rigid)
                } else {
                    Haptics.impact(.light)
                }
            }
    }
}

/// 圆形物理弹性按钮样式（用于顶栏圆钮、语音圆钮与发送圆钮）。
public struct PressScaleOvershootCircleButtonStyle: ButtonStyle {
    public var scale: CGFloat = 0.94
    public var enableHaptics: Bool = true

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    public init(scale: CGFloat = 0.94, enableHaptics: Bool = true) {
        self.scale = scale
        self.enableHaptics = enableHaptics
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .overlay {
                if configuration.isPressed {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    accent.opacity(scheme == .dark ? 0.45 : 0.35),
                                    accent.opacity(scheme == .dark ? 0.20 : 0.12),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2.0
                        )
                        .blur(radius: 0.8)
                        .allowsHitTesting(false)
                }
            }
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.10)
                    : .spring(response: 0.28, dampingFraction: 0.58),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                guard enableHaptics else { return }
                if isPressed {
                    Haptics.impact(.rigid)
                } else {
                    Haptics.impact(.light)
                }
            }
    }
}

extension View {
    /// 添加弹性微缩与超调触觉反馈（按压 0.96 + 主题色内阴影，释放 1.02 超调）。
    public func pressScaleOvershoot(scale: CGFloat = 0.96, cornerRadius: CGFloat = 16) -> some View {
        buttonStyle(PressScaleOvershootButtonStyle(scale: scale, cornerRadius: cornerRadius))
    }

    /// 胶囊形态弹性微缩与超调触觉反馈。
    public func pressScaleOvershootCapsule(scale: CGFloat = 0.96) -> some View {
        buttonStyle(PressScaleOvershootCapsuleButtonStyle(scale: scale))
    }

    /// 圆形形态弹性微缩与超调触觉反馈。
    public func pressScaleOvershootCircle(scale: CGFloat = 0.94) -> some View {
        buttonStyle(PressScaleOvershootCircleButtonStyle(scale: scale))
    }
}

// MARK: - 5. 阻尼弹性速度吸附抽屉 (Velocity-Snapping Bottom Sheet)

/// 支持上下拖拽边缘阻尼拉伸（0.35 延伸系数）与初速度瞬时吸附判定的底部抽屉。
public struct VelocitySnappingDrawer<Content: View>: View {
    @Binding public var isPresented: Bool
    public var minHeight: CGFloat = 180
    public var maxHeight: CGFloat = 460
    @ViewBuilder public let content: () -> Content

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    @State private var currentHeight: CGFloat = 340
    @State private var dragTranslationY: CGFloat = 0

    public init(
        isPresented: Binding<Bool>,
        minHeight: CGFloat = 180,
        maxHeight: CGFloat = 460,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.content = content
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                (scheme == .dark ? Color(red: 0.05, green: 0.04, blue: 0.09) : accent)
                    .opacity(scheme == .dark ? 0.48 : 0.18)
                    .ignoresSafeArea()
                    .onTapGesture { closeWithSpring() }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    // 抽屉抓握条
                    Capsule(style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.30) : accent.opacity(0.25))
                        .frame(width: 42, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    content()
                        .frame(maxWidth: .infinity)
                }
                .frame(height: effectiveHeight)
                .liquidGlass(.regular.interactive(), in: .rect(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(scheme == .dark ? 0.50 : 0.85),
                                    accent.opacity(scheme == .dark ? 0.35 : 0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                        .allowsHitTesting(false)
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.50 : 0.12), radius: 26, y: -6)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragTranslationY = value.translation.height
                        }
                        .onEnded { value in
                            let velocityY = value.velocity.height
                            let predictedY = value.predictedEndTranslation.height
                            // 综合瞬时速度与预测最终位置进行干脆利落的吸附
                            let targetHeight = currentHeight - dragTranslationY - velocityY * 0.18
                            dragTranslationY = 0

                            if velocityY > 600 || predictedY > 200 || targetHeight < minHeight * 0.85 {
                                closeWithSpring()
                            } else {
                                let snapped = min(max(targetHeight, minHeight), maxHeight)
                                withAnimation(.spring(response: 0.36, dampingFraction: 0.80)) {
                                    currentHeight = snapped
                                }
                            }
                        }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isPresented)
    }

    /// 应用 0.35 橡皮筋阻尼拉伸公式计算高度。
    private var effectiveHeight: CGFloat {
        let raw = currentHeight - dragTranslationY
        let stretchFactor: CGFloat = 0.35
        if raw > maxHeight {
            let over = raw - maxHeight
            return maxHeight + (1.0 - (1.0 / (over * 0.006 * stretchFactor + 1.0))) * 64.0
        } else if raw < minHeight {
            let under = minHeight - raw
            return minHeight - (1.0 - (1.0 / (under * 0.006 * stretchFactor + 1.0))) * 64.0
        }
        return max(raw, 0)
    }

    private func closeWithSpring() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            isPresented = false
        }
    }
}
