import SwiftUI

// MARK: - 液态玻璃封装
//
// iOS 26 起使用原生 `glassEffect`；更低版本自动回退为材质背景，
// 保证同一份视图代码在旧系统上依然可用。

extension View {

    /// 原生液态玻璃按钮底：iOS 26 `glassEffect` 的 interactive 变体。
    ///
    /// 用户的诉求是「按键要有 iOS 26 那种真的液态玻璃」——所以这里直接用系统
    /// `glassEffect`，不再自绘渐变、光晕或折射描边。`.interactive()` 让玻璃在
    /// 点按时产生系统自带的形变与高光，这是手写阴影永远做不出来的。
    @ViewBuilder
    func nativeGlass<S: Shape>(
        _ shape: S,
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// 圆形玻璃按钮底（头像、返回、更多）。
    @ViewBuilder
    func nativeGlassCircle(size: CGFloat? = nil, tint: Color? = nil) -> some View {
        if let size {
            self.frame(width: size, height: size).nativeGlass(.circle, tint: tint)
        } else {
            self.nativeGlass(.circle, tint: tint)
        }
    }

    /// 圆角矩形玻璃底（输入框、标签、卡片）。
    @ViewBuilder
    func nativeGlassRect(cornerRadius: CGFloat = AppUI.controlRadius, tint: Color? = nil, interactive: Bool = true) -> some View {
        self.nativeGlass(.rect(cornerRadius: cornerRadius), tint: tint, interactive: interactive)
    }

    /// 原生液态玻璃效果（自动降级）。
    @ViewBuilder
    func liquidGlass<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(glass, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// 常规玻璃卡片。
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat = AppSpacing.cardCorner) -> some View {
        self.liquidGlass(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// 次要表面：更通透的 clear 变体，避免玻璃叠加过重。
    @ViewBuilder
    func liquidGlassClear(cornerRadius: CGFloat = AppSpacing.cardCorner) -> some View {
        self.liquidGlass(.clear, in: .rect(cornerRadius: cornerRadius))
    }

    /// 加一层极淡的描边，让玻璃边缘在浅色背景下依然清晰。
    func glassHairline(cornerRadius: CGFloat = AppSpacing.cardCorner, opacity: Double = 0.18) -> some View {
        self.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(opacity), Color.white.opacity(opacity * 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
    }

}

// MARK: - 动态背景

/// 缓慢流动的光晕背景：引导页与语音模式共用。
/// 颜色随深色 / 浅色模式自动调整，光点做极缓慢漂浮。
struct AuroraBackground: View {

    var intensity: Double = 1.0
    var showsParticles: Bool = true

    @Environment(\.colorScheme) private var scheme
    @State private var drift: Double = 0
    @State private var particlePhase: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                baseGradient

                Circle()
                    .fill(AppColor.brandIndigo.opacity((scheme == .dark ? 0.42 : 0.30) * intensity))
                    .frame(width: size.width * 0.95, height: size.width * 0.95)
                    .blur(radius: 120)
                    .offset(
                        x: -size.width * 0.22 + CGFloat(drift) * 26,
                        y: -size.height * 0.26 + CGFloat(drift) * 18
                    )

                Circle()
                    .fill(AppColor.brandPurple.opacity((scheme == .dark ? 0.36 : 0.24) * intensity))
                    .frame(width: size.width * 0.85, height: size.width * 0.85)
                    .blur(radius: 130)
                    .offset(
                        x: size.width * 0.30 - CGFloat(drift) * 20,
                        y: size.height * 0.22 + CGFloat(drift) * 22
                    )

                Circle()
                    .fill(AppColor.brandTeal.opacity((scheme == .dark ? 0.22 : 0.16) * intensity))
                    .frame(width: size.width * 0.7, height: size.width * 0.7)
                    .blur(radius: 110)
                    .offset(
                        x: -size.width * 0.28,
                        y: size.height * 0.34 - CGFloat(drift) * 16
                    )

                if showsParticles {
                    particleLayer(in: size)
                }
            }
            .compositingGroup()
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                    drift = 1
                }
                withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                    particlePhase = 1
                }
            }
        }
    }

    private var baseGradient: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(hex: "120D1D"), Color(hex: "1A122B"), Color(hex: "120D1D")]
                : [Color.white, Color(hex: "F8F6FD"), Color.white],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func particleLayer(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            for index in 0..<26 {
                let seed = Double(index) * 0.618
                let baseX = (seed.truncatingRemainder(dividingBy: 1.0)) * canvasSize.width
                let baseY = (seed * 1.7).truncatingRemainder(dividingBy: 1.0) * canvasSize.height
                let rise = particlePhase * (18 + Double(index % 5) * 9)
                let radius = 1.0 + Double(index % 4) * 0.9

                var y = baseY - rise
                while y < -10 { y += canvasSize.height + 20 }

                let opacity = 0.10 + Double(index % 3) * 0.06
                let rect = CGRect(x: baseX, y: y, width: radius * 2, height: radius * 2)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(scheme == .dark
                                 ? Color.white.opacity(opacity)
                                 : AppColor.brandIndigo.opacity(opacity * 0.9))
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .blendMode(scheme == .dark ? .plusLighter : .normal)
        .allowsHitTesting(false)
    }
}

// MARK: - 原生液态玻璃容器编组 (GlassEffectContainer)

/// 编组多个液态玻璃元素的容器，在 iOS 26+ 上统一焦散与折射。
public struct GlassContainer<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26.0, *) {
            if let spacing {
                GlassEffectContainer(spacing: spacing) {
                    content
                }
            } else {
                GlassEffectContainer {
                    content
                }
            }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    public func inGlassContainer(spacing: CGFloat? = nil) -> some View {
        GlassContainer(spacing: spacing) {
            self
        }
    }
}
