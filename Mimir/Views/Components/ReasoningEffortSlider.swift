import SwiftUI

/// 思考强度阶梯滑块（Codex 桌面端的 Reasoning Effort）。
///
/// 微型液态玻璃滑轨 + 三个物理停靠刻度（High / X-High / Max），
/// 游标是内嵌脑波图标的发光圆钮；拖动或点按都会平滑吸附到最近刻度，
/// 每次换档都有触觉反馈。直接绑定真实的 `ThinkingMode`，改完立即作用于下一次请求。
struct ReasoningEffortSlider: View {

    @Binding var level: ThinkingMode

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    /// 拖动过程中显示连续位置；松手后回到档位停靠点。
    @State private var dragProgress: Double?

    private static let trackWidth: CGFloat = 118
    private static let thumbSize: CGFloat = 26
    private static let trackHeight: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let inset = Self.thumbSize / 2
            let usable = max(proxy.size.width - inset * 2, 1)
            let progress = currentProgress
            let thumbX = inset + usable * progress

            ZStack(alignment: .leading) {
                track

                Capsule(style: .continuous)
                    .fill(accent.opacity(0.9))
                    .frame(width: max(thumbX, Self.trackHeight), height: Self.trackHeight)
                    .shadow(color: accent.opacity(0.65), radius: 6)

                ForEach(Array(ThinkingMode.allCases.enumerated()), id: \.offset) { index, mode in
                    let stopX = inset + usable * Self.progress(for: mode)
                    Circle()
                        .fill(Color.white.opacity(level == mode ? 0 : 0.55))
                        .frame(width: 3, height: 3)
                        .offset(x: stopX - 1.5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                thumb
                    .offset(x: thumbX - inset)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let raw = (value.location.x - inset) / usable
                        let clamped = min(max(raw, 0), 1)
                        dragProgress = clamped
                        let nearest = Self.nearest(clamped)
                        if nearest != level {
                            level = nearest
                        }
                    }
                    .onEnded { _ in
                        withAnimation(AppUI.snap) { dragProgress = nil }
                    }
            )
        }
        .frame(width: Self.trackWidth, height: Self.thumbSize)
        .sensoryFeedback(.selection, trigger: level)
        .accessibilityElement()
        .accessibilityLabel("思考强度")
        .accessibilityValue(level.title)
        .accessibilityAdjustableAction { direction in
            let all = ThinkingMode.allCases
            guard let index = all.firstIndex(of: level) else { return }
            switch direction {
            case .increment:
                if index + 1 < all.count { level = all[index + 1] }
            case .decrement:
                if index > 0 { level = all[index - 1] }
            @unknown default:
                return
            }
        }
    }

    // MARK: - 部件

    private var track: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(height: Self.trackHeight)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
            )
    }

    private var thumb: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
            Circle()
                .strokeBorder(accent.opacity(0.5), lineWidth: 1)
                .blur(radius: 0.6)
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent)
        }
        .frame(width: Self.thumbSize, height: Self.thumbSize)
        .shadow(color: accent.opacity(0.55), radius: 9)
        .scaleEffect(dragProgress == nil ? 1 : 1.08)
    }

    // MARK: - 档位几何

    private var currentProgress: Double {
        dragProgress ?? Self.progress(for: level)
    }

    /// 三档均分：High = 0、X-High = 0.5、Max = 1。
    static func progress(for mode: ThinkingMode) -> Double {
        let all = ThinkingMode.allCases
        guard let index = all.firstIndex(of: mode), all.count > 1 else { return 0 }
        return Double(index) / Double(all.count - 1)
    }

    static func nearest(_ progress: Double) -> ThinkingMode {
        let all = ThinkingMode.allCases
        guard all.count > 1 else { return all.first ?? .thinking }
        let scaled = progress * Double(all.count - 1)
        let index = Int(scaled.rounded())
        return all[min(max(index, 0), all.count - 1)]
    }
}

private struct ReasoningEffortSliderPreviewHost: View {

    @State private var level: ThinkingMode = .expert

    var body: some View {
        VStack(spacing: 20) {
            ReasoningEffortSlider(level: $level)
            Text(level.title).font(AppUI.footnote).foregroundStyle(AppUI.label2)
        }
        .padding(30)
    }
}

#Preview {
    ReasoningEffortSliderPreviewHost()
}
