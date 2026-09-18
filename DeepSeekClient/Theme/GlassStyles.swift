import SwiftUI

// MARK: - 液态玻璃封装
//
// iOS 26 起使用原生 `glassEffect`；更低版本自动回退为材质背景，
// 保证同一份视图代码在旧系统上依然可用。

extension View {

    /// 原生液态玻璃效果（自动降级）。
    @ViewBuilder
    func liquidGlass<S: Shape>(_ glass: Glass, in shape: S) -> some View {
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

    /// 胶囊形态玻璃。
    @ViewBuilder
    func liquidGlassCapsule(_ glass: Glass = .regular) -> some View {
        self.liquidGlass(glass, in: .capsule)
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

    /// 兼容旧系统的极简玻璃描边（用于胶囊）。
    func capsuleHairline(opacity: Double = 0.16) -> some View {
        self.overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(opacity), lineWidth: 0.8)
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
                    .fill(AppColor.brandIndigo.opacity(scheme == .dark ? 0.42 : 0.30) * intensity)
                    .frame(width: size.width * 0.95, height: size.width * 0.95)
                    .blur(radius: 120)
                    .offset(
                        x: -size.width * 0.22 + CGFloat(drift) * 26,
                        y: -size.height * 0.26 + CGFloat(drift) * 18
                    )

                Circle()
                    .fill(AppColor.brandPurple.opacity(scheme == .dark ? 0.36 : 0.24) * intensity)
                    .frame(width: size.width * 0.85, height: size.width * 0.85)
                    .blur(radius: 130)
                    .offset(
                        x: size.width * 0.30 - CGFloat(drift) * 20,
                        y: size.height * 0.22 + CGFloat(drift) * 22
                    )

                Circle()
                    .fill(AppColor.brandTeal.opacity(scheme == .dark ? 0.22 : 0.16) * intensity)
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
                ? [Color(red: 0.05, green: 0.06, blue: 0.12),
                   Color(red: 0.07, green: 0.08, blue: 0.16),
                   Color(red: 0.04, green: 0.05, blue: 0.10)]
                : [Color(red: 0.96, green: 0.97, blue: 1.00),
                   Color(red: 0.95, green: 0.96, blue: 0.99),
                   Color(red: 0.98, green: 0.97, blue: 0.99)],
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
