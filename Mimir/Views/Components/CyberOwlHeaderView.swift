import SwiftUI

/// 赛博猫头鹰 RAG 知识共振轨道标头（Cyber-Owl Knowledge Resonance Header）。
///
/// 核心特性：
/// 1. 居中原生绘制的 Cyber-Owl（MimirMascot）；
/// 2. 围绕猫头鹰行星星轨动态附着 1 到 6 个参数化角度分布的轨道粒子节点（`OrbitalNodeView`）；
/// 3. 当 SSE 流或上下文命中特定分块时，触发 `#7D52F4` 焦散光晕呼吸脉冲（radius: 8pt）；
/// 4. 点击轨道节点弹出无变形的高架悬浮切片卡片（Elevated Floating Popover，`#120D1D` 85% + `ultraThinMaterial`），支持行截断与全量视图导航。
struct CyberOwlHeaderView: View {

    let mascotSize: CGFloat
    let isCompact: Bool
    var onSelectNode: ((RAGOrbitalNode) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @Environment(AppSettings.self) private var settings
    @State private var ragManager = RAGContextManager.shared
    @State private var activePopoverNode: RAGOrbitalNode?
    @State private var showFullSliceSheet: Bool = false
    @State private var orbitalDriftAngle: Double = 0

    // Mimir 严选品牌色基准（严禁 Color.black）
    private let irisViolet = Color(hex: "7D52F4")
    private let deepPlumBase = Color(hex: "120D1D")
    private let paleLavender = Color(hex: "F8F6FD")

    var body: some View {
        VStack(spacing: isCompact ? 6 : 12) {
            orbitalCenterStage
            statusPillBadge
            greetingAndCaption
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, isCompact ? 10 : 20)
        .overlay(alignment: .center) {
            popoverOverlay
        }
        .sheet(isPresented: $showFullSliceSheet) {
            if let node = activePopoverNode {
                FullSliceSheet(node: node)
            }
        }
    }

    // MARK: - 拆原子视图（Sub-views）

    private var orbitalCenterStage: some View {
        let orbitRadiusX = mascotSize * 0.78
        let orbitRadiusY = mascotSize * 0.36

        return ZStack {
            // 呼吸背景微光晕
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            irisViolet.opacity(scheme == .dark ? 0.28 : 0.16),
                            irisViolet.opacity(0.06),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: mascotSize * 0.8
                    )
                )
                .frame(width: mascotSize * 1.5, height: mascotSize * 1.5)

            // 环绕行星轨道环（纤细透光玻璃轨道）
            Ellipse()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            irisViolet.opacity(0.45),
                            Color.white.opacity(scheme == .dark ? 0.22 : 0.35),
                            irisViolet.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
                .frame(width: orbitRadiusX * 2.05, height: orbitRadiusY * 2.05)
                .rotationEffect(.degrees(-16))

            // 中央核心：Cyber-Owl 赛博猫头鹰
            MimirMascot(size: mascotSize * 0.90, mood: .calm)
                .frame(width: mascotSize, height: mascotSize)
                .shadow(color: irisViolet.opacity(scheme == .dark ? 0.38 : 0.24), radius: mascotSize * 0.18, y: 3)

            // 参数化分布的 1 到 6 个 RAG 轨道粒子节点
            ForEach(Array(ragManager.orbitalNodes.enumerated()), id: \.element.id) { index, node in
                let pos = nodePosition(index: index, total: ragManager.orbitalNodes.count, radiusX: orbitRadiusX, radiusY: orbitRadiusY)
                OrbitalNodeView(node: node) {
                    activePopoverNode = node
                    ragManager.selectedNode = node
                    onSelectNode?(node)
                }
                .offset(x: pos.offset.x, y: pos.offset.y)
                .zIndex(pos.isFront ? 10 : 2)
            }
        }
        .frame(height: max(isCompact ? 144 : 188, mascotSize * 1.35))
        .onAppear {
            withAnimation(.linear(duration: 45).repeatForever(autoreverses: false)) {
                orbitalDriftAngle = 2.0 * .pi
            }
        }
    }

    private func nodePosition(index: Int, total: Int, radiusX: CGFloat, radiusY: CGFloat) -> (offset: CGPoint, isFront: Bool) {
        let count = Double(max(1, total))
        let baseAngle = (Double(index) / count) * (2.0 * .pi)
        let currentAngle = baseAngle + orbitalDriftAngle

        let rawX = cos(currentAngle) * Double(radiusX)
        let rawY = sin(currentAngle) * Double(radiusY)
        let tiltRad = -16.0 * .pi / 180.0
        let rx = rawX * cos(tiltRad) - rawY * sin(tiltRad)
        let ry = rawX * sin(tiltRad) + rawY * cos(tiltRad)
        return (CGPoint(x: rx, y: ry), sin(currentAngle) > 0)
    }

    private var statusPillBadge: some View {
        HStack(spacing: 7) {
            Circle().fill(Color.green).frame(width: 5, height: 5)
            Text("MIMIR · KNOWLEDGE RESONANCE READY")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(irisViolet)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(irisViolet.opacity(scheme == .dark ? 0.15 : 0.08))
                .overlay(Capsule().strokeBorder(irisViolet.opacity(0.25), lineWidth: 0.8))
        )
    }

    private var greetingAndCaption: some View {
        VStack(spacing: 4) {
            Text(greeting)
                .font(.system(size: isCompact ? 18 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(scheme == .dark ? paleLavender : deepPlumBase)
                .lineLimit(1)
                .minimumScaleFactor(0.88)
                .multilineTextAlignment(.center)

            Text("轻触轨道文件粒子，查看实时摄入的知识切片。")
                .font(.system(size: isCompact ? 11 : 12.5, weight: .medium))
                .foregroundStyle(scheme == .dark ? paleLavender.opacity(0.65) : deepPlumBase.opacity(0.65))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var popoverOverlay: some View {
        if let node = activePopoverNode {
            RAGChunkPopoverView(node: node, onDismiss: {
                activePopoverNode = nil
            }, onOpenFullView: {
                showFullSliceSheet = true
            })
            .transition(.asymmetric(
                insertion: .scale(scale: 0.96).combined(with: .opacity),
                removal: .opacity
            ))
            .zIndex(100)
        }
    }

    private var greeting: String {
        let name = settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "你好，我是 Mimir" : "你好，\(name)，我是 Mimir"
    }
}

// MARK: - 轨道粒子节点视图（OrbitalNodeView）

/// 环绕在星轨上的微型流体玻璃知识粒子
struct OrbitalNodeView: View {

    let node: RAGOrbitalNode
    let onTap: () -> Void

    @Environment(\.colorScheme) private var scheme
    private let irisViolet = Color(hex: "7D52F4")
    private let deepPlumBase = Color(hex: "120D1D")

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // 焦散光晕呼吸脉冲（#7D52F4 8pt 呼吸）
                if node.isCausticActive {
                    Circle()
                        .fill(irisViolet.opacity(0.40))
                        .frame(width: 32, height: 32)
                        .blur(radius: 8)
                        .scaleEffect(1.22)
                }

                // 微型高架液态玻璃圆盘（刚性无形变）
                Circle()
                    .fill(
                        scheme == .dark
                            ? deepPlumBase.opacity(0.85)
                            : Color.white.opacity(0.85)
                    )
                    .frame(width: 26, height: 26)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(
                                node.isCausticActive
                                    ? irisViolet
                                    : Color.white.opacity(scheme == .dark ? 0.35 : 0.65),
                                lineWidth: node.isCausticActive ? 1.6 : 0.8
                            )
                    }
                    .shadow(
                        color: node.isCausticActive ? irisViolet.opacity(0.65) : Color.black.opacity(0.12),
                        radius: node.isCausticActive ? 6 : 3,
                        y: 1.5
                    )

                // 文件类型标识符小字
                Text(fileTag(for: node.fileExtension))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(node.isCausticActive ? irisViolet : (scheme == .dark ? Color.white : deepPlumBase))
            }
        }
        .buttonStyle(RigidNodeButtonStyle())
        .accessibilityLabel("知识分块：\(node.title)")
    }

    private func fileTag(for ext: String) -> String {
        switch ext {
        case "swift": return "SW"
        case "md", "markdown": return "MD"
        case "json": return "JS"
        case "py": return "PY"
        case "c", "cpp", "h": return "C"
        default: return String(ext.prefix(2).uppercased())
        }
    }
}

// MARK: - 高架悬浮切片卡片（Elevated Floating Popover）

/// 严格遵守 Design DNA：`#120D1D` 85% + `ultraThinMaterial`，0.8pt 折射边缘，无按压缩放，刚性悬浮
private struct RAGChunkPopoverView: View {

    let node: RAGOrbitalNode
    let onDismiss: () -> Void
    let onOpenFullView: () -> Void

    @Environment(\.colorScheme) private var scheme
    private let irisViolet = Color(hex: "7D52F4")
    private let deepPlumBase = Color(hex: "120D1D")
    private let paleLavender = Color(hex: "F8F6FD")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶栏：文件名与分块编号 + 关闭按钮
            HStack(spacing: 8) {
                Image(systemName: iconName(for: node.fileExtension))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(irisViolet)

                VStack(alignment: .leading, spacing: 1) {
                    Text(node.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Text("RAG CHUNK #\(node.chunkIndex + 1) OF \(node.totalChunks)")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(irisViolet)
                }

                Spacer(minLength: 4)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(RigidNodeButtonStyle())
            }

            // 文本/代码切片内容（行截断 line-clamp 4行）
            Text(node.snippet)
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(4)
                .lineSpacing(3)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: "1D152D").opacity(0.90))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                )

            // 底栏操作："查看完整切片"
            Button(action: onOpenFullView) {
                HStack(spacing: 6) {
                    Text("查看完整切片")
                        .font(.system(size: 11.5, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(irisViolet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(irisViolet.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(irisViolet.opacity(0.35), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(RigidNodeButtonStyle())
        }
        .padding(14)
        .frame(width: 290)
        // 严格遵循：#120D1D 85% + ultraThinMaterial
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(deepPlumBase.opacity(0.85))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.38),
                                    irisViolet.opacity(0.55),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                }
                .shadow(color: irisViolet.opacity(0.24), radius: 24, y: 10)
                .shadow(color: Color.black.opacity(0.32), radius: 14, y: 6)
        }
    }

    private func iconName(for ext: String) -> String {
        switch ext {
        case "swift": return "swift"
        case "md", "markdown": return "doc.text"
        case "json": return "curlybraces"
        default: return "doc.fill"
        }
    }
}

// MARK: - 全量切片展示 Sheet

private struct FullSliceSheet: View {
    let node: RAGOrbitalNode
    @Environment(\.dismiss) private var dismiss
    private let irisViolet = Color(hex: "7D52F4")
    private let deepPlumBase = Color(hex: "120D1D")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text("分块 \(node.chunkIndex + 1) / \(node.totalChunks)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(irisViolet)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(irisViolet.opacity(0.15)))
                        Spacer()
                    }

                    Text(node.snippet)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: "1A1228"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                                )
                        )
                }
                .padding(20)
            }
            .background(deepPlumBase.ignoresSafeArea())
            .navigationTitle(node.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(irisViolet)
                }
            }
        }
    }
}

// MARK: - 刚性无形变按钮样式（Rigid Slabs, Zero Shrink, Zero 3D Tilt）

private struct RigidNodeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1.0) // 仅调节透明度，绝不触发缩放或 3D 旋转形变
    }
}
