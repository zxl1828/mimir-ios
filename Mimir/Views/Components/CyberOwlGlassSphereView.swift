import SwiftUI

/// Reusable glass sphere with Mimir's armored owl and a single animated orbital satellite.
struct CyberOwlGlassSphereView: View {
    var diameter: CGFloat = 180
    var isAnimating = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var orbitPhase: CGFloat = 0

    private let iris = Color(hex: "9C70FF")
    private let violet = Color(hex: "7D52F4")

    private var orbitWidth: CGFloat { diameter * 1.34 }
    private var orbitHeight: CGFloat { diameter * 0.58 }

    var body: some View {
        ZStack {
            orbitalPath(opacity: 0.55, lineWidth: 1.1)
                .blur(radius: 0.35)

            ambientRefraction
                .frame(width: diameter * 1.16, height: diameter * 1.16)

            glassSphere
                .frame(width: diameter, height: diameter)
                .zIndex(1)

            orbitalPath(opacity: 0.78, lineWidth: 0.8)
                .mask {
                    Ellipse()
                        .trim(from: 0.02, to: 0.48)
                        .stroke(style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: orbitWidth, height: orbitHeight)
                        .rotation3DEffect(.degrees(64), axis: (x: 1, y: 0, z: 0))
                        .rotationEffect(.degrees(-18))
                }
                .zIndex(2)

            satellite
                .offset(
                    x: CGFloat(cos(Double(orbitPhase))) * orbitWidth * 0.5,
                    y: CGFloat(sin(Double(orbitPhase))) * orbitHeight * 0.5
                )
                .rotation3DEffect(.degrees(64), axis: (x: 1, y: 0, z: 0))
                .rotationEffect(.degrees(-18))
                .zIndex(sin(Double(orbitPhase)) > 0 ? 3 : 0)
        }
        .frame(width: orbitWidth, height: diameter * 1.28)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mimir 赛博猫头鹰液态玻璃球")
        .onAppear {
            guard isAnimating, !reduceMotion else { return }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                orbitPhase = .pi * 2
            }
        }
    }

    private var glassSphere: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "342452").opacity(0.30),
                            Color(hex: "171126").opacity(0.48),
                            Color(hex: "100C1A").opacity(0.30)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: diameter * 0.55
                    )
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.17),
                            Color(hex: "C9AEFF").opacity(0.07),
                            violet.opacity(0.10),
                            Color.white.opacity(0.03)
                        ],
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

            MimirMascot(size: min(80, diameter * 0.48), mood: .calm, showsOrbit: false)
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

    private var satellite: some View {
        ZStack {
            Circle()
                .fill(iris.opacity(0.38))
                .frame(width: 18, height: 18)
                .blur(radius: 7)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white, iris, violet.opacity(0.7)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 6
                    )
                )
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.88), lineWidth: 0.6))
                .shadow(color: iris.opacity(0.95), radius: 6)
        }
        .frame(width: 20, height: 20)
        .allowsHitTesting(false)
    }

    private func orbitalPath(opacity: Double, lineWidth: CGFloat) -> some View {
        Ellipse()
            .stroke(
                AngularGradient(
                    colors: [
                        violet.opacity(0.12),
                        iris.opacity(opacity),
                        Color.white.opacity(opacity * 0.72),
                        iris.opacity(0.16),
                        violet.opacity(0.68),
                        violet.opacity(0.12)
                    ],
                    center: .center
                ),
                lineWidth: lineWidth
            )
            .frame(width: orbitWidth, height: orbitHeight)
            .rotation3DEffect(.degrees(64), axis: (x: 1, y: 0, z: 0))
            .rotationEffect(.degrees(-18))
            .shadow(color: violet.opacity(0.38), radius: 4)
            .allowsHitTesting(false)
    }
}
