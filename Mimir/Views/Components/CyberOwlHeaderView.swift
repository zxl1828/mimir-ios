import SwiftUI

/// Home header combining the glass sphere, knowledge status, and greeting.
struct CyberOwlHeaderView: View {

    let mascotSize: CGFloat
    let isCompact: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(AppSettings.self) private var settings
    @State private var ragManager = RAGContextManager.shared

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
    }

    // MARK: - 拆原子视图（Sub-views）

    private var orbitalCenterStage: some View {
        let diameter = min(180, max(isCompact ? 120 : 142, mascotSize * 0.86))
        return CyberOwlGlassSphereView(diameter: diameter)
            .frame(height: diameter * 1.28)
    }

    private var statusPillBadge: some View {
        HStack(spacing: 7) {
            Circle().fill(Color.green).frame(width: 5, height: 5)
            Text("知识库已就绪 · \(ragManager.orbitalNodes.count) 个内容片段")
                .font(.system(size: 11, weight: .medium))
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

            Text("深紫机甲猫头鹰 · 液态玻璃轨道")
                .font(.system(size: isCompact ? 11 : 12.5, weight: .medium))
                .foregroundStyle(scheme == .dark ? paleLavender.opacity(0.65) : deepPlumBase.opacity(0.65))
                .lineLimit(2)
                .multilineTextAlignment(.center)
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
                    .fill(Color.white.opacity(0.90))
                    .frame(width: 26, height: 26)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(
                                node.isCausticActive
                                    ? irisViolet
                                    : Color.white.opacity(0.82),
                                lineWidth: node.isCausticActive ? 1.6 : 0.8
                            )
                    }
                    .shadow(
                        color: node.isCausticActive ? irisViolet.opacity(0.65) : deepPlumBase.opacity(0.12),
                        radius: node.isCausticActive ? 6 : 3,
                        y: 1.5
                    )

                // 文件类型标识符小字
                Text(fileTag(for: node.fileExtension))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(node.isCausticActive ? irisViolet : deepPlumBase)
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

    private let irisViolet = Color(hex: "7D52F4")
    private let deepPlumBase = Color(hex: "120D1D")

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
                        .foregroundStyle(deepPlumBase)
                        .lineLimit(1)

                    Text("RAG CHUNK #\(node.chunkIndex + 1) OF \(node.totalChunks)")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(irisViolet)
                }

                Spacer(minLength: 4)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(deepPlumBase.opacity(0.65))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(RigidNodeButtonStyle())
            }

            // 文本/代码切片内容（行截断 line-clamp 4行）
            Text(node.snippet)
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundStyle(deepPlumBase.opacity(0.92))
                .lineLimit(4)
                .lineSpacing(3)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: "F5F1FA").opacity(0.92))
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
                .fill(Color.white.opacity(0.92))
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
                .shadow(color: deepPlumBase.opacity(0.24), radius: 14, y: 6)
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
                        .foregroundStyle(deepPlumBase.opacity(0.92))
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: "F5F1FA"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                                )
                        )
                }
                .padding(20)
            }
            .background(Color(hex: "F8F6FD").ignoresSafeArea())
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
