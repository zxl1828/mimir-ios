import SwiftUI

/// 1:1 复刻实机参考图的「思考强度浮动卡片」（含大号发光档位标题、模型切换行、星尘阶梯滑块）。
struct ReasoningEffortCard: View {

    @Binding var level: ThinkingMode
    let options: [ModelCatalog.Option]
    @Binding var selectedModelID: String
    var onOpenSettings: () -> Void = {}

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            // 1. 顶部居中大字档位标题（High / X-High / Ultra），带霓虹紫辉光
            Text(level.heroTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: "281F36"),
                            accent,
                            AppUI.neonViolet
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: accent.opacity(0.38), radius: 12, y: 0)
                .shadow(color: AppUI.neonViolet.opacity(0.20), radius: 22, y: 2)
                .contentTransition(.numericText())
                .animation(AppUI.snap, value: level)

            // 2. 居中模型选择行：[当前模型名称] >
            Menu {
                ForEach(options) { option in
                    Button {
                        Haptics.selectionChanged()
                        selectedModelID = option.id
                    } label: {
                        HStack {
                            Text(option.title)
                            if option.id == selectedModelID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button {
                    onOpenSettings()
                } label: {
                    Label("自定义模型与参数…", systemImage: "slider.horizontal.3")
                }
            } label: {
                HStack(spacing: 5) {
                    Text(ModelCatalog.cardLabel(for: selectedModelID))
                        .font(.system(size: 14.5, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(Color(hex: "51465F"))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)

            // 3. 星尘阶梯滑轨（Stepped Stardust Slider）
            ReasoningEffortSlider(level: $level)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: 296)
        .background {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            shape.fill(.ultraThinMaterial)
                .overlay {
                    shape.fill(
                        scheme == .dark
                            ? Color(hex: "F8F6FD").opacity(0.90)
                            : Color.white.opacity(0.85)
                    )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.70), accent.opacity(0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .shadow(
            color: Color(hex: "5A3E85").opacity(scheme == .dark ? 0.22 : 0.07),
            radius: 22,
            y: 12
        )
        .shadow(color: accent.opacity(scheme == .dark ? 0.22 : 0.10), radius: 16, y: 5)
    }
}

/// 实机 1:1 星尘阶梯滑块（Stepped Stardust Slider）。
///
/// 加厚胶囊轨道 + 电光紫渐变激活段 + 星座连线与微光星尘纹理 + 离散停靠刻度点 + 纯白立体圆钮。
/// 严格限定四档思考：`Light` / `High` / `X-High` / `Max (Ultra)`，全部档位均执行推理，绝不引入"不思考"模式。
struct ReasoningEffortSlider: View {

    @Binding var level: ThinkingMode

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    /// 拖动过程中显示连续位置；松手后平滑吸附到四档停靠点。
    @State private var dragProgress: Double?

    private static let trackHeight: CGFloat = 40
    private static let thumbDiameter: CGFloat = 34
    private static let horizontalPadding: CGFloat = 3

    /// 四档停靠在轨道上的归一化位置：让每档都有对应的星尘轨迹段（0.0 ~ 1.0 严格对称动态映射）。
    static func progress(for mode: ThinkingMode) -> Double {
        let all = ThinkingMode.allCases
        guard let index = all.firstIndex(of: mode), all.count > 1 else { return 0.0 }
        return Double(index) / Double(all.count - 1)
    }

    static func nearest(_ progress: Double) -> ThinkingMode {
        let all = ThinkingMode.allCases
        guard all.count > 1 else { return all.first ?? .thinking }
        let index = Int(round(progress * Double(all.count - 1)))
        let clamped = min(max(index, 0), all.count - 1)
        return all[clamped]
    }

    private var currentProgress: Double {
        dragProgress ?? Self.progress(for: level)
    }

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width, 0)
            let thumbDiameter = Self.thumbDiameter
            let horizontalPadding = Self.horizontalPadding
            let maxOffset = max(trackWidth - thumbDiameter - (horizontalPadding * 2), 0)

            let progress = currentProgress
            let currentOffset = progress * maxOffset
            let thumbCenterX = horizontalPadding + currentOffset + (thumbDiameter / 2)
            let activeWidth = thumbDiameter + currentOffset

            ZStack(alignment: .leading) {
                // 1. 未激活底轨（透光白紫玻璃）
                inactiveTrack

                // 2. 左侧电光紫激活段 + 星尘与星座连线纹理
                activeStardustSegment(
                    width: activeWidth,
                    height: Self.trackHeight - (horizontalPadding * 2),
                    padding: horizontalPadding
                )

                // 3. 轨道内的离散刻度点（7 颗微点，其中 4 颗对应主档位）
                tickDotsLayer(
                    horizontalPadding: horizontalPadding,
                    maxOffset: maxOffset,
                    thumbDiameter: thumbDiameter,
                    thumbCenterX: thumbCenterX
                )

                // 4. 纯白立体圆钮（White Circular Thumb）
                whiteThumb
                    .offset(x: horizontalPadding + currentOffset)
            }
            .frame(width: trackWidth, height: Self.trackHeight)
            .contentShape(Capsule(style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard maxOffset > 0 else { return }
                        let touchOffset = value.location.x - horizontalPadding - (thumbDiameter / 2)
                        let clampedOffset = min(max(touchOffset, 0), maxOffset)
                        let normalizedProgress = clampedOffset / maxOffset
                        dragProgress = normalizedProgress
                        let snapped = Self.nearest(normalizedProgress)
                        if snapped != level {
                            level = snapped
                        }
                    }
                    .onEnded { value in
                        guard maxOffset > 0 else {
                            dragProgress = nil
                            return
                        }
                        let momentum = (value.predictedEndTranslation.width - value.translation.width) * 0.12
                        let touchOffset = value.location.x + momentum - horizontalPadding - (thumbDiameter / 2)
                        let clampedOffset = min(max(touchOffset, 0), maxOffset)
                        let normalizedProgress = clampedOffset / maxOffset
                        let snapped = Self.nearest(normalizedProgress)
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                            level = snapped
                            dragProgress = nil
                        }
                    }
            )
            .animation(dragProgress == nil ? AppUI.snap : nil, value: currentOffset)
        }
        .frame(height: Self.trackHeight)
        .sensoryFeedback(.selection, trigger: level)
        .accessibilityElement()
        .accessibilityLabel("思考强度")
        .accessibilityValue(level.heroTitle)
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

    // MARK: - 滑轨子层

    private var inactiveTrack: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                Capsule(style: .continuous)
                    .fill(
                        scheme == .dark
                            ? Color(hex: "F8F6FD").opacity(0.90)
                            : Color.white.opacity(0.85)
                    )
            }
            .overlay(alignment: .trailing) {
                // 右侧微弱算力芯片水印图标（对应实机截图滑轨右侧的暗纹）
                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(
                        accent.opacity(0.22)
                    )
                    .padding(.trailing, 20)
            }
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.70), accent.opacity(scheme == .dark ? 0.22 : 0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }

    private func activeStardustSegment(width: CGFloat, height: CGFloat, padding: CGFloat) -> some View {
        let segmentWidth = max(width, height)
        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.85),
                            accent,
                            accent.opacity(0.65)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            // 星座连线 + 微型星尘粒子纹理
            StardustTrackCanvas(
                intensity: level == .light ? 0.45 : (level == .thinking ? 0.68 : (level == .expert ? 0.88 : 1.0)),
                accent: accent
            )
            .clipShape(Capsule(style: .continuous))
        }
        .frame(width: segmentWidth, height: height)
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.7)
        )
        .padding(.leading, padding)
        .shadow(color: accent.opacity(scheme == .dark ? 0.60 : 0.32), radius: 10, x: 0, y: 2)
    }

    private func tickDotsLayer(
        horizontalPadding: CGFloat,
        maxOffset: CGFloat,
        thumbDiameter: CGFloat,
        thumbCenterX: CGFloat
    ) -> some View {
        let totalDots = 7
        let stops: [Double] = (0..<totalDots).map { Double($0) / Double(totalDots - 1) }
        let majorIndices: Set<Int> = [0, 2, 4, 6] // 对应 Light (0), High (2), X-High (4), Max/Ultra (6)

        return ZStack(alignment: .leading) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                let x = horizontalPadding + (CGFloat(stop) * maxOffset) + (thumbDiameter / 2)
                let isCoveredByThumb = abs(x - thumbCenterX) < thumbDiameter * 0.45
                let isActive = x <= thumbCenterX
                let isMajor = majorIndices.contains(index)
                let dotSize: CGFloat = isMajor ? 5.2 : 4.0

                Circle()
                    .fill(
                        isActive
                            ? Color.white.opacity(isMajor ? 0.88 : 0.55)
                            : accent.opacity(isMajor ? 0.35 : 0.20)
                    )
                    .frame(width: dotSize, height: dotSize)
                    .offset(x: x - dotSize / 2)
                    .opacity(isCoveredByThumb ? 0 : 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private var whiteThumb: some View {
        Circle()
            .fill(Color.white)
            .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 1)
            )
            .shadow(color: accent.opacity(0.16), radius: 4, x: 0, y: 1)
            .shadow(color: accent.opacity(0.45), radius: 8, x: 0, y: 0)
    }
}

/// 激活滑轨内部的星座连线与微光星尘绘制层（复刻实机参考图的星图细节）。
private struct StardustTrackCanvas: View {

    var intensity: Double = 1.0
    var accent: Color = .purple

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            guard w > 24 else { return }

            // 1. 星座折线（仿参考图左上至中段的星图连线）
            let constellation: [(CGFloat, CGFloat)] = [
                (0.14, 0.42),
                (0.24, 0.26),
                (0.35, 0.34),
                (0.46, 0.22),
                (0.58, 0.38)
            ]
            var linePath = Path()
            for (index, pt) in constellation.enumerated() {
                let p = CGPoint(x: pt.0 * w, y: pt.1 * h)
                if index == 0 {
                    linePath.move(to: p)
                } else {
                    linePath.addLine(to: p)
                }
            }
            context.stroke(
                linePath,
                with: .color(Color.white.opacity(0.32 * intensity)),
                lineWidth: 0.75
            )

            for pt in constellation {
                let p = CGPoint(x: pt.0 * w, y: pt.1 * h)
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6)),
                    with: .color(Color.white.opacity(0.78 * intensity))
                )
            }

            // 2. 散布的星尘微粒与十字微星
            let dust: [(CGFloat, CGFloat, CGFloat)] = [
                (0.09, 0.68, 1.1),
                (0.19, 0.76, 1.4),
                (0.29, 0.62, 1.0),
                (0.41, 0.78, 1.6),
                (0.52, 0.66, 1.2),
                (0.66, 0.28, 1.5),
                (0.74, 0.72, 1.3),
                (0.84, 0.32, 1.4)
            ]
            for (rx, ry, r) in dust {
                let p = CGPoint(x: rx * w, y: ry * h)
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                    with: .color(Color.white.opacity(0.55 * intensity))
                )
            }

            // 两颗四角微星
            for starPt in [CGPoint(x: 0.39 * w, y: 0.74 * h), CGPoint(x: 0.68 * w, y: 0.30 * h)] {
                var star = Path()
                let sr: CGFloat = 2.8
                star.move(to: CGPoint(x: starPt.x, y: starPt.y - sr))
                star.addLine(to: CGPoint(x: starPt.x, y: starPt.y + sr))
                star.move(to: CGPoint(x: starPt.x - sr, y: starPt.y))
                star.addLine(to: CGPoint(x: starPt.x + sr, y: starPt.y))
                context.stroke(star, with: .color(Color.white.opacity(0.75 * intensity)), lineWidth: 0.8)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 底部输入框上方的思考状态胶囊（对应参考图 1 底部的 `DeepSeek-V4.1-Flash Ultra` 胶囊）。
///
/// 点击可展开 / 收起上方的 `ReasoningEffortCard` 星尘浮动卡片。
struct ReasoningStatusChip: View {

    let modelID: String
    let level: ThinkingMode
    let isExpanded: Bool
    var action: () -> Void

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)

                Text("\(ModelCatalog.cardLabel(for: modelID))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppUI.label)
                    .lineLimit(1)

                Text(level.heroTitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(accent.opacity(scheme == .dark ? 0.22 : 0.14))
                    )

                // 右侧立体微光圆珠（对应参考图胶囊右侧的圆球指示器）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white,
                                scheme == .dark ? Color.white.opacity(0.86) : accent.opacity(0.45)
                            ],
                            center: .topLeading,
                            startRadius: 1,
                            endRadius: 14
                        )
                    )
                    .frame(width: 18, height: 18)
                    .shadow(color: accent.opacity(isExpanded ? 0.65 : 0.25), radius: 4, y: 1)
            }
            .padding(.leading, 11)
            .padding(.trailing, 7)
            .padding(.vertical, 6)
            .liquidGlass(
                .regular.tint(accent.opacity(isExpanded ? 0.35 : 0.15)),
                in: .capsule
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isExpanded
                            ? AnyShapeStyle(accent.opacity(0.85))
                            : AnyShapeStyle(AppUI.refractionEdge(accent, scheme: scheme)),
                        lineWidth: isExpanded ? 1.2 : 0.9
                    )
            )
            .shadow(
                color: isExpanded ? accent.opacity(scheme == .dark ? 0.42 : 0.22) : accent.opacity(scheme == .dark ? 0.20 : 0.08),
                radius: isExpanded ? 10 : 5,
                y: 2
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityLabel("思考强度与模型：\(ModelCatalog.cardLabel(for: modelID)) \(level.heroTitle)")
    }
}
