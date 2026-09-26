import SwiftUI
import UIKit

/// Mimir 的形象「米米」：住在全息玻璃球里的紫色猫头鹰。
///
/// 纯 `Canvas` 矢量绘制（设计稿 100 × 100），任意尺寸都清晰，并跟随状态做动画：
/// - `.calm`：紫色呼吸光晕 + 双轨道缓慢逆向旋转，空对话页使用
/// - `.thinking`：头顶浮起思考气泡，生成 / 思考时使用
/// - `.happy`：月牙眼 + 闪光，完成类场景使用
struct MimirMascot: View {

    enum Mood {
        case calm
        case thinking
        case happy
    }

    var size: CGFloat = 96
    var mood: Mood = .calm
    var animated: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { timeline in
            Canvas { context, canvasSize in
                let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                MimirOwlRenderer.draw(
                    in: &context,
                    size: canvasSize,
                    mood: mood,
                    time: time
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 纯绘制逻辑，与视图状态无关。
private enum MimirOwlRenderer {

    /// 设计稿为 100 × 100 的方形。
    private static let design: CGFloat = 100

    static func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        mood: MimirMascot.Mood,
        time: TimeInterval
    ) {
        let scale = min(size.width, size.height) / design
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale, y: y * scale)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
        }

        let accent = AppUI.brandPurple
        let neon = AppUI.neonViolet
        let deep = AppUI.deepViolet

        // 呼吸：2.2s 一个周期，0...1
        let breath = 0.5 + 0.5 * sin(time * 2 * .pi / 2.2)
        let bob = CGFloat(sin(time * 1.05)) * (mood == .thinking ? 0.9 : 1.7)
        let center = pt(50, 50 + bob * 0.5)

        // MARK: 1. 呼吸光晕
        let glowRadius = (45 + breath * 4) * scale
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 11 * scale))
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - glowRadius,
                    y: center.y - glowRadius,
                    width: glowRadius * 2,
                    height: glowRadius * 2
                )),
                with: .color(accent.opacity(0.16 + 0.14 * breath))
            )
        }

        // MARK: 2. 双同心轨道环（逆向旋转）
        drawOrbit(
            in: &context,
            center: center,
            scale: scale,
            radiusX: 44,
            radiusY: 15,
            degrees: time * 16,
            color: neon.opacity(0.55),
            lineWidth: 1.4,
            dotPhase: time * 0.85
        )
        drawOrbit(
            in: &context,
            center: center,
            scale: scale,
            radiusX: 39,
            radiusY: 13,
            degrees: -time * 11 + 42,
            color: accent.opacity(0.38),
            lineWidth: 1.0,
            dotPhase: time * 0.55 + 0.4
        )

        // MARK: 3. 全息玻璃球
        let sphere = Path(ellipseIn: rect(22, 22, 56, 56))
        context.fill(
            sphere,
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.30),
                    accent.opacity(0.32),
                    deep.opacity(0.62)
                ]),
                center: pt(42, 37),
                startRadius: 2 * scale,
                endRadius: 34 * scale
            )
        )
        context.stroke(sphere, with: .color(Color.white.opacity(0.45)), lineWidth: 1.1 * scale)

        // 顶部高光弧
        var rim = Path()
        rim.addArc(
            center: center,
            radius: 27.5 * scale,
            startAngle: .degrees(198),
            endAngle: .degrees(322),
            clockwise: false
        )
        context.stroke(rim, with: .color(Color.white.opacity(breath > 0.5 ? 0.62 : 0.48)), lineWidth: 1.6 * scale)

        // MARK: 4. 猫头鹰
        drawOwl(
            in: &context,
            scale: scale,
            pt: pt,
            rect: rect,
            mood: mood,
            time: time,
            accent: accent,
            neon: neon,
            deep: deep,
            bob: bob
        )

        // MARK: 5. 情绪特效
        switch mood {
        case .calm:
            break

        case .thinking:
            for index in 0..<3 {
                let phase = (time * 0.9 + Double(index) * 0.33).truncatingRemainder(dividingBy: 1)
                let rise = CGFloat(phase) * 12
                let alpha = 1 - phase
                let radius = (1.5 + CGFloat(index) * 0.9) * scale
                let bubble = Path(ellipseIn: CGRect(
                    x: pt(50 + CGFloat(index) * 7 - 3, 16 - rise).x - radius,
                    y: pt(0, 16 - rise).y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.fill(bubble, with: .color(neon.opacity(alpha * 0.85)))
            }

        case .happy:
            let pulse = CGFloat(0.85 + 0.25 * sin(time * 3.4))
            context.fill(
                star(center: pt(74, 26), radius: 6.4 * scale * pulse),
                with: .color(Color.white.opacity(0.95))
            )
            context.fill(
                star(center: pt(27, 33), radius: 3.8 * scale * pulse),
                with: .color(neon.opacity(0.9))
            )
        }
    }

    // MARK: - 轨道

    private static func drawOrbit(
        in context: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat,
        radiusX: CGFloat,
        radiusY: CGFloat,
        degrees: Double,
        color: Color,
        lineWidth: CGFloat,
        dotPhase: TimeInterval
    ) {
        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .degrees(degrees))

        let orbit = Path(ellipseIn: CGRect(
            x: -radiusX * scale,
            y: -radiusY * scale,
            width: radiusX * 2 * scale,
            height: radiusY * 2 * scale
        ))
        layer.stroke(orbit, with: .color(color), lineWidth: lineWidth * scale)

        // 轨道上的一颗微光点
        let angle = dotPhase * 2 * .pi
        let dot = CGPoint(
            x: cos(angle) * radiusX * scale,
            y: sin(angle) * radiusY * scale
        )
        let dotRadius = 2.2 * scale
        layer.drawLayer { glow in
            glow.addFilter(.blur(radius: 3 * scale))
            glow.fill(
                Path(ellipseIn: CGRect(
                    x: dot.x - dotRadius * 2,
                    y: dot.y - dotRadius * 2,
                    width: dotRadius * 4,
                    height: dotRadius * 4
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
            with: .color(Color.white.opacity(0.9))
        )
    }

    // MARK: - 猫头鹰本体

    private static func drawOwl(
        in context: inout GraphicsContext,
        scale: CGFloat,
        pt: (CGFloat, CGFloat) -> CGPoint,
        rect: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect,
        mood: MimirMascot.Mood,
        time: TimeInterval,
        accent: Color,
        neon: Color,
        deep: Color,
        bob: CGFloat
    ) {
        var owl = context
        owl.translateBy(x: 0, y: bob * scale * 0.4)

        // 耳簇
        owl.fill(polygon([(36.5, 36), (40.5, 25.5), (45.5, 35)], pt), with: .color(deep))
        owl.fill(polygon([(63.5, 36), (59.5, 25.5), (54.5, 35)], pt), with: .color(deep))

        // 身体
        let body = Path(ellipseIn: rect(34, 33, 32, 36))
        owl.fill(
            body,
            with: .linearGradient(
                Gradient(colors: [deep.opacity(0.96), deep.opacity(0.72)]),
                startPoint: pt(50, 33),
                endPoint: pt(50, 69)
            )
        )
        owl.stroke(body, with: .color(accent.opacity(0.45)), lineWidth: 1 * scale)

        // 翅膀
        owl.stroke(Path(ellipseIn: rect(30.5, 45, 13, 21)), with: .color(accent.opacity(0.42)), lineWidth: 1.3 * scale)
        owl.stroke(Path(ellipseIn: rect(56.5, 45, 13, 21)), with: .color(accent.opacity(0.42)), lineWidth: 1.3 * scale)

        // 面盘
        let leftDisc = Path(ellipseIn: rect(35, 34.5, 16.5, 16.5))
        let rightDisc = Path(ellipseIn: rect(48.5, 34.5, 16.5, 16.5))
        owl.fill(leftDisc, with: .color(Color.white.opacity(0.92)))
        owl.fill(rightDisc, with: .color(Color.white.opacity(0.92)))
        owl.stroke(leftDisc, with: .color(accent.opacity(0.55)), lineWidth: 1.1 * scale)
        owl.stroke(rightDisc, with: .color(accent.opacity(0.55)), lineWidth: 1.1 * scale)

        // 眼睛（发光底）
        owl.drawLayer { glow in
            glow.addFilter(.blur(radius: 2.6 * scale))
            glow.fill(Path(ellipseIn: rect(38.5, 38, 9.5, 9.5)), with: .color(neon))
            glow.fill(Path(ellipseIn: rect(52, 38, 9.5, 9.5)), with: .color(neon))
        }

        if mood == .happy {
            // 月牙眼：两条上凸弧
            for originX in [CGFloat(40.0), CGFloat(53.5)] {
                var arc = Path()
                arc.addArc(
                    center: pt(originX + 3, 43.6),
                    radius: 3.4 * scale,
                    startAngle: .degrees(200),
                    endAngle: .degrees(340),
                    clockwise: false
                )
                owl.stroke(arc, with: .color(deep.opacity(0.95)), lineWidth: 1.9 * scale)
            }
        } else {
            owl.fill(Path(ellipseIn: rect(40.2, 39.8, 6.1, 6.1)), with: .color(deep.opacity(0.96)))
            owl.fill(Path(ellipseIn: rect(53.7, 39.8, 6.1, 6.1)), with: .color(deep.opacity(0.96)))
            // 眼神高光
            let blink = sin(time * 0.7) > 0.985 ? 0.35 : 1.0
            owl.fill(
                Path(ellipseIn: rect(44.4, 40.6, 2.1, 2.1)),
                with: .color(Color.white.opacity(0.95 * blink))
            )
            owl.fill(
                Path(ellipseIn: rect(57.9, 40.6, 2.1, 2.1)),
                with: .color(Color.white.opacity(0.95 * blink))
            )
        }

        // 喙（锐利下折角）
        owl.fill(
            polygon([(50, 45.4), (45.6, 52.6), (50, 51.2), (54.4, 52.6)], pt),
            with: .color(neon.opacity(0.95))
        )

        // 胸前羽纹
        owl.stroke(
            polygon([(43, 58), (50, 60.5), (57, 58)], pt),
            with: .color(accent.opacity(0.5)),
            lineWidth: 1.2 * scale
        )
        owl.stroke(
            polygon([(45.5, 62.5), (50, 64.2), (54.5, 62.5)], pt),
            with: .color(accent.opacity(0.35)),
            lineWidth: 1.1 * scale
        )
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
