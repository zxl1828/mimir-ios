import SwiftUI
import UIKit

/// Mimir 的形象「米米」：悬浮在全息液态玻璃球中的赛博猫头鹰（Cyber-Owl）。
///
/// 纯 `Canvas` 矢量绘制（设计稿 100 × 100），任意尺寸都清晰，并自动适配浅色与深色模式：
/// - `.calm`：2.2s 紫色呼吸光晕 + 双倾斜星轨逆向旋转 + 眨眼，空对话页与侧栏使用
/// - `.thinking`：星轨加速 + 头顶浮起脉冲思考星尘，生成 / 思考时使用
/// - `.happy`：月牙笑眼 + 四角星闪光，引导页连接成功等场景使用
struct MimirMascot: View {

    enum Mood {
        case calm
        case thinking
        case happy
    }

    var size: CGFloat = 96
    var mood: Mood = .calm
    var animated: Bool = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { timeline in
            Canvas { context, canvasSize in
                let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                MimirOwlRenderer.draw(
                    in: &context,
                    size: canvasSize,
                    mood: mood,
                    time: time,
                    scheme: scheme,
                    accent: accent
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 纯绘制逻辑，与视图状态解耦。
private enum MimirOwlRenderer {

    /// 设计稿为 100 × 100 的方形。
    private static let design: CGFloat = 100

    static func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        mood: MimirMascot.Mood,
        time: TimeInterval,
        scheme: ColorScheme,
        accent: Color
    ) {
        let scale = min(size.width, size.height) / design
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale, y: y * scale)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
        }

        let isDark = scheme == .dark
        let neon = AppUI.neonViolet
        let deep = AppUI.deepViolet

        // 呼吸周期 2.2s：0...1
        let breath = 0.5 + 0.5 * sin(time * 2 * .pi / 2.2)
        let bob = CGFloat(sin(time * 1.15)) * (mood == .thinking ? 1.1 : 1.6)
        let center = pt(50, 50 + bob * 0.45)
        let speedMultiplier: Double = mood == .thinking ? 1.75 : 1.0

        // MARK: 1. 柔和呼吸光晕（深浅色自适应透明度）
        let glowRadius = (43 + breath * 5) * scale
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 10 * scale))
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - glowRadius,
                    y: center.y - glowRadius,
                    width: glowRadius * 2,
                    height: glowRadius * 2
                )),
                with: .color(accent.opacity((isDark ? 0.22 : 0.16) + 0.14 * breath))
            )
        }

        // MARK: 2. 后半圈双倾斜星轨（穿插在玻璃球后方）
        let orbitColor1 = isDark ? neon.opacity(0.72) : accent.opacity(0.68)
        let orbitColor2 = isDark ? accent.opacity(0.52) : deep.opacity(0.48)

        drawOrbitHalf(
            in: &context,
            center: CGPoint(x: center.x, y: center.y + 1.2 * scale),
            scale: scale,
            radiusX: 44.5,
            radiusY: 14.5,
            tiltDegrees: -22,
            frontHalf: false,
            color: orbitColor1,
            lineWidth: 1.35,
            dotAngles: [time * 24 * speedMultiplier + 210, time * 24 * speedMultiplier + 330]
        )
        drawOrbitHalf(
            in: &context,
            center: CGPoint(x: center.x, y: center.y + 1.2 * scale),
            scale: scale,
            radiusX: 40.0,
            radiusY: 12.2,
            tiltDegrees: 19,
            frontHalf: false,
            color: orbitColor2,
            lineWidth: 1.05,
            dotAngles: [-time * 18 * speedMultiplier + 255]
        )

        // MARK: 3. 全息液态玻璃球底层（浅色模式下加深球胆紫度，确保猫头鹰高对比清晰）
        let sphereRect = rect(20.5, 20.5 + bob * 0.45, 59, 59)
        let sphere = Path(ellipseIn: sphereRect)
        context.fill(
            sphere,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(isDark ? 0.24 : 0.36), location: 0.0),
                    .init(color: accent.opacity(isDark ? 0.36 : 0.58), location: 0.45),
                    .init(color: deep.opacity(isDark ? 0.78 : 0.88), location: 1.0)
                ]),
                center: pt(41, 36 + bob * 0.45),
                startRadius: 2 * scale,
                endRadius: 36 * scale
            )
        )

        // 球体右下方紫罗兰内折射柔光
        context.drawLayer { layer in
            layer.clip(to: sphere)
            layer.addFilter(.blur(radius: 5 * scale))
            layer.fill(
                Path(ellipseIn: rect(38, 44 + bob * 0.45, 38, 34)),
                with: .color(neon.opacity(isDark ? 0.42 : 0.35))
            )
        }

        // MARK: 4. 赛博猫头鹰本体（与参考图 1 & 2 严格对齐）
        drawCyberOwl(
            in: &context,
            scale: scale,
            pt: pt,
            rect: rect,
            mood: mood,
            time: time,
            isDark: isDark,
            accent: accent,
            neon: neon,
            deep: deep,
            bob: bob
        )

        // MARK: 5. 液态玻璃球表面高光弧与外圈折射描边
        context.stroke(
            sphere,
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(isDark ? 0.72 : 0.88),
                    accent.opacity(0.55),
                    Color.white.opacity(isDark ? 0.28 : 0.45)
                ]),
                startPoint: pt(24, 24),
                endPoint: pt(76, 76)
            ),
            lineWidth: 1.25 * scale
        )

        // 左上角月牙高光反射弧
        var topArc = Path()
        topArc.addArc(
            center: center,
            radius: 27.6 * scale,
            startAngle: .degrees(196),
            endAngle: .degrees(312),
            clockwise: false
        )
        context.stroke(
            topArc,
            with: .color(Color.white.opacity(0.58 + 0.18 * breath)),
            style: StrokeStyle(lineWidth: 1.65 * scale, lineCap: .round)
        )

        // 右下角次级折射弧
        var bottomArc = Path()
        bottomArc.addArc(
            center: center,
            radius: 27.6 * scale,
            startAngle: .degrees(24),
            endAngle: .degrees(116),
            clockwise: false
        )
        context.stroke(
            bottomArc,
            with: .color(neon.opacity(0.62)),
            style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round)
        )

        // MARK: 6. 前半圈双倾斜星轨（横跨玻璃球前方，形成 3D 环绕感）
        drawOrbitHalf(
            in: &context,
            center: CGPoint(x: center.x, y: center.y + 1.2 * scale),
            scale: scale,
            radiusX: 44.5,
            radiusY: 14.5,
            tiltDegrees: -22,
            frontHalf: true,
            color: orbitColor1,
            lineWidth: 1.45,
            dotAngles: [time * 24 * speedMultiplier + 28, time * 24 * speedMultiplier + 148]
        )
        drawOrbitHalf(
            in: &context,
            center: CGPoint(x: center.x, y: center.y + 1.2 * scale),
            scale: scale,
            radiusX: 40.0,
            radiusY: 12.2,
            tiltDegrees: 19,
            frontHalf: true,
            color: orbitColor2,
            lineWidth: 1.15,
            dotAngles: [-time * 18 * speedMultiplier + 72, -time * 18 * speedMultiplier + 162]
        )

        // MARK: 7. 情绪特效
        switch mood {
        case .calm:
            break

        case .thinking:
            for index in 0..<3 {
                let phase = (time * 0.95 + Double(index) * 0.33).truncatingRemainder(dividingBy: 1)
                let rise = CGFloat(phase) * 11
                let alpha = 1 - phase
                let radius = (1.4 + CGFloat(index) * 0.85) * scale
                let bubbleCenter = pt(49 + CGFloat(index) * 6 - 3, 16 - rise)
                let bubble = Path(ellipseIn: CGRect(
                    x: bubbleCenter.x - radius,
                    y: bubbleCenter.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.fill(bubble, with: .color(neon.opacity(alpha * 0.9)))
            }

        case .happy:
            let pulse = CGFloat(0.85 + 0.25 * sin(time * 3.4))
            context.fill(
                star(center: pt(76, 25), radius: 5.8 * scale * pulse),
                with: .color(Color.white.opacity(0.95))
            )
            context.fill(
                star(center: pt(24, 31), radius: 3.8 * scale * pulse),
                with: .color(neon.opacity(0.92))
            )
        }
    }

    // MARK: - 3D 分段星轨

    private static func drawOrbitHalf(
        in context: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat,
        radiusX: CGFloat,
        radiusY: CGFloat,
        tiltDegrees: Double,
        frontHalf: Bool,
        color: Color,
        lineWidth: CGFloat,
        dotAngles: [Double]
    ) {
        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .degrees(tiltDegrees))

        let startDeg: Double = frontHalf ? 0 : 180
        let endDeg: Double = frontHalf ? 180 : 360
        var arcPath = Path()
        let steps = 60
        for step in 0...steps {
            let deg = startDeg + (endDeg - startDeg) * Double(step) / Double(steps)
            let rad = deg * .pi / 180
            let p = CGPoint(
                x: CGFloat(cos(rad)) * radiusX * scale,
                y: CGFloat(sin(rad)) * radiusY * scale
            )
            if step == 0 {
                arcPath.move(to: p)
            } else {
                arcPath.addLine(to: p)
            }
        }
        layer.stroke(arcPath, with: .color(color), lineWidth: lineWidth * scale)

        // 轨道上的发光星尘节点
        for rawDeg in dotAngles {
            let normalized = (rawDeg.truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360)
            let isInFront = normalized >= 0 && normalized <= 180
            guard isInFront == frontHalf else { continue }

            let rad = normalized * .pi / 180
            let dot = CGPoint(
                x: CGFloat(cos(rad)) * radiusX * scale,
                y: CGFloat(sin(rad)) * radiusY * scale
            )
            let dotRadius = (frontHalf ? 2.1 : 1.6) * scale
            layer.drawLayer { glow in
                glow.addFilter(.blur(radius: 2.6 * scale))
                glow.fill(
                    Path(ellipseIn: CGRect(
                        x: dot.x - dotRadius * 2.2,
                        y: dot.y - dotRadius * 2.2,
                        width: dotRadius * 4.4,
                        height: dotRadius * 4.4
                    )),
                    with: .color(color)
                )
            }
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: dot.x - dotRadius,
                    y: dot.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )),
                with: .color(Color.white.opacity(0.95))
            )
        }
    }

    // MARK: - 赛博猫头鹰本体

    private static func drawCyberOwl(
        in context: inout GraphicsContext,
        scale: CGFloat,
        pt: (CGFloat, CGFloat) -> CGPoint,
        rect: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect,
        mood: MimirMascot.Mood,
        time: TimeInterval,
        isDark: Bool,
        accent: Color,
        neon: Color,
        deep: Color,
        bob: CGFloat
    ) {
        var owl = context
        owl.translateBy(x: 0, y: bob * scale * 0.45)

        let bodyTop = Color(red: 0.52, green: 0.30, blue: 0.98)
        let bodyBottom = Color(red: 0.22, green: 0.09, blue: 0.56)
        let rimStroke = Color(red: 0.84, green: 0.70, blue: 1.00)
        let pupilInk = Color(red: 0.08, green: 0.03, blue: 0.20)

        // 1. 身体主轮廓（饱满椭圆躯干）
        let torso = Path(ellipseIn: rect(34.5, 35.0, 31.0, 34.5))
        owl.fill(
            torso,
            with: .linearGradient(
                Gradient(colors: [bodyTop, bodyBottom]),
                startPoint: pt(50, 35),
                endPoint: pt(50, 69.5)
            )
        )
        owl.stroke(torso, with: .color(rimStroke.opacity(0.72)), lineWidth: 0.95 * scale)

        // 2. 两侧收拢护翼（带霓虹描边）
        let leftWing = polygon([
            (35.2, 43.5),
            (31.8, 49.8),
            (32.2, 58.8),
            (36.0, 65.2),
            (39.0, 62.2),
            (38.0, 51.5)
        ], pt)
        let rightWing = polygon([
            (64.8, 43.5),
            (68.2, 49.8),
            (67.8, 58.8),
            (64.0, 65.2),
            (61.0, 62.2),
            (62.0, 51.5)
        ], pt)
        owl.fill(leftWing, with: .color(bodyBottom.opacity(0.92)))
        owl.fill(rightWing, with: .color(bodyBottom.opacity(0.92)))
        owl.stroke(leftWing, with: .color(rimStroke.opacity(0.82)), lineWidth: 0.95 * scale)
        owl.stroke(rightWing, with: .color(rimStroke.opacity(0.82)), lineWidth: 0.95 * scale)

        // 3. 标志性上扬尖耳簇（V 字眉骨外延）
        let leftEar = polygon([
            (35.8, 35.5),
            (32.8, 25.2),
            (40.8, 28.8),
            (46.2, 34.2),
            (39.5, 36.5)
        ], pt)
        let rightEar = polygon([
            (64.2, 35.5),
            (67.2, 25.2),
            (59.2, 28.8),
            (53.8, 34.2),
            (60.5, 36.5)
        ], pt)
        owl.fill(leftEar, with: .color(bodyTop))
        owl.fill(rightEar, with: .color(bodyTop))
        owl.stroke(leftEar, with: .color(rimStroke.opacity(0.9)), lineWidth: 0.95 * scale)
        owl.stroke(rightEar, with: .color(rimStroke.opacity(0.9)), lineWidth: 0.95 * scale)

        // 4. 发光双眼底盘与眼盘
        let leftEyeRect = rect(36.8, 34.5, 12.2, 12.2)
        let rightEyeRect = rect(51.0, 34.5, 12.2, 12.2)

        owl.drawLayer { glow in
            glow.addFilter(.blur(radius: 2.4 * scale))
            glow.fill(Path(ellipseIn: leftEyeRect.insetBy(dx: -1.2 * scale, dy: -1.2 * scale)), with: .color(neon))
            glow.fill(Path(ellipseIn: rightEyeRect.insetBy(dx: -1.2 * scale, dy: -1.2 * scale)), with: .color(neon))
        }

        let leftDisc = Path(ellipseIn: leftEyeRect)
        let rightDisc = Path(ellipseIn: rightEyeRect)
        owl.fill(leftDisc, with: .color(Color(red: 0.86, green: 0.74, blue: 1.00)))
        owl.fill(rightDisc, with: .color(Color(red: 0.86, green: 0.74, blue: 1.00)))
        owl.stroke(leftDisc, with: .color(Color.white.opacity(0.88)), lineWidth: 0.95 * scale)
        owl.stroke(rightDisc, with: .color(Color.white.opacity(0.88)), lineWidth: 0.95 * scale)

        if mood == .happy {
            for centerX in [CGFloat(42.9), CGFloat(57.1)] {
                var arc = Path()
                arc.addArc(
                    center: pt(centerX, 41.2),
                    radius: 3.3 * scale,
                    startAngle: .degrees(200),
                    endAngle: .degrees(340),
                    clockwise: false
                )
                owl.stroke(arc, with: .color(pupilInk), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
            }
        } else {
            // 紫罗兰虹膜 + 深色瞳孔 + 双高光点
            let leftIris = Path(ellipseIn: rect(38.2, 35.9, 9.4, 9.4))
            let rightIris = Path(ellipseIn: rect(52.4, 35.9, 9.4, 9.4))
            owl.fill(leftIris, with: .color(Color(red: 0.60, green: 0.32, blue: 1.00)))
            owl.fill(rightIris, with: .color(Color(red: 0.60, green: 0.32, blue: 1.00)))

            let leftPupil = Path(ellipseIn: rect(39.4, 37.1, 7.0, 7.0))
            let rightPupil = Path(ellipseIn: rect(53.6, 37.1, 7.0, 7.0))
            owl.fill(leftPupil, with: .color(pupilInk))
            owl.fill(rightPupil, with: .color(pupilInk))

            let blink = sin(time * 0.75) > 0.985 ? 0.25 : 1.0
            owl.fill(
                Path(ellipseIn: rect(40.4, 37.8, 2.3, 2.3)),
                with: .color(Color.white.opacity(0.96 * blink))
            )
            owl.fill(
                Path(ellipseIn: rect(54.6, 37.8, 2.3, 2.3)),
                with: .color(Color.white.opacity(0.96 * blink))
            )
            owl.fill(
                Path(ellipseIn: rect(44.0, 41.4, 1.2, 1.2)),
                with: .color(rimStroke.opacity(0.85 * blink))
            )
            owl.fill(
                Path(ellipseIn: rect(58.2, 41.4, 1.2, 1.2)),
                with: .color(rimStroke.opacity(0.85 * blink))
            )
        }

        // 5. 眉心 V 字科技折线（从双耳直达鸟喙）
        var browLine = Path()
        browLine.move(to: pt(36.2, 31.2))
        browLine.addLine(to: pt(50.0, 41.2))
        browLine.addLine(to: pt(63.8, 31.2))
        owl.stroke(
            browLine,
            with: .color(rimStroke.opacity(0.92)),
            style: StrokeStyle(lineWidth: 1.15 * scale, lineCap: .round, lineJoin: .round)
        )

        // 6. 锐利菱形鸟喙
        let beak = polygon([
            (50.0, 41.5),
            (47.2, 45.8),
            (50.0, 50.2),
            (52.8, 45.8)
        ], pt)
        owl.fill(beak, with: .color(Color.white.opacity(0.92)))
        owl.stroke(beak, with: .color(rimStroke), lineWidth: 0.7 * scale)

        // 7. 胸前标志性三排 V 形羽毛鳞纹（参考图 1 & 2 核心特征）
        let featherRows: [[(CGFloat, CGFloat)]] = [
            [(43.5, 53.6), (47.8, 54.0), (52.2, 54.0), (56.5, 53.6)],
            [(45.5, 57.8), (50.0, 58.2), (54.5, 57.8)],
            [(47.8, 61.8), (52.2, 61.8)]
        ]
        for row in featherRows {
            for (fx, fy) in row {
                var vPath = Path()
                vPath.move(to: pt(fx - 1.35, fy - 0.65))
                vPath.addLine(to: pt(fx, fy + 0.95))
                vPath.addLine(to: pt(fx + 1.35, fy - 0.65))
                owl.stroke(
                    vPath,
                    with: .color(rimStroke.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 0.85 * scale, lineCap: .round, lineJoin: .round)
                )
            }
        }

        // 8. 底部三趾小利爪
        for baseX in [CGFloat(44.5), CGFloat(55.5)] {
            for dx in [CGFloat(-1.7), CGFloat(0), CGFloat(1.7)] {
                let clawRect = rect(baseX + dx - 0.55, 67.8, 1.1, 3.2)
                owl.fill(
                    Path(roundedRect: clawRect, cornerRadius: 0.55 * scale),
                    with: .color(rimStroke.opacity(0.88))
                )
            }
        }
    }

    // MARK: - 几何辅助

    private static func polygon(
        _ points: [(CGFloat, CGFloat)],
        _ transform: (CGFloat, CGFloat) -> CGPoint
    ) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: transform(first.0, first.1))
        for point in points.dropFirst() {
            path.addLine(to: transform(point.0, point.1))
        }
        path.closeSubpath()
        return path
    }

    private static func star(center: CGPoint, radius: CGFloat, thin: CGFloat = 0.30) -> Path {
        let w = radius * thin
        return polygon(
            [
                (0, -radius),
                (w, -w),
                (radius, 0),
                (w, w),
                (0, radius),
                (-w, w),
                (-radius, 0),
                (-w, -w)
            ],
            { CGPoint(x: center.x + $0, y: center.y + $1) }
        )
    }
}
