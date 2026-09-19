import SwiftUI
import UIKit

/// 思考模式滑块。
///
/// 收起时是输入框上方的小状态胶囊，点开后是横向滑块；
/// 轨道填充色随位置冷 → 暖插值，Ultra 档带一整套持续动效。
struct ThinkingModeSlider: View {

    @Binding var selection: ThinkingMode

    @State private var isPresented = false
    @State private var progress: Double = 0
    @State private var isDragging = false
    @State private var stretch: CGFloat = 0
    @State private var lastHapticIndex = -1
    @State private var haloScale: CGFloat = 0.8
    @State private var haloOpacity: Double = 0
    @State private var breath = false

    private let indicatorSize: CGFloat = 34
    private let trackHeight: CGFloat = 44

    private var isUltra: Bool { selection == .ultra }

    var body: some View {
        Button {
            Haptics.impact(.light)
            isPresented.toggle()
        } label: {
            capsuleLabel
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            panel
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.clear)
        }
        .onAppear {
            progress = selection.normalized
            lastHapticIndex = ThinkingMode.allCases.firstIndex(of: selection) ?? 0
        }
        .onChange(of: selection) { _, newValue in
            guard !isDragging else { return }
            withAnimation(AppAnimation.thinkingSnap) {
                progress = newValue.normalized
            }
        }
    }

    // MARK: - 收起状态

    private var capsuleLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: selection.systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(selection.shortTitle)
                .font(AppFont.chipCompact)
        }
        .foregroundStyle(selection.tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule(style: .continuous).fill(selection.tint.opacity(0.14)))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(selection.tint.opacity(0.38), lineWidth: 0.8)
        )
        .background { if isUltra { bloomLayer } }
        .overlay { if isUltra { particleLayer } }
        // 收起状态不再做呼吸缩放 / 扫光：之前 Max 标签会一直抽搐闪烁。
        .shadow(color: isUltra ? selection.tint.opacity(0.28) : .clear, radius: 10)
        .onAppear { startBreathingIfNeeded() }
        .onChange(of: selection) { _, _ in startBreathingIfNeeded() }
    }

    private var shimmerMask: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isUltra)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.85), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 70)
            .offset(x: -35 + CGFloat(phase) * 70)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }

    /// Max 档：中心铺开的暖色泛光（进入档位时放大到位，离开即消失）。
    private var bloomLayer: some View {
        RadialGradient(
            colors: [selection.tint.opacity(0.55), selection.tint.opacity(0.0)],
            center: .center,
            startRadius: 2,
            endRadius: 52
        )
        .scaleEffect(breath ? 1.16 : 0.92)
        .opacity(breath ? 0.9 : 0.4)
        .animation(AppAnimation.ultraBreath, value: breath)
        .allowsHitTesting(false)
    }

    /// Max 档：10 颗光粒按固定随机角度向外飘散（Canvas 绘制，离开档位时间线暂停）。
    private var particleLayer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isUltra)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for index in 0..<10 {
                    let seed = Double(index)
                    let angle = seed * 2.3999632
                    let speed = 0.32 + (seed.truncatingRemainder(dividingBy: 3)) * 0.13
                    let progress = (time * speed + seed * 0.37).truncatingRemainder(dividingBy: 1)
                    let distance = 9 + progress * 30
                    let dot = 1.1 + (1 - progress) * 2.2
                    let point = CGPoint(
                        x: center.x + CGFloat(cos(angle) * distance),
                        y: center.y + CGFloat(sin(angle) * distance * 0.62)
                    )
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: point.x - dot,
                                y: point.y - dot,
                                width: dot * 2,
                                height: dot * 2
                            )
                        ),
                        with: .color(selection.tint.opacity(0.6 * (1 - progress)))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func startBreathingIfNeeded() {
        if isUltra {
            withAnimation(AppAnimation.ultraBreath) { breath = true }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { breath = false }
        }
    }

    // MARK: - 展开面板

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("思考程度")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .overlay { if isUltra { shimmerMask } }
                Spacer(minLength: 8)
                Text(selection.subtitle)
                    .font(AppFont.hint)
                    .foregroundStyle(AppColor.secondaryText)
            }

            track

            HStack(spacing: 0) {
                ForEach(ThinkingMode.allCases) { mode in
                    Button {
                        Haptics.selectionChanged()
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(AppAnimation.thinkingSnap) {
                            selection = mode
                            progress = mode.normalized
                        }
                        if mode == .ultra { triggerUltraFeedback() }
                    } label: {
                        Text(mode.shortTitle)
                            .font(.system(size: 12, weight: selection == mode ? .semibold : .regular))
                            .foregroundStyle(selection == mode ? mode.tint : AppColor.secondaryText)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .liquidGlass(.regular, in: .rect(cornerRadius: 20))
        .glassHairline(cornerRadius: 20)
        .padding(1)
    }

    private var track: some View {
        GeometryReader { proxy in
            // 指示器圆心与下方四个标签的中心对齐（标签是四等分居中排列），
            // 这样两端不会一边空一边挤。
            let width = proxy.size.width
            let centerX = width * (0.125 + 0.75 * CGFloat(progress))

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(AppColor.secondaryText.opacity(0.16))

                Capsule(style: .continuous)
                    .fill(fillGradient)
                    .frame(width: max(centerX, indicatorSize))

                if isUltra {
                    flowingOverlay(width: proxy.size.width)
                }

                indicator(centerX: centerX)

                if isUltra {
                    particleField(indicatorX: centerX - indicatorSize / 2, size: proxy.size)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: trackHeight)
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppColor.thinkingTrackColor(progress: 0),
                AppColor.thinkingTrackColor(progress: progress)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func flowingOverlay(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isUltra)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: AppAnimation.ultraFlowDuration) / AppAnimation.ultraFlowDuration
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.5), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.45)
            .offset(x: -width * 0.45 + CGFloat(phase) * width * 1.45)
            .mask(Capsule(style: .continuous))
            .allowsHitTesting(false)
        }
        .frame(width: width)
    }

    private func indicator(centerX: CGFloat) -> some View {
        // 形变收敛一些：之前拉长时圆会被压得很扁。
        let stretchX = 1 + (isDragging ? stretch : 0)
        let stretchY = 1 - (isDragging ? stretch * 0.22 : 0)

        return Circle()
            .fill(.clear)
            .liquidGlass(.regular.tint(selection.tint).interactive(), in: .circle)
            .frame(width: indicatorSize, height: indicatorSize)
            .scaleEffect(x: stretchX, y: stretchY)
            .shadow(color: selection.tint.opacity(isUltra ? 0.55 : 0.28), radius: isUltra ? 16 : 8)
            .offset(x: centerX - indicatorSize / 2)
            .animation(AppAnimation.thinkingSnap, value: isDragging)
            .overlay(alignment: .center) {
                Circle()
                    .stroke(selection.tint.opacity(0.35), lineWidth: 1)
                    .frame(width: indicatorSize - 6, height: indicatorSize - 6)
                    .scaleEffect(haloScale)
                    .opacity(haloOpacity)
                    .offset(x: centerX - indicatorSize / 2)
                    .allowsHitTesting(false)
            }
    }

    private func particleField(indicatorX: CGFloat, size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isUltra)) { timeline in
            Canvas { context, canvasSize in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<10 {
                    let seed = Double(index) * 0.83
                    let angle = seed * 2.1 + time * 0.7
                    let radius = 16 + sin(time * 1.2 + seed) * 8
                    let x = indicatorX + CGFloat(cos(angle) * radius)
                    let y = canvasSize.height / 2 + CGFloat(sin(angle) * radius * 0.6)
                    let dot = 1.2 + CGFloat(index % 3) * 0.6
                    let alpha = 0.35 + 0.3 * sin(time * 1.6 + seed)

                    context.fill(
                        Path(ellipseIn: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)),
                        with: .color(AppColor.thinkingWarm.opacity(max(alpha, 0)))
                    )
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    Haptics.impact(.light)
                }
                // 与指示器轨迹同一套映射：0.125 → 0.875。
                let raw = (Double(value.location.x) / Double(max(width, 1)) - 0.125) / 0.75
                progress = min(max(Double(raw), 0), 1)

                let horizontalTravel = abs(value.translation.width)
                stretch = min(horizontalTravel / 180, 0.16)

                let candidate = ThinkingMode.nearest(progress: progress)
                let index = ThinkingMode.allCases.firstIndex(of: candidate) ?? 0
                if index != lastHapticIndex {
                    lastHapticIndex = index
                    Haptics.selectionChanged()
                }
            }
            .onEnded { _ in
                isDragging = false
                let snapped = ThinkingMode.nearest(progress: progress)
                withAnimation(AppAnimation.thinkingSnap) {
                    stretch = 0
                    progress = snapped.normalized
                    selection = snapped
                }
                Haptics.selectionChanged()
                if snapped == .ultra { triggerUltraFeedback() }
            }
    }

    private func triggerUltraFeedback() {
        Haptics.impact(.heavy)
        Haptics.notify(.success)
        haloScale = 0.8
        haloOpacity = 0.9
        withAnimation(AppAnimation.glow) {
            haloScale = 2.2
            haloOpacity = 0
        }
    }
}

extension AppAnimation {
    /// Ultra 流光循环周期（秒），供 TimelineView 计算相位。
    static let ultraFlowDuration: Double = 2.4
}
