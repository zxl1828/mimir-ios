import SwiftUI
import UIKit

/// 语音球：屏幕中央的液态玻璃球体，形状与光效随会话状态变化。
struct VoiceOrb: View {

    let state: VoiceSessionState
    var inputLevel: Double = 0
    var outputLevel: Double = 0
    var diameter: CGFloat = 190

    @State private var ripple: CGFloat = 0
    @State private var rippleOpacity: Double = 0
    @State private var spin: Double = 0
    @State private var breath = false
    @State private var flash = false

    private var tint: Color {
        switch state {
        case .idle, .unavailable: return AppColor.secondaryText
        case .listening, .transcribing: return AppColor.listening
        case .thinking: return AppColor.thinking
        case .speaking: return AppColor.speaking
        case .interrupted: return AppColor.interrupted
        }
    }

    private var reactiveLevel: Double {
        switch state {
        case .listening, .transcribing: return inputLevel
        case .speaking: return outputLevel
        default: return 0
        }
    }

    var body: some View {
        ZStack {
            rippleLayer
            glowLayer
            orbBody
            innerWave
            if state == .speaking { particleLayer }
        }
        .frame(width: diameter * 2, height: diameter * 2)
        .animation(AppAnimation.orbPulse, value: inputLevel)
        .animation(AppAnimation.orbPulse, value: outputLevel)
        .onAppear { startContinuousAnimations() }
        .onChange(of: state) { _, _ in startContinuousAnimations() }
    }

    // MARK: - 层

    private var orbBody: some View {
        Circle()
            .fill(.clear)
            .liquidGlass(.regular.tint(tint.opacity(0.45)).interactive(), in: .circle)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [tint.opacity(0.75), tint.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .scaleEffect(scaleFactor)
            .rotationEffect(.degrees(state == .thinking ? spin : 0))
            .shadow(color: tint.opacity(0.45), radius: 34)
            .overlay {
                if flash {
                    Circle()
                        .fill(AppColor.interrupted.opacity(0.35))
                        .frame(width: diameter, height: diameter)
                }
            }
    }

    private var scaleFactor: CGFloat {
        var value = 1.0
        if state == .thinking && breath { value += 0.04 }
        if state == .speaking { value += min(outputLevel, 1) * 0.10 }
        if state == .listening { value += min(inputLevel, 1) * 0.08 }
        return value
    }

    private var rippleLayer: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .stroke(tint.opacity(0.5), lineWidth: 1.2)
                    .frame(width: diameter * (0.9 + ripple + CGFloat(index) * 0.35))
                    .opacity(rippleOpacity * (index == 0 ? 1 : 0.6))
            }
        }
        .opacity(state == .listening ? 1 : 0.25)
    }

    private var glowLayer: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(0.45), tint.opacity(0.0)],
                    center: .center,
                    startRadius: diameter * 0.2,
                    endRadius: diameter * 1.1
                )
            )
            .frame(width: diameter * 2, height: diameter * 2)
            .scaleEffect(state == .thinking && breath ? 1.08 : 0.98)
    }

    private var innerWave: some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [
                        tint.opacity(0.0),
                        tint.opacity(0.55),
                        tint.opacity(0.0),
                        tint.opacity(0.35),
                        tint.opacity(0.0)
                    ],
                    center: .center
                )
            )
            .frame(width: diameter * 0.62, height: diameter * 0.62)
            .rotationEffect(.degrees(spin))
            .blur(radius: 8)
            .opacity(state == .thinking || state == .speaking ? 1 : 0.35)
    }

    private var particleLayer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for index in 0..<12 {
                    let seed = Double(index) * 0.71
                    let angle = seed * 2.3 + time * 0.9
                    let radius = diameter * 0.62 + sin(time * 1.4 + seed) * 14
                    let point = CGPoint(
                        x: center.x + CGFloat(cos(angle) * radius),
                        y: center.y + CGFloat(sin(angle) * radius)
                    )
                    let dot = 1.4 + CGFloat(index % 3) * 0.7
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)),
                        with: .color(AppColor.speaking.opacity(0.55))
                    )
                }
            }
        }
        .frame(width: diameter * 2, height: diameter * 2)
        .allowsHitTesting(false)
    }

    // MARK: - 动画

    private func startContinuousAnimations() {
        ripple = 0
        rippleOpacity = 0.8
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            ripple = 0.55
            rippleOpacity = 0
        }

        spin = 0
        withAnimation(AppAnimation.orbSlowSpin) { spin = 360 }

        if state == .thinking || state == .speaking {
            withAnimation(AppAnimation.ultraBreath) { breath = true }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { breath = false }
        }

        if state == .interrupted {
            flash = true
            withAnimation(.easeOut(duration: 0.35)) { flash = false }
        }
    }
}
