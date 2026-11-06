import SwiftUI

/// Mimir 的静态赛博猫头鹰品牌资产：深紫金属机甲、机械胸甲、细节眼眸与静态行星环。
struct MimirMascot: View {
    enum Mood { case calm, thinking, happy }
    var size: CGFloat = 72
    var mood: Mood = .calm
    var animated: Bool = false
    var showsOrbit: Bool = true

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) / 100
            let p: (CGFloat, CGFloat) -> CGPoint = { CGPoint(x: $0 * s, y: $1 * s) }
            let outline = Color(hex: "D8C8FF")
            let metalTop = Color(hex: "7650C8")
            let metalMid = Color(hex: "39206E")
            let metalDeep = Color(hex: "17102E")
            let neon = Color(hex: "B18CFF")

            if showsOrbit {
                var orbit = Path()
                for index in 0...80 {
                    let a = Double(index) / 80 * Double.pi * 2
                    let point = p(50 + CGFloat(cos(a)) * 44, 50 + CGFloat(sin(a)) * 14)
                    if index == 0 { orbit.move(to: point) } else { orbit.addLine(to: point) }
                }
                context.stroke(orbit, with: .color(neon.opacity(0.68)), lineWidth: 1.0 * s)
            }

            let torso = Path(roundedRect: CGRect(x: 33 * s, y: 34 * s, width: 34 * s, height: 38 * s), cornerRadius: 13 * s)
            context.fill(torso, with: .linearGradient(Gradient(colors: [metalTop, metalMid, metalDeep]), startPoint: p(42, 32), endPoint: p(60, 72)))
            context.stroke(torso, with: .color(outline.opacity(0.8)), lineWidth: 1.1 * s)

            let leftWing = polygon([(35, 42), (28, 53), (33, 68), (42, 62), (40, 48)], p)
            let rightWing = polygon([(65, 42), (72, 53), (67, 68), (58, 62), (60, 48)], p)
            context.fill(leftWing, with: .color(metalDeep.opacity(0.96)))
            context.fill(rightWing, with: .color(metalDeep.opacity(0.96)))
            context.stroke(leftWing, with: .color(outline.opacity(0.72)), lineWidth: 1 * s)
            context.stroke(rightWing, with: .color(outline.opacity(0.72)), lineWidth: 1 * s)

            let leftEar = polygon([(36, 37), (31, 24), (44, 30), (48, 38)], p)
            let rightEar = polygon([(64, 37), (69, 24), (56, 30), (52, 38)], p)
            context.fill(leftEar, with: .color(metalTop))
            context.fill(rightEar, with: .color(metalTop))
            context.stroke(leftEar, with: .color(outline), lineWidth: 1 * s)
            context.stroke(rightEar, with: .color(outline), lineWidth: 1 * s)

            let eyeCenters: [CGFloat] = [42, 58]
            for x in eyeCenters {
                let eye = Path(ellipseIn: CGRect(x: (x - 7) * s, y: 34 * s, width: 14 * s, height: 14 * s))
                context.fill(eye, with: .color(Color(hex: "D9C9FF")))
                context.stroke(eye, with: .color(.white.opacity(0.9)), lineWidth: 0.8 * s)
                context.fill(Path(ellipseIn: CGRect(x: (x - 5) * s, y: 36 * s, width: 10 * s, height: 10 * s)), with: .color(neon))
                context.fill(Path(ellipseIn: CGRect(x: (x - 2.7) * s, y: 38 * s, width: 5.4 * s, height: 6 * s)), with: .color(Color(hex: "120D1D")))
                context.fill(Path(ellipseIn: CGRect(x: (x - 2.8) * s, y: 37 * s, width: 2 * s, height: 2 * s)), with: .color(.white))
            }

            var brow = Path()
            brow.move(to: p(35, 30)); brow.addLine(to: p(50, 41)); brow.addLine(to: p(65, 30))
            context.stroke(brow, with: .color(outline), lineWidth: 1.15 * s)
            context.fill(polygon([(50, 41), (46.5, 47), (50, 51), (53.5, 47)], p), with: .color(.white.opacity(0.9)))

            let rows: [[(CGFloat, CGFloat)]] = [[(41, 53), (50, 55), (59, 53)], [(43, 58), (50, 60), (57, 58)], [(46, 63), (50, 65), (54, 63)]]
            for row in rows {
                var plate = Path()
                plate.move(to: p(row[0].0, row[0].1)); plate.addLine(to: p(row[1].0, row[1].1)); plate.addLine(to: p(row[2].0, row[2].1))
                context.stroke(plate, with: .color(outline.opacity(0.9)), style: StrokeStyle(lineWidth: 1.15 * s, lineCap: .round, lineJoin: .round))
            }
            context.fill(Path(roundedRect: CGRect(x: 48.5 * s, y: 54 * s, width: 3 * s, height: 13 * s), cornerRadius: 1.5 * s), with: .color(neon.opacity(0.75)))
            let footCenters: [CGFloat] = [44, 56]
            for x in footCenters { context.fill(Path(roundedRect: CGRect(x: (x - 2) * s, y: 69 * s, width: 1.5 * s, height: 4 * s), cornerRadius: 0.7 * s), with: .color(outline)) }
        }
        .frame(width: min(size, 80), height: min(size, 80))
        .accessibilityLabel("Mimir 赛博猫头鹰")
    }

    private func polygon(_ points: [(CGFloat, CGFloat)], _ transform: (CGFloat, CGFloat) -> CGPoint) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: transform(first.0, first.1))
        for point in points.dropFirst() { path.addLine(to: transform(point.0, point.1)) }
        path.closeSubpath()
        return path
    }
}
