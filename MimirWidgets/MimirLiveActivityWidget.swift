import ActivityKit
import SwiftUI
import WidgetKit
import AppIntents

/// Mimir 灵动岛与锁屏语音实时活动小组件（Cyber-Owl Live Activity & Timestamp Pin）。
public struct MimirLiveActivityWidget: Widget {

    // 核心品牌色
    private let irisViolet = Color(red: 0.49, green: 0.32, blue: 0.96) // #7D52F4
    private let deepPlumBase = Color(red: 0.07, green: 0.05, blue: 0.11) // #120D1D

    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: MimirActivityAttributes.self) { context in
            // 锁屏横幅卡片：高架浮动玻璃平板风格（#120D1D 基底，80% 透明度，玻璃边缘）
            lockScreenBannerView(context: context)
                .activityBackgroundTint(deepPlumBase.opacity(0.80))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开态（Expanded）
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        cyberOwlIcon(glow: context.state.owlGlow, size: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mimir 实时录音")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                            Text(context.state.statusText)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(irisViolet)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    // 活动经过时间计时器
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(irisViolet)
                        Text(formatDuration(context.state.audioElapsedSeconds))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        // 极简实时波形图 + 振幅指示
                        liveWaveformStage(levels: context.state.audioLevels)

                        // 交互式 "Pin Moment" 意图按钮
                        HStack {
                            if context.state.pinnedMomentsCount > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 9))
                                    Text("\(context.state.pinnedMomentsCount) 个高光点")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                }
                                .foregroundStyle(irisViolet)
                            }

                            Spacer(minLength: 0)

                            Button(intent: PinMomentIntent(sessionID: context.attributes.sessionID)) {
                                HStack(spacing: 5) {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Pin Moment")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(irisViolet))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                // 紧凑左前部：等比例缩放居中 Cyber-Owl 图标 + 细腻呼吸脉冲眼眸
                cyberOwlIcon(glow: context.state.owlGlow, size: 15)
            } compactTrailing: {
                // 紧凑右后部：微型 #7D52F4 3 柱音频波形振幅指示器
                miniEqualizerBars(levels: context.state.audioLevels)
            } minimal: {
                cyberOwlIcon(glow: 0.75, size: 14)
            }
            .keylineTint(irisViolet)
        }
    }

    // MARK: - 锁屏横幅（Lock Screen Banner）

    private func lockScreenBannerView(context: ActivityViewContext<MimirActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            // 左侧：猫头鹰发光徽章
            cyberOwlIcon(glow: context.state.owlGlow, size: 28)

            // 中央：转写状态与录音计时
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Mimir 录音会话")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)

                    Text(formatDuration(context.state.audioElapsedSeconds))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(irisViolet)
                }

                Text(context.state.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // 右侧：免解锁 "Pin Moment" 交互按钮
            Button(intent: PinMomentIntent(sessionID: context.attributes.sessionID)) {
                HStack(spacing: 5) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Pin Moment")
                        .font(.system(size: 11.5, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(irisViolet)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.8)
                        )
                )
            }
        }
        .padding(14)
        // 严格遵循：#120D1D 80% 透明度 + 玻璃边缘
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(deepPlumBase.opacity(0.80))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.38), irisViolet.opacity(0.50), Color.white.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - 辅助部件

    /// 赛博猫头鹰微图标 + 呼吸脉冲光晕
    private func cyberOwlIcon(glow: Double, size: CGFloat) -> some View {
        ZStack {
            Image(systemName: "bird.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(irisViolet)
                .shadow(color: irisViolet.opacity(min(max(glow, 0.4), 0.95)), radius: size * 0.45)
        }
        .frame(width: size + 4, height: size + 4)
    }

    /// 微型 3 柱音频波形振幅指示器（#7D52F4）
    private func miniEqualizerBars(levels: [Float]) -> some View {
        let l1 = CGFloat(levels.count > 0 ? levels[0] : 0.3)
        let l2 = CGFloat(levels.count > 1 ? levels[1] : 0.7)
        let l3 = CGFloat(levels.count > 2 ? levels[2] : 0.5)

        return HStack(alignment: .bottom, spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(irisViolet)
                .frame(width: 2.2, height: max(4, min(14, 4 + l1 * 10)))
            RoundedRectangle(cornerRadius: 1)
                .fill(irisViolet)
                .frame(width: 2.2, height: max(4, min(14, 4 + l2 * 10)))
            RoundedRectangle(cornerRadius: 1)
                .fill(irisViolet)
                .frame(width: 2.2, height: max(4, min(14, 4 + l3 * 10)))
        }
        .frame(height: 14)
    }

    /// 极简展开态实时波形条
    private func liveWaveformStage(levels: [Float]) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { i in
                let factor = CGFloat(sin(Double(i) * 0.4 + 1.2)) * 0.5 + 0.5
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(irisViolet.opacity(0.35 + factor * 0.65))
                    .frame(height: max(3, 16 * factor))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 18)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
