import SwiftUI

/// Mimir 的卡通形象「米米」：住在智慧之井里的小鲸。
///
/// 与 App 图标同源几何（设计稿 100 × 86），用 `Canvas` 矢量绘制，
/// 因此在任意尺寸下都清晰，也能跟随状态做动画：
/// - `.calm`：轻轻上浮、偶尔眨眼，空对话页使用
/// - `.thinking`：头顶冒泡，生成 / 思考时使用
/// - `.happy`：闪光炸开，连接成功等庆祝场景使用
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
                MascotRenderer.draw(
                    in: &context,
                    size: canvasSize,
                    mood: mood,
                    time: time
                )
            }
        }
        .frame(width: size, height: size * MascotRenderer.aspect)
        .accessibilityHidden(true)
    }
}

/// 纯绘制逻辑，与视图状态无关，便于复用与测试。
private enum MascotRenderer {

    /// 设计稿高宽比（100 × 86）。
    static let aspect: CGFloat = 0.86

    private static let design = CGSize(width: 100, height: 86)

    // 配色：浅色 / 深色背景下都能看清，不随外观切换。
    // 身体带一层淡靛蓝，避免在白色页面上「隐形」。
    private static let bodyTop = Color(red: 0.94, green: 0.96, blue: 1.00)
    private static let bodyBottom = Color(red: 0.72, green: 0.80, blue: 1.00)
    private static let fin = Color(red: 0.71, green: 0.79, blue: 1.00)
    private static let belly = Color(red: 0.86, green: 0.91, blue: 1.00)
    private static let gloss = Color.white.opacity(0.55)
    private static let ink = Color(red: 0.11, green: 0.13, blue: 0.31)
    private static let blush = Color(red: 1.00, green: 0.60, blue: 0.78)

    static func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        mood: MimirMascot.Mood,
        time: TimeInterval
    ) {
        let sx = size.width / design.width
        let sy = size.height / design.height
        let scale = min(sx, sy)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * sx, y: y * sy)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(origin: pt(x, y), size: CGSize(width: w * sx, height: h * sy))
        }

        // 呼吸 / 上浮
        let bob = CGFloat(sin(time * 1.1)) * (mood == .thinking ? 0.6 : 1.1)
        let wag = CGFloat(sin(time * 2.4)) * (mood == .happy ? 9.0 : 5.0)

        var whale = context
        whale.translateBy(x: 0, y: bob * sy)

        // MARK: 鳍（在身体之下，只露出边缘）
        let hinge = pt(25.5, 49.4)
        var tail = whale
        tail.translateBy(x: hinge.x, y: hinge.y)
        tail.rotate(by: Angle(degrees: Double(wag)))
        tail.translateBy(x: -hinge.x, y: -hinge.y)
        tail.fill(
            polygon([(25.5, 49.4), (2.7, 32.7), (12.4, 48.8), (2.7, 65.2), (26.1, 55.2)], pt),
            with: .color(fin)
        )
        whale.fill(
            polygon([(46.7, 36.7), (57.0, 18.2), (64.5, 36.7)], pt),
            with: .color(fin)
        )
        whale.fill(Path(ellipseIn: rect(74.8, 62.7, 17, 12.5)), with: .color(fin))

        // MARK: 身体（多个椭圆相加成豆形；渐变用绝对坐标，重叠处无缝）
        var silhouette = Path()
        silhouette.addEllipse(in: rect(50.8, 25.5, 47.7, 45.7))   // 头
        silhouette.addEllipse(in: rect(39.4, 30.9, 40.9, 38.5))   // 背线过渡
        silhouette.addEllipse(in: rect(21.5, 32.1, 57.3, 36.7))   // 后身
        silhouette.addEllipse(in: rect(23.0, 40.6, 19.7, 21.8))   // 尾根

        whale.drawLayer { layer in
            layer.addFilter(
                .shadow(
                    color: Color(red: 0.22, green: 0.28, blue: 0.68).opacity(0.22),
                    radius: max(1.5, scale * 1.6),
                    x: 0,
                    y: max(1, scale * 0.8)
                )
            )
            layer.fill(
                silhouette,
                with: .linearGradient(
                    Gradient(colors: [bodyTop, bodyBottom]),
                    startPoint: pt(50, 26),
                    endPoint: pt(50, 72)
                )
            )
        }

        // MARK: 身体内部：腹部与背部高光（按剪影裁切，不会溢出）
        var inner = whale
        inner.clip(to: silhouette)
        inner.fill(Path(ellipseIn: rect(36, 55, 56, 13)), with: .color(belly))
        var glossPath = Path()
        glossPath.addArc(
            center: pt(55, 49),
            radius: 26 * scale,
            startAngle: .degrees(196),
            endAngle: .degrees(268),
            clockwise: false
        )
        inner.stroke(glossPath, with: .color(gloss), lineWidth: max(0.8, scale * 1.4))
        inner.fill(Path(ellipseIn: rect(84.2, 50, 10, 5.2)), with: .color(blush.opacity(0.75)))

        // MARK: 眼睛与微笑
        let blink: CGFloat = {
            let cycle = time.truncatingRemainder(dividingBy: 4.2)
            guard cycle < 0.16 else { return 1 }
            return CGFloat(0.10 + abs(cycle - 0.08) / 0.08 * 0.90)
        }()
        if mood == .happy {
            // 开心时弯成月牙眼
            var eye = Path()
            eye.move(to: pt(72.5, 43.5))
            eye.addQuadCurve(to: pt(83.5, 43.5), control: pt(78, 33.5))
            whale.stroke(eye, with: .color(ink), style: StrokeStyle(lineWidth: max(1.2, scale * 2.0), lineCap: .round))
        } else {
            let eyeBox = rect(73.3, 36.4, 9.7, 9.7 * blink)
            whale.fill(Path(ellipseIn: eyeBox), with: .color(ink))
            if blink > 0.5 {
                whale.fill(Path(ellipseIn: rect(75.5, 38.2, 3.3, 3.3)), with: .color(Color.white.opacity(0.92)))
                whale.fill(Path(ellipseIn: rect(80.6, 43.3, 1.8, 1.9)), with: .color(Color.white.opacity(0.75)))
            }
        }
        var smile = Path()
        smile.addArc(
            center: pt(81.2, 54),
            radius: 6.4 * scale,
            startAngle: .degrees(25),
            endAngle: .degrees(105),
            clockwise: false
        )
        whale.stroke(
            smile,
            with: .color(ink.opacity(0.9)),
            style: StrokeStyle(lineWidth: max(1.0, scale * 1.4), lineCap: .round)
        )

        // MARK: 头顶喷水 / 冒泡 / 闪光
        switch mood {
        case .thinking:
            for index in 0..<3 {
                let progress = ((time * 0.55) + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let radius = CGFloat(1.3 + 1.1 * (1 - progress)) * scale
                let center = pt(66 + CGFloat(index) * 5.5, 21 - CGFloat(progress) * 15)
                whale.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .color(Color.white.opacity(0.75 * (1 - progress) + 0.15))
                )
            }
        default:
            let pulse: CGFloat = mood == .happy ? 1 + 0.18 * CGFloat(sin(time * 6)) : 1
            whale.fill(star(center: pt(74.2, 10.6), radius: 7.0 * scale * pulse), with: .color(Color.white.opacity(0.95)))
            whale.fill(star(center: pt(85.8, 2.6), radius: 3.0 * scale * pulse), with: .color(Color.white.opacity(0.85)))
            whale.fill(Path(ellipseIn: rect(65.2, 14.5, 4.5, 4.6)), with: .color(Color.white.opacity(0.9)))
            whale.fill(Path(ellipseIn: rect(82.1, 13.3, 3.4, 3.4)), with: .color(Color.white.opacity(0.8)))
        }
    }

    // MARK: - 小工具

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
                (-w, -w),
            ],
            { CGPoint(x: center.x + $0, y: center.y + $1) }
        )
    }
}
