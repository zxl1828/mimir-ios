import SwiftUI

/// 双流模型竞技场（Split-Prism Arena：光学棱镜对比视窗）。
///
/// 核心特性：
/// 1. 采用光学棱镜双层重叠排版：通过 `.mask()` 精确控制左右两侧模型流式输出的可见切面；
/// 2. 交互式垂直分割条（`PrismDividerView`）：2.5pt 垂直液态玻璃条 + `#7D52F4` 焦散高光；
/// 3. 严格限制于 X 轴的拖拽手势：动态实时揭示左侧模型 A 与右侧模型 B 的生成细节；
/// 4. 阈值锁定与分支合并：当分割条拖动越过 85% 屏幕宽度（或低于 15%）时，自动将优势模型锁定为胜出分支，折叠并丢弃对立分支。
public struct SplitPrismArenaView: View {

    public let modelAName: String
    public let modelBName: String
    public let responseA: String
    public let responseB: String
    public let isStreaming: Bool
    public let onSelectWinner: (String, String) -> Void
    public let onDismiss: () -> Void

    @Environment(\.colorScheme) private var scheme
    private let irisViolet = Color(hex: "7D52F4")
    private let deepPlumBase = Color(hex: "120D1D")
    private let paleLavender = Color(hex: "F8F6FD")
    private let electricViolet = Color(hex: "9B70FF")

    /// 分割线位置（0.0 ~ 1.0），默认居中 0.5
    @State private var splitRatio: CGFloat = 0.5
    @State private var lockedWinner: String? = nil
    @State private var isDragging: Bool = false

    public init(
        modelAName: String = "Claude 3.5 Sonnet",
        modelBName: String = "GPT-4o Mini",
        responseA: String,
        responseB: String,
        isStreaming: Bool = false,
        onSelectWinner: @escaping (String, String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.modelAName = modelAName
        self.modelBName = modelBName
        self.responseA = responseA
        self.responseB = responseB
        self.isStreaming = isStreaming
        self.onSelectWinner = onSelectWinner
        self.onDismiss = onDismiss
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let totalHeight = geometry.size.height
            let dividerX = totalWidth * splitRatio

            ZStack(alignment: .topLeading) {
                // 底层基底（严格遵循 Design DNA：深李色 #120D1D 85% + ultraThinMaterial）
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(deepPlumBase.opacity(0.92))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.38),
                                        irisViolet.opacity(0.60),
                                        Color.white.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    }

                // ① 模型 A 层（左侧主位，由 leading mask 裁切）
                modelStreamContent(
                    modelName: modelAName,
                    content: responseA,
                    badgeColor: irisViolet,
                    alignment: .leading
                )
                .frame(width: totalWidth, height: totalHeight)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: max(0, dividerX), height: totalHeight)
                }

                // ② 模型 B 层（右侧对位，由 trailing mask 裁切）
                modelStreamContent(
                    modelName: modelBName,
                    content: responseB,
                    badgeColor: electricViolet,
                    alignment: .trailing
                )
                .frame(width: totalWidth, height: totalHeight)
                .mask(alignment: .trailing) {
                    Rectangle()
                        .frame(width: max(0, totalWidth - dividerX), height: totalHeight)
                }

                // ③ 垂直光学棱镜分割条（PrismDividerView，2.5pt 宽，#7D52F4 焦散高光）
                PrismDividerView(
                    height: totalHeight,
                    isDragging: isDragging,
                    splitRatio: splitRatio
                )
                .offset(x: dividerX - 18) // 居中 36pt 手势触摸热区
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let newX = value.location.x
                            let ratio = max(0.05, min(0.95, newX / totalWidth))
                            splitRatio = ratio

                            // 触达 85% 阈值反馈
                            if ratio >= 0.85 || ratio <= 0.15 {
                                Haptics.impact(.medium)
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                            evaluateWinnerLock()
                        }
                )

                // ④ 顶栏标题与关闭入口
                arenaHeader
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: irisViolet.opacity(0.30), radius: 24, y: 10)
        }
        .frame(maxHeight: 520)
        .padding(.horizontal, 14)
    }

    // MARK: - 顶栏

    private var arenaHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(irisViolet.opacity(0.25)).frame(width: 24, height: 24)
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(irisViolet)
            }

            Text("SPLIT-PRISM ARENA · DUAL STREAM")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(irisViolet)

            Spacer(minLength: 4)

            if isStreaming {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("STREAMING")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.green.opacity(0.12)))
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(RigidPrismButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [deepPlumBase.opacity(0.95), deepPlumBase.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - 单侧流式输出视图

    private func modelStreamContent(
        modelName: String,
        content: String,
        badgeColor: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 模型标签徽章（刚性液态玻璃药丸）
            HStack {
                if alignment == .trailing { Spacer(minLength: 0) }

                HStack(spacing: 5) {
                    Circle().fill(badgeColor).frame(width: 6, height: 6)
                    Text(modelName)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(badgeColor.opacity(0.22))
                        .overlay(Capsule().strokeBorder(badgeColor.opacity(0.45), lineWidth: 0.8))
                )

                if alignment == .leading { Spacer(minLength: 0) }
            }
            .padding(.top, 42)
            .padding(.horizontal, 14)

            // 回复文本渲染
            ScrollView(.vertical, showsIndicators: false) {
                Text(content.isEmpty ? "等待模型生成…" : content)
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(content.isEmpty ? 0.45 : 0.92))
                    .lineSpacing(4)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 50)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            // 快捷选定按钮（底栏）
            Button {
                commitWinner(model: modelName, text: content)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("采用此版本")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(badgeColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(badgeColor.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(badgeColor.opacity(0.35), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(RigidPrismButtonStyle())
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    // MARK: - 胜出阈值检测逻辑

    private func evaluateWinnerLock() {
        if splitRatio >= 0.85 {
            // 模型 A 胜出
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                splitRatio = 1.0
                lockedWinner = modelAName
            }
            Haptics.notification(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                commitWinner(model: modelAName, text: responseA)
            }
        } else if splitRatio <= 0.15 {
            // 模型 B 胜出
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                splitRatio = 0.0
                lockedWinner = modelBName
            }
            Haptics.notification(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                commitWinner(model: modelBName, text: responseB)
            }
        } else {
            // 归位到舒适比较视角（0.5）
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                splitRatio = 0.5
            }
        }
    }

    private func commitWinner(model: String, text: String) {
        onSelectWinner(model, text)
        onDismiss()
    }
}

// MARK: - 垂直光学棱镜分割条（PrismDividerView）

/// 2.5pt 垂直液态玻璃条 + `#7D52F4` 焦散高光 + 菱形中置玻璃手柄
struct PrismDividerView: View {

    let height: CGFloat
    let isDragging: Bool
    let splitRatio: CGFloat

    private let irisViolet = Color(hex: "7D52F4")

    var body: some View {
        ZStack {
            // 2.5pt 垂直高光玻璃条
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            irisViolet.opacity(0.20),
                            Color.white.opacity(0.85),
                            irisViolet,
                            Color.white.opacity(0.85),
                            irisViolet.opacity(0.20)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2.5, height: height)
                .shadow(color: irisViolet.opacity(isDragging ? 0.90 : 0.60), radius: isDragging ? 10 : 5)

            // 中置透光玻璃手柄胶囊（菱形/药丸光感，指示左右滑动）
            ZStack {
                Capsule()
                    .fill(Color(hex: "1D1432").opacity(0.92))
                    .frame(width: 22, height: 44)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white, irisViolet, Color.white.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: irisViolet.opacity(0.55), radius: 8, y: 1)

                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color.white)
            }
        }
        .frame(width: 36, height: height)
        .contentShape(Rectangle())
    }
}

private struct RigidPrismButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.80 : 1.0)
    }
}
