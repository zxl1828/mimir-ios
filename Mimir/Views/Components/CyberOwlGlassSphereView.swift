import SwiftUI

/// Reusable glass sphere with Mimir's armored owl.
///
/// 说明：球外的椭圆轨道与卫星曾由这里单独绘制，与猫头鹰自带的星轨叠在一起，
/// 3D 压扁后会在球心横穿一条深色"直线"。现在轨道统一交给 `MimirMascot` 画，
/// 这里只负责玻璃球与猫头鹰本体。
struct CyberOwlGlassSphereView: View {
    var diameter: CGFloat = 180
    var isAnimating = true


    private let iris = Color(hex: "9C70FF")
    private let violet = AppUI.consoleSignal

    private var orbitWidth: CGFloat { diameter * 1.34 }

    @Environment(\.colorScheme) private var scheme

    /// 玻璃球底色跟着深浅色模式走：浅色是雾白玻璃，深色才是紫黑；
    /// 之前两种模式共用一套深紫填充，浅色下就成了一块黑罩子。
    private var bodyFills: [Color] {
        if scheme == .dark {
            return [
                Color(hex: "342452").opacity(0.34),
                Color(hex: "171126").opacity(0.50),
                Color(hex: "100C1A").opacity(0.32)
            ]
        }
        return [
            Color.white.opacity(0.72),
            Color(hex: "EFE8FF").opacity(0.52),
            Color.white.opacity(0.34)
        ]
    }

    private var sheenColors: [Color] {
        if scheme == .dark {
            return [
                Color.white.opacity(0.17),
                Color(hex: "C9AEFF").opacity(0.07),
                violet.opacity(0.10),
                Color.white.opacity(0.03)
            ]
        }
        return [
            Color.white.opacity(0.90),
            Color(hex: "D9C7FF").opacity(0.42),
            violet.opacity(0.10),
            Color.white.opacity(0.30)
        ]
    }

    var body: some View {
        ZStack {
            ambientRefraction
                .frame(width: diameter * 1.16, height: diameter * 1.16)

            glassSphere
                .frame(width: diameter, height: diameter)
                .zIndex(1)
        }
        .frame(width: orbitWidth, height: diameter * 1.28)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mimir 赛博猫头鹰液态玻璃球")
    }

    private var glassSphere: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: bodyFills,
                        center: .center,
                        startRadius: 2,
                        endRadius: diameter * 0.55
                    )
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: sheenColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [iris.opacity(0.32), violet.opacity(0.10), .clear],
                        center: .center,
                        startRadius: diameter * 0.08,
                        endRadius: diameter * 0.56
                    )
                )
                .padding(diameter * 0.10)
                .blendMode(.screen)

            MimirMascot(size: min(112, diameter * 0.62), mood: .calm, showsOrbit: true)
                .shadow(color: iris.opacity(0.50), radius: diameter * 0.10, y: 1)
                .shadow(color: violet.opacity(0.32), radius: diameter * 0.18, y: 4)

            Circle()
                .trim(from: 0.10, to: 0.43)
                .stroke(
                    AngularGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0.14), iris.opacity(0.52)],
                        center: .center,
                        startAngle: .degrees(205),
                        endAngle: .degrees(335)
                    ),
                    style: StrokeStyle(lineWidth: max(2, diameter * 0.026), lineCap: .round)
                )
                .rotationEffect(.degrees(-108))
                .padding(diameter * 0.045)
                .blur(radius: 0.35)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.48), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: diameter * 0.30, height: diameter * 0.105)
                .blur(radius: diameter * 0.025)
                .rotationEffect(.degrees(-38))
                .offset(x: -diameter * 0.22, y: -diameter * 0.32)

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.88),
                            Color(hex: "C9AEFF").opacity(0.52),
                            violet.opacity(0.64),
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )

            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.55)
                .padding(diameter * 0.035)
        }
        .liquidGlass(.regular.tint(violet.opacity(0.08)), in: Circle())
        .clipShape(Circle())
        .shadow(color: violet.opacity(0.18), radius: diameter * 0.12, y: diameter * 0.045)
    }

    private var ambientRefraction: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [iris.opacity(0.24), violet.opacity(0.08), .clear],
                    center: .center,
                    startRadius: diameter * 0.20,
                    endRadius: diameter * 0.58
                )
            )
            .blur(radius: diameter * 0.12)
            .allowsHitTesting(false)
    }

}
