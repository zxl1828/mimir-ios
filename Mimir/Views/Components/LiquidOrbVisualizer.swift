import SwiftUI

/// 实时语音波形：以音频电平驱动振幅，并按显示器刷新节奏绘制。
public struct VoiceWaveformVisualizer: View {
    public var inputLevel: Double = 0
    public var outputLevel: Double = 0
    public var isSpeaking: Bool = false
    public var diameter: CGFloat = 200

    @Environment(\.colorScheme) private var colorScheme

    private let iris = Color(hex: "7D52F4")
    private let lavender = Color(hex: "B8A2FF")
    private let cyan = Color(hex: "68E1FD")
    private let magenta = Color(hex: "F86ECE")

    public init(
        inputLevel: Double = 0,
        outputLevel: Double = 0,
        isSpeaking: Bool = false,
        diameter: CGFloat = 200
    ) {
        self.inputLevel = inputLevel
        self.outputLevel = outputLevel
        self.isSpeaking = isSpeaking
        self.diameter = diameter
    }

    private var activity: Double {
        min(max(max(inputLevel, outputLevel), 0), 1)
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let dark = colorScheme == .dark

            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                iris.opacity(dark ? 0.36 : 0.20),
                                cyan.opacity(dark ? 0.14 : 0.09),
                                .clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: diameter * 0.78
                        )
                    )
                    .frame(width: diameter * 1.55, height: diameter * 0.7)
                    .blur(radius: 18)

                Canvas { context, size in
                    let midY = size.height * 0.5
                    let level = CGFloat(activity)
                    let baseAmplitude = size.height * (0.095 + level * 0.20)
                    let colors: [Color] = dark
                        ? [lavender, cyan, Color.white, magenta]
                        : [iris, cyan, Color.white, magenta]

                    for layer in 0..<4 {
                        let layerIndex = Double(layer)
                        let phase = time * (isSpeaking ? 2.1 : 1.45) + layerIndex * 1.32
                        let amplitude = baseAmplitude * CGFloat(1 - layerIndex * 0.16)
                        let thickness = CGFloat(2.5 - layerIndex * 0.35)
                        var centerLine = Path()
                        var band = Path()
                        let steps = 72

                        for step in 0...steps {
                            let progress = Double(step) / Double(steps)
                            let x = CGFloat(progress) * size.width
                            let envelope = pow(max(0, sin(progress * .pi)), 0.68)
                            let carrier = sin(progress * .pi * 3.25 + phase)
                            let overtone = cos(progress * .pi * 5.1 - phase * 0.72) * 0.23
                            let y = midY + CGFloat(carrier + overtone) * amplitude * CGFloat(envelope)
                            let point = CGPoint(x: x, y: y)

                            if step == 0 {
                                centerLine.move(to: point)
                                band.move(to: CGPoint(x: x, y: y - thickness * 2.2))
                            } else {
                                centerLine.addLine(to: point)
                                band.addLine(to: CGPoint(x: x, y: y - thickness * 2.2))
                            }
                        }

                        for step in stride(from: steps, through: 0, by: -1) {
                            let progress = Double(step) / Double(steps)
                            let x = CGFloat(progress) * size.width
                            let envelope = pow(max(0, sin(progress * .pi)), 0.68)
                            let carrier = sin(progress * .pi * 3.25 + phase)
                            let overtone = cos(progress * .pi * 5.1 - phase * 0.72) * 0.23
                            let y = midY + CGFloat(carrier + overtone) * amplitude * CGFloat(envelope)
                            band.addLine(to: CGPoint(x: x, y: y + thickness * 2.2))
                        }
                        band.closeSubpath()

                        let layerColor = colors[layer]
                        context.fill(
                            band,
                            with: .linearGradient(
                                Gradient(colors: [
                                    layerColor.opacity(dark ? 0.22 : 0.17),
                                    colors[(layer + 1) % colors.count].opacity(dark ? 0.12 : 0.09),
                                    .clear
                                ]),
                                startPoint: CGPoint(x: 0, y: 0),
                                endPoint: CGPoint(x: size.width, y: size.height)
                            )
                        )
                        context.stroke(
                            centerLine,
                            with: .linearGradient(
                                Gradient(colors: [
                                    colors[(layer + 1) % colors.count].opacity(0.62),
                                    layerColor.opacity(0.98),
                                    Color.white.opacity(dark ? 0.88 : 0.94),
                                    colors[(layer + 2) % colors.count].opacity(0.86)
                                ]),
                                startPoint: CGPoint(x: 0, y: midY - amplitude),
                                endPoint: CGPoint(x: size.width, y: midY + amplitude)
                            ),
                            style: StrokeStyle(lineWidth: layer == 0 ? 3.2 : 1.8, lineCap: .round, lineJoin: .round)
                        )
                    }

                    for index in 0..<14 {
                        let seed = Double(index) * 2.13
                        let drift = sin(time * 0.72 + seed) * 0.5 + 0.5
                        let x = size.width * CGFloat(0.12 + 0.76 * drift)
                        let y = midY + CGFloat(cos(time * 1.1 + seed)) * size.height * 0.30
                        let radius = CGFloat(0.8 + drift * 1.0)
                        let point = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                        context.fill(point, with: .color((dark ? lavender : iris).opacity(0.25 + drift * 0.42)))
                    }
                }
                .frame(height: max(100, diameter * 0.82))
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(104, diameter * 0.88))
            .accessibilityLabel(isSpeaking ? "Mimir 正在播放语音" : "实时语音波形")
        }
    }
}
