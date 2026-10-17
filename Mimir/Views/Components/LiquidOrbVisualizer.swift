import SwiftUI

/// 3D 超流体声波共振核心（LiquidOrbVisualizer）。
///
/// 遵循 Apple Design Award 视觉与图像类最高设计标准：
/// - **深色形态（核心交互态）**：中央为 3D 虹彩超流体玻璃悬浮球（Liquid Glass Sphere），
///   表面缠绕液态金属（水银/铬）扭转反光条，外覆多重行星微光星轨与浮动发光粒子，
///   并由音频输入功率驱动呼吸形变与同心扩散光环。
/// - **浅色/转写形态**：中央为 3D 梦幻流体动态声波丝带（Iridescent Wave Ribbon）与音频时间轴量规。
public struct LiquidOrbVisualizer: View {

    /// 视觉形态模式：.duplexSphere（深色 3D 玻璃球）或 .transcriptRibbon（浅色流体丝带）
    public enum VisualMode: Sendable {
        case duplexSphere
        case transcriptRibbon
    }

    public var mode: VisualMode = .duplexSphere
    public var inputLevel: Double = 0.0
    public var outputLevel: Double = 0.0
    public var isSpeaking: Bool = false
    public var diameter: CGFloat = 200

    @Environment(\.colorScheme) private var scheme

    // 核心动画状态
    @State private var phase: Double = 0
    @State private var pulsePhase: Double = 0

    // 核心色彩令牌
    private let irisViolet = Color(hex: "7D52F4")
    private let electricViolet = Color(hex: "9B70FF")
    private let deepPlum = Color(hex: "120D1D")
    private let cyanRefraction = Color(hex: "68E1FD")
    private let magentaFresnel = Color(hex: "F86ECE")

    public init(
        mode: VisualMode = .duplexSphere,
        inputLevel: Double = 0.0,
        outputLevel: Double = 0.0,
        isSpeaking: Bool = false,
        diameter: CGFloat = 200
    ) {
        self.mode = mode
        self.inputLevel = inputLevel
        self.outputLevel = outputLevel
        self.isSpeaking = isSpeaking
        self.diameter = diameter
    }

    private var reactiveLevel: Double {
        max(inputLevel, outputLevel)
    }

    public var body: some View {
        Group {
            if mode == .duplexSphere {
                duplexSphereView
            } else {
                transcriptRibbonView
            }
        }
    }

    // MARK: - 1. 深色形态：3D 虹彩超流体玻璃悬浮球 (Liquid Glass Sphere)

    private var duplexSphereView: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let dynamicScale = 1.0 + min(reactiveLevel, 1.0) * 0.09 + sin(time * 1.8) * 0.015

            ZStack {
                // ① 背景宏观空间焦散光晕与声波涟漪
                ambientCausticGlow(time: time)
                audioReactiveShockwaves(time: time)

                // ② 外层行星微光星轨（倾斜环绕立体轨道）
                planetaryOrbitTracks(time: time)

                // ③ 3D 浮动发光微粒星尘群（位于球体后方的半数粒子）
                stardustParticles(time: time, inFront: false)

                // ④ 核心 3D 超流体晶体玻璃球体（含菲涅尔彩虹边缘与水银扭转反光条）
                liquidGlassOrbCore(time: time)
                    .scaleEffect(dynamicScale)

                // ⑤ 3D 浮动发光微粒星尘群（位于球体前方的近景粒子）
                stardustParticles(time: time, inFront: true)
            }
            .frame(width: diameter * 1.6, height: diameter * 1.5)
            .compositingGroup()
        }
    }

    // MARK: - 背景空间焦散与光晕

    private func ambientCausticGlow(time: Double) -> some View {
        ZStack {
            // 深邃紫夜核心光晕
            RadialGradient(
                colors: [
                    irisViolet.opacity(0.40 + min(reactiveLevel, 1.0) * 0.25),
                    electricViolet.opacity(0.18),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: diameter * 0.85
            )
            .frame(width: diameter * 1.7, height: diameter * 1.7)
            .blur(radius: 20)

            // 次级彩虹光晕环
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            irisViolet.opacity(0.35),
                            cyanRefraction.opacity(0.25),
                            magentaFresnel.opacity(0.30),
                            irisViolet.opacity(0.35)
                        ],
                        center: .center,
                        angle: .degrees(time * 15)
                    ),
                    lineWidth: 18
                )
                .frame(width: diameter * 1.15, height: diameter * 1.15)
                .blur(radius: 14)
        }
    }

    // MARK: - 音频驱动声波外向扩散涟漪

    private func audioReactiveShockwaves(time: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let offset = Double(index) * 0.33
                let progress = (time * 0.6 + offset).truncatingRemainder(dividingBy: 1.0)
                let waveScale = 0.85 + progress * 0.65
                let opacity = (1.0 - progress) * (0.28 + min(reactiveLevel, 1.0) * 0.45)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                irisViolet.opacity(opacity * 0.8),
                                electricViolet.opacity(opacity * 0.4),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(0.8, (1.0 - progress) * 2.2)
                    )
                    .frame(width: diameter * waveScale, height: diameter * waveScale)
                    .scaleEffect(y: 0.94) // 轻微椭圆透视
            }
        }
    }

    // MARK: - 行星微光星轨（多重倾斜环绕椭圆轨道）

    private func planetaryOrbitTracks(time: Double) -> some View {
        ZStack {
            // 主倾斜轨道环 1
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            electricViolet.opacity(0.45),
                            irisViolet.opacity(0.15),
                            Color.white.opacity(0.40)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .frame(width: diameter * 1.55, height: diameter * 0.85)
                .rotationEffect(.degrees(-24))
                .shadow(color: electricViolet.opacity(0.45), radius: 8)

            // 次级轨道环 2
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            cyanRefraction.opacity(0.45),
                            magentaFresnel.opacity(0.35),
                            Color.white.opacity(0.20),
                            irisViolet.opacity(0.35)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 0.9
                )
                .frame(width: diameter * 1.42, height: diameter * 0.72)
                .rotationEffect(.degrees(-18 + sin(time * 0.4) * 3))

            // 细致外星环 3
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.clear,
                            electricViolet.opacity(0.30)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 0.7, dash: [4, 6])
                )
                .frame(width: diameter * 1.68, height: diameter * 0.92)
                .rotationEffect(.degrees(-28))
        }
        .allowsHitTesting(false)
    }

    // MARK: - 3D 浮动发光微粒星尘群

    private func stardustParticles(time: Double, inFront: Bool) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let particleCount = 38

            for i in 0..<particleCount {
                let seed = Double(i) * 1.618
                let speed = 0.22 + (Double(i % 5) * 0.04)
                let angle = (time * speed + seed).truncatingRemainder(dividingBy: .pi * 2)

                let orbitA = (diameter * 0.62) + Double(i % 7) * 14.0
                let orbitB = (diameter * 0.35) + Double(i % 4) * 8.0

                // 3D 椭圆轨道旋转 -24°
                let tiltRad = -24.0 * .pi / 180.0
                let rawX = cos(angle) * orbitA
                let rawY = sin(angle) * orbitB
                let z = sin(angle) // z > 0 为前方，z < 0 为后方

                let isParticleInFront = z >= 0
                guard isParticleInFront == inFront else { continue }

                let rotX = rawX * cos(tiltRad) - rawY * sin(tiltRad)
                let rotY = rawX * sin(tiltRad) + rawY * cos(tiltRad)

                let pt = CGPoint(x: center.x + rotX, y: center.y + rotY)

                // 闪烁亮度与大小
                let twinkle = 0.45 + 0.55 * sin(time * 3.5 + seed * 2.0)
                let baseRadius = (1.2 + Double(i % 3) * 0.9) * (isParticleInFront ? 1.15 : 0.8)
                let radius = baseRadius * (0.8 + twinkle * 0.4)

                let dotColor: Color = (i % 3 == 0)
                    ? Color.white.opacity(0.85 * twinkle)
                    : ((i % 3 == 1) ? cyanRefraction.opacity(0.75 * twinkle) : electricViolet.opacity(0.80 * twinkle))

                let rect = CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(dotColor))

                // 高亮星芒光晕
                if i % 4 == 0 && isParticleInFront {
                    let glowRect = CGRect(x: pt.x - radius * 2.4, y: pt.y - radius * 2.4, width: radius * 4.8, height: radius * 4.8)
                    context.fill(Path(ellipseIn: glowRect), with: .color(dotColor.opacity(0.25)))
                }
            }
        }
        .frame(width: diameter * 1.6, height: diameter * 1.5)
        .allowsHitTesting(false)
    }

    // MARK: - 3D 超流体晶体玻璃球体核心

    private func liquidGlassOrbCore(time: Double) -> some View {
        ZStack {
            // ① 球体内部体积基底 (Deep Spherical Volume)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "5A28A8"),
                            Color(hex: "34136B"),
                            Color(hex: "180936"),
                            Color(hex: "0D041D")
                        ],
                        center: UnitPoint(x: 0.38, y: 0.35),
                        startRadius: 10,
                        endRadius: diameter * 0.55
                    )
                )
                .frame(width: diameter, height: diameter)

            // ② 核心内部共振光团 (Inner Resonant Pulse)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            irisViolet.opacity(0.65 + min(reactiveLevel, 1.0) * 0.30),
                            electricViolet.opacity(0.35),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.55, y: 0.52),
                        startRadius: 5,
                        endRadius: diameter * 0.42
                    )
                )
                .frame(width: diameter * 0.85, height: diameter * 0.85)
                .blur(radius: 12)

            // ③ 3D 液态金属扭转环绕反光条 (Liquid Chrome Ribbon)
            liquidMetalChromeRibbon(time: time)
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())

            // ④ 薄膜干涉彩虹光晕与菲涅尔边缘 (Thin-film Iridescence & Fresnel Rim)
            Circle()
                .strokeBorder(
                    AngularGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.95), location: 0.08),
                            .init(color: cyanRefraction.opacity(0.85), location: 0.22),
                            .init(color: electricViolet.opacity(0.90), location: 0.45),
                            .init(color: magentaFresnel.opacity(0.80), location: 0.65),
                            .init(color: Color.white.opacity(0.70), location: 0.88),
                            .init(color: Color.white.opacity(0.95), location: 1.0)
                        ],
                        center: .center,
                        angle: .degrees(-45 + sin(time * 0.3) * 15)
                    ),
                    lineWidth: 3.2
                )
                .frame(width: diameter, height: diameter)

            // ⑤ 内阴影营造厚度玻璃折射 (Glass Depth Inner Refraction)
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.75),
                            Color.clear,
                            Color(hex: "120D1D").opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 6
                )
                .frame(width: diameter, height: diameter)

            // ⑥ 顶部主高光月牙弧 (Key Glass Specular Highlight)
            glassKeySpecularHighlight
                .frame(width: diameter, height: diameter)

            // ⑦ 底部次级环境反弹光弧 (Bounce Rim Highlight)
            glassBottomBounceHighlight
                .frame(width: diameter, height: diameter)
        }
        .shadow(color: irisViolet.opacity(0.55 + min(reactiveLevel, 1.0) * 0.35), radius: 32, x: 0, y: 10)
    }

    // MARK: - 3D 液态金属扭转反光条 (Liquid Chrome Ribbon)

    private func liquidMetalChromeRibbon(time: Double) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // 动态起伏偏移
            let wobble = sin(time * 1.5) * 4.0
            let wobble2 = cos(time * 1.2) * 5.0

            // 主液态金属带路径（类似无限符号 ∞ 与流体缠绕的优雅 S 曲线）
            var path = Path()
            path.move(to: CGPoint(x: w * 0.18, y: h * 0.52 + wobble))
            path.addCurve(
                to: CGPoint(x: w * 0.55, y: h * 0.28 + wobble2),
                control1: CGPoint(x: w * 0.24, y: h * 0.30),
                control2: CGPoint(x: w * 0.40, y: h * 0.22)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.82, y: h * 0.48 - wobble),
                control1: CGPoint(x: w * 0.70, y: h * 0.34),
                control2: CGPoint(x: w * 0.80, y: h * 0.38)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.46, y: h * 0.78 + wobble),
                control1: CGPoint(x: w * 0.85, y: h * 0.65),
                control2: CGPoint(x: w * 0.65, y: h * 0.82)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.18, y: h * 0.52 + wobble),
                control1: CGPoint(x: w * 0.32, y: h * 0.74),
                control2: CGPoint(x: w * 0.12, y: h * 0.64)
            )

            // 1. 投影层（投射到玻璃球内胆）
            context.drawLayer { ctx in
                ctx.addFilter(.blur(radius: 7))
                ctx.stroke(
                    path,
                    with: .color(Color(hex: "0B0318").opacity(0.85)),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
                )
            }

            // 2. 金属底层铬银质感
            let chromeGrad = Gradient(colors: [
                Color(hex: "2A1B46"),
                Color(hex: "B2BDDF"),
                Color.white,
                Color(hex: "8590B5"),
                Color(hex: "23133D"),
                Color(hex: "CCD4F0")
            ])
            context.stroke(
                path,
                with: .linearGradient(
                    chromeGrad,
                    startPoint: CGPoint(x: w * 0.15, y: h * 0.2),
                    endPoint: CGPoint(x: w * 0.85, y: h * 0.8)
                ),
                style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round)
            )

            // 3. 高光棱线（镜面反射极光白）
            let ridgeGrad = Gradient(colors: [
                Color.white.opacity(0.2),
                Color.white.opacity(0.95),
                Color(hex: "A3E5FF").opacity(0.9),
                Color.white.opacity(0.95),
                Color.white.opacity(0.3)
            ])
            context.stroke(
                path,
                with: .linearGradient(
                    ridgeGrad,
                    startPoint: CGPoint(x: w * 0.25, y: h * 0.25),
                    endPoint: CGPoint(x: w * 0.75, y: h * 0.75)
                ),
                style: StrokeStyle(lineWidth: 3.8, lineCap: .round, lineJoin: .round)
            )

            // 4. 第二条交叉微带（增强丰富度）
            var crossPath = Path()
            crossPath.move(to: CGPoint(x: w * 0.30, y: h * 0.32 + wobble2))
            crossPath.addCurve(
                to: CGPoint(x: w * 0.72, y: h * 0.68 - wobble),
                control1: CGPoint(x: w * 0.45, y: h * 0.42),
                control2: CGPoint(x: w * 0.58, y: h * 0.58)
            )
            context.stroke(
                crossPath,
                with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.85), Color(hex: "C2CDED"), Color.white.opacity(0.6)]),
                    startPoint: CGPoint(x: w * 0.30, y: h * 0.32),
                    endPoint: CGPoint(x: w * 0.72, y: h * 0.68)
                ),
                style: StrokeStyle(lineWidth: 5.5, lineCap: .round)
            )
        }
    }

    // MARK: - 玻璃高光弧与反弹光

    private var glassKeySpecularHighlight: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            var path = Path()
            path.addArc(
                center: CGPoint(x: w * 0.48, y: h * 0.46),
                radius: w * 0.43,
                startAngle: .degrees(-135),
                endAngle: .degrees(-50),
                clockwise: false
            )

            let specGrad = Gradient(colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.88),
                Color.white.opacity(0.95),
                Color.white.opacity(0.1)
            ])

            context.stroke(
                path,
                with: .linearGradient(
                    specGrad,
                    startPoint: CGPoint(x: w * 0.2, y: h * 0.15),
                    endPoint: CGPoint(x: w * 0.7, y: h * 0.35)
                ),
                style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
            )
        }
    }

    private var glassBottomBounceHighlight: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            var path = Path()
            path.addArc(
                center: CGPoint(x: w * 0.50, y: h * 0.52),
                radius: w * 0.45,
                startAngle: .degrees(35),
                endAngle: .degrees(110),
                clockwise: false
            )

            let bounceGrad = Gradient(colors: [
                cyanRefraction.opacity(0.0),
                cyanRefraction.opacity(0.65),
                electricViolet.opacity(0.75),
                Color.clear
            ])

            context.stroke(
                path,
                with: .linearGradient(
                    bounceGrad,
                    startPoint: CGPoint(x: w * 0.6, y: h * 0.75),
                    endPoint: CGPoint(x: w * 0.3, y: h * 0.95)
                ),
                style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
            )
        }
    }

    // MARK: - 2. 浅色/转写形态：3D 梦幻流体动态声波丝带 (Iridescent Wave Ribbon)

    private var transcriptRibbonView: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            VStack(spacing: 14) {
                ZStack {
                    // 柔和虹彩漫射背光
                    RadialGradient(
                        colors: [
                            irisViolet.opacity(0.20 + min(reactiveLevel, 1.0) * 0.18),
                            cyanRefraction.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: diameter * 0.95
                    )
                    .frame(height: 180)
                    .blur(radius: 20)

                    // 多层流体声波丝带（Canvas 绘制 3 层重叠半透明贝塞尔曲面）
                    fluidWaveRibbonCanvas(time: time)
                        .frame(height: 160)

                    // 丝带周围飞舞的微光火花粒子
                    ribbonSparkles(time: time)
                        .frame(height: 160)
                }

                // 音频时间轴刻度量规（参考图 2）
                timelineRuler(time: time)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func fluidWaveRibbonCanvas(time: Double) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let midY = h * 0.50
            let amp = 24.0 + min(reactiveLevel, 1.0) * 38.0

            // 绘制 3 条流体交织波带
            for layer in 0..<3 {
                let speed = 1.6 + Double(layer) * 0.35
                let phaseShift = time * speed + Double(layer) * 1.8
                let layerAmp = amp * (1.0 - Double(layer) * 0.18)

                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))

                let steps = 48
                for s in 0...steps {
                    let progress = Double(s) / Double(steps)
                    let x = progress * w
                    let envelope = sin(progress * .pi) // 两端收窄，中间隆起

                    let wave1 = sin(progress * .pi * 3.2 + phaseShift) * layerAmp * envelope
                    let wave2 = cos(progress * .pi * 2.0 - phaseShift * 0.8) * (layerAmp * 0.4) * envelope
                    let y = midY + wave1 + wave2

                    if s == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                // 闭合到底部做半透明流体渐变填充
                var fillPath = path
                fillPath.addLine(to: CGPoint(x: w, y: h * 0.85))
                fillPath.addLine(to: CGPoint(x: 0, y: h * 0.85))
                fillPath.closeSubpath()

                let fillColors: [Color] = layer == 0
                    ? [irisViolet.opacity(0.35), magentaFresnel.opacity(0.25), cyanRefraction.opacity(0.15)]
                    : (layer == 1
                        ? [cyanRefraction.opacity(0.30), electricViolet.opacity(0.20), Color.clear]
                        : [magentaFresnel.opacity(0.25), irisViolet.opacity(0.18), Color.clear])

                context.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: fillColors),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: w, y: h)
                    )
                )

                // 丝带主边缘流动描边（高光焦散线）
                let strokeGrad = Gradient(colors: [
                    cyanRefraction.opacity(0.7),
                    Color.white.opacity(0.95),
                    electricViolet.opacity(0.85),
                    magentaFresnel.opacity(0.75),
                    Color.white.opacity(0.6)
                ])
                context.stroke(
                    path,
                    with: .linearGradient(
                        strokeGrad,
                        startPoint: CGPoint(x: 0, y: midY - amp),
                        endPoint: CGPoint(x: w, y: midY + amp)
                    ),
                    style: StrokeStyle(lineWidth: layer == 0 ? 3.0 : 1.8, lineCap: .round)
                )
            }
        }
    }

    private func ribbonSparkles(time: Double) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            for i in 0..<18 {
                let seed = Double(i) * 2.13
                let prog = (sin(time * 0.8 + seed) * 0.5 + 0.5)
                let x = w * (0.2 + 0.6 * prog)
                let y = (h * 0.5) + cos(time * 1.5 + seed) * 42.0

                let radius = 1.2 + sin(time * 4.0 + seed) * 0.8
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.75)))
            }
        }
    }

    // MARK: - 音频时间轴量规（Timeline Ruler）

    private func timelineRuler(time: Double) -> some View {
        VStack(spacing: 4) {
            // 刻度线
            HStack(spacing: 5) {
                ForEach(0..<36, id: \.self) { index in
                    Rectangle()
                        .fill(index == 18 ? irisViolet : Color.primary.opacity(index % 6 == 0 ? 0.35 : 0.15))
                        .frame(width: index == 18 ? 2 : 1, height: index == 18 ? 12 : (index % 6 == 0 ? 8 : 4))
                }
            }
            .frame(height: 14)

            // 时间戳标注：00:03 | 00:04 (加粗高亮) | 00:05
            HStack {
                Text("00:03")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.6))
                Spacer()
                Text("00:04")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(irisViolet)
                Spacer()
                Text("00:05")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 48)
        }
        .padding(.horizontal, 24)
    }
}
