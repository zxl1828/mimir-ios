import SwiftUI

/// Mimir brand icon: compact, static, and clear.
struct MimirMascot: View {
    enum Mood { case calm, thinking, happy }
    var size: CGFloat = 72
    var mood: Mood = .calm
    var animated: Bool = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 80
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let badge = Path(ellipseIn: CGRect(x: center.x - 34 * scale, y: center.y - 34 * scale,
                                                width: 68 * scale, height: 68 * scale))
            let outline = scheme == .dark ? Color(hex: "BDA8F8") : Color(hex: "7D52F4")
            context.fill(badge, with: .color(scheme == .dark ? Color(hex: "241B35") : Color(hex: "F0EAFB")))
            context.stroke(badge, with: .color(outline.opacity(0.55)), lineWidth: 1.2 * scale)

            var owl = Path()
            owl.move(to: CGPoint(x: center.x - 20 * scale, y: center.y - 9 * scale))
            owl.addLine(to: CGPoint(x: center.x - 17 * scale, y: center.y - 24 * scale))
            owl.addLine(to: CGPoint(x: center.x - 7 * scale, y: center.y - 17 * scale))
            owl.addCurve(to: CGPoint(x: center.x + 7 * scale, y: center.y - 17 * scale),
                         control1: CGPoint(x: center.x - 3 * scale, y: center.y - 20 * scale),
                         control2: CGPoint(x: center.x + 3 * scale, y: center.y - 20 * scale))
            owl.addLine(to: CGPoint(x: center.x + 17 * scale, y: center.y - 24 * scale))
            owl.addLine(to: CGPoint(x: center.x + 20 * scale, y: center.y - 9 * scale))
            owl.addCurve(to: CGPoint(x: center.x - 20 * scale, y: center.y - 9 * scale),
                         control1: CGPoint(x: center.x + 20 * scale, y: center.y + 23 * scale),
                         control2: CGPoint(x: center.x - 20 * scale, y: center.y + 23 * scale))
            owl.closeSubpath()
            context.fill(owl, with: .color(accent))
            context.stroke(owl, with: .color(outline.opacity(0.72)), lineWidth: scale)

            let eyeRadius = 9 * scale
            for x in [-10.0, 10.0] {
                let eyeCenter = CGPoint(x: center.x + CGFloat(x) * scale, y: center.y - 4 * scale)
                let eye = Path(ellipseIn: CGRect(x: eyeCenter.x - eyeRadius, y: eyeCenter.y - eyeRadius,
                                                 width: eyeRadius * 2, height: eyeRadius * 2))
                context.fill(eye, with: .color(Color.white.opacity(scheme == .dark ? 0.90 : 0.98)))
                context.fill(Path(ellipseIn: CGRect(x: eyeCenter.x - 2.5 * scale, y: eyeCenter.y - 2.5 * scale,
                                                    width: 5 * scale, height: 5 * scale)), with: .color(Color(hex: "120D1D")))
            }

            var beak = Path()
            beak.move(to: CGPoint(x: center.x, y: center.y + 4 * scale))
            beak.addLine(to: CGPoint(x: center.x - 4 * scale, y: center.y + 10 * scale))
            beak.addLine(to: CGPoint(x: center.x + 4 * scale, y: center.y + 10 * scale))
            beak.closeSubpath()
            context.fill(beak, with: .color(Color.white.opacity(0.9)))
        }
        .frame(width: min(size, 80), height: min(size, 80))
        .accessibilityLabel("Mimir")
    }
}
