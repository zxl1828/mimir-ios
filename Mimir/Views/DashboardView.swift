import SwiftUI
import SwiftData

/// 页面一：工作台仪表盘（DashboardView）。
///
/// 1:1 复刻设计参考图，包含多智能体协作中心、数据指标监控、项目状态与近期任务流。
struct DashboardView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]

    @State private var showSettings = false
    @State private var showHelpGuide = false
    @State private var previewArtwork = false

    private var coordinator: TabNavigationCoordinator {
        TabNavigationCoordinator.shared
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                // 1. 顶部导航行（Header Bar）
                topHeaderRow
                    .staggeredSlideEntrance(index: 0)

                // 2. 顶部快捷指令行（Quick Tools Grid）
                quickToolsRow
                    .staggeredSlideEntrance(index: 1)

                // 3. 数据与指标监控（DATA & METRICS >）
                dataAndMetricsSection
                    .staggeredSlideEntrance(index: 2)

                // 4. 项目状态与代码微缩预览（PROJECT STATUS >）
                projectStatusSection
                    .staggeredSlideEntrance(index: 3)

                // 5. 进行中的会话与任务流（CURRENT CONVERSATIONS）
                currentConversationsSection
                    .staggeredSlideEntrance(index: 4)

                // 6. 底部星穹神树精选多模态资产微展台
                artworkShowcaseCard
                    .staggeredSlideEntrance(index: 5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 96) // 留足底部悬浮 TabBar 的空间
        }
        .background {
            AppUI.ambientBackground(scheme: scheme)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(list: ConversationListViewModel(modelContext: modelContext, settings: settings))
        }
        .sheet(isPresented: $showHelpGuide) {
            helpGuideSheet
        }
    }

    // MARK: - 1. 顶部 Header

    private var topHeaderRow: some View {
        HStack(spacing: 10) {
            MimirMascot(size: 30, mood: .calm)

            Text("Mimir")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppUI.textTitle(scheme: scheme))

            Spacer()

            // 用户头像
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "A78BFA"), Color(hex: "7C5CFC")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.white.opacity(0.92))
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 1.2)
                }
                .shadow(color: AppUI.electricViolet.opacity(0.3), radius: 6)

            // 帮助按钮
            Button {
                Haptics.impact(.light)
                showHelpGuide = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(PhysicalElasticCircleButtonStyle())

            // 设置按钮
            Button {
                Haptics.impact(.light)
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(PhysicalElasticCircleButtonStyle())
        }
        .padding(.vertical, 4)
    }

    // MARK: - 2. 顶部快捷指令行 (Quick Tools Grid)

    private var quickToolsRow: some View {
        HStack(spacing: 12) {
            // 卡片 1: [AI] Image Generation
            Button {
                coordinator.navigateToAssistant(withPrompt: "画一张图片，画面是：")
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("AI")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(AppUI.electricViolet)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppUI.electricViolet.opacity(0.14))
                            )

                        Text("Image Gen")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppUI.textTitle(scheme: scheme))
                            .lineLimit(1)
                    }

                    // 底部微型药丸胶囊（含 3 个微图标）
                    HStack(spacing: 14) {
                        Image(systemName: "book")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "paperplane")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme).opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.85))
                    )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .softGlassCard(cornerRadius: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AppUI.electricViolet.opacity(0.35), lineWidth: 1.2)
                )
                .shadow(color: AppUI.electricViolet.opacity(0.18), radius: 10, y: 4)
            }
            .buttonStyle(PhysicalElasticButtonStyle())
            .interactiveTilt(maxAngle: 5.5, cornerRadius: 18)

            // 卡片 2: Library
            Button {
                coordinator.switchToTab(.files)
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .frame(height: 28)

                    Text("Library")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .softGlassCard(cornerRadius: 18)
            }
            .buttonStyle(PhysicalElasticButtonStyle())
            .interactiveTilt(maxAngle: 5.5, cornerRadius: 18)

            // 卡片 3: My Projects
            Button {
                coordinator.switchToTab(.code)
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .frame(height: 28)

                    Text("My Projects")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .lineLimit(1)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .softGlassCard(cornerRadius: 18)
            }
            .buttonStyle(PhysicalElasticButtonStyle())
            .interactiveTilt(maxAngle: 5.5, cornerRadius: 18)
        }
    }

    // MARK: - 3. 数据与指标监控 (Data & Metrics)

    private var dataAndMetricsSection: some View {
        VStack(spacing: 10) {
            sectionHeader(title: "DATA & METRICS", destinationTab: .files)

            HStack(spacing: 12) {
                // 左卡片：Castor Chats
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Castor Chats")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                        Spacer()
                        Text("Pro, Ratio")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: "9CA3AF"))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        metricRow(label: "S: Chats", value: "#a# 11", tag: "Low", tagColor: Color(hex: "34D399"))
                        metricRow(label: "Depts analysis", value: "#a# 12", tag: "High", tagColor: Color(hex: "F472B6"))
                        metricRow(label: "Deptc points", value: "#a2 9", tag: "Medium", tagColor: Color(hex: "FBBF24"))
                        metricRow(label: "Moicar chats", value: "#a3 3", tag: "Upch", tagColor: Color(hex: "A78BFA"))
                    }
                    .padding(.vertical, 2)

                    Spacer(minLength: 4)

                    // 底部 3 根微型紫蓝进度条
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Color(hex: "7C5CFC"), Color(hex: "A78BFA")], startPoint: .bottom, endPoint: .top))
                            .frame(width: 8, height: 16)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Color(hex: "7C5CFC"), Color(hex: "38BDF8")], startPoint: .bottom, endPoint: .top))
                            .frame(width: 8, height: 22)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Color(hex: "7C5CFC"), Color(hex: "F472B6")], startPoint: .bottom, endPoint: .top))
                            .frame(width: 8, height: 12)

                        Spacer()
                        Text("High/Low token ratio")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 146)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(hex: "1F1B2C").opacity(scheme == .dark ? 0.90 : 0.88))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
                .interactiveTilt(maxAngle: 5.0, cornerRadius: 18)

                // 右卡片：Export Trend 柱状图
                VStack(alignment: .leading, spacing: 6) {
                    Text("Export Trend")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)

                    HStack(alignment: .bottom, spacing: 4) {
                        // Y 轴刻度
                        VStack(alignment: .leading) {
                            Text("100").font(.system(size: 8))
                            Spacer()
                            Text("40").font(.system(size: 8))
                            Spacer()
                            Text("20").font(.system(size: 8))
                            Spacer()
                            Text("0").font(.system(size: 8))
                        }
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(height: 72)

                        Spacer()

                        // 10 根渐变走势柱
                        let barHeights: [CGFloat] = [18, 32, 44, 26, 68, 22, 52, 40, 58, 64]
                        HStack(alignment: .bottom, spacing: 4.5) {
                            ForEach(0..<10, id: \.self) { idx in
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(hex: "7C5CFC"),
                                                Color(hex: "38BDF8")
                                            ],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(width: 5.5, height: barHeights[idx])
                                    .shadow(color: Color(hex: "7C5CFC").opacity(0.35), radius: 3, y: 0)
                            }
                        }
                        .frame(height: 72, alignment: .bottom)
                    }

                    // X 轴时间刻度
                    HStack {
                        Spacer()
                        Text("01  12  03  44  56  67  78  89  10e 10t")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.40))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 146)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(hex: "1F1B2C").opacity(scheme == .dark ? 0.90 : 0.88))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
                .interactiveTilt(maxAngle: 5.0, cornerRadius: 18)
            }
        }
    }

    private func metricRow(label: String, value: String, tag: String, tagColor: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.70))
                .lineLimit(1)
            Spacer()
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.90))
            Text("// \(tag)")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(tagColor)
        }
    }

    // MARK: - 4. 项目状态与代码微缩预览 (Project Status)

    private var projectStatusSection: some View {
        VStack(spacing: 10) {
            sectionHeader(title: "PROJECT STATUS", destinationTab: .code)

            HStack(spacing: 12) {
                // 左卡片：Objective 折线图
                VStack(alignment: .leading, spacing: 4) {
                    Text("Objective")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading) {
                            Text("100").font(.system(size: 8))
                            Spacer()
                            Text("50").font(.system(size: 8))
                            Spacer()
                            Text("0").font(.system(size: 8))
                        }
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(height: 56)

                        Spacer()

                        // 贝塞尔发光平滑折线
                        ObjectiveLineChart()
                            .frame(height: 60)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 122)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(hex: "1F1B2C").opacity(scheme == .dark ? 0.90 : 0.88))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
                .interactiveTilt(maxAngle: 5.0, cornerRadius: 18)

                // 右卡片：语法高亮代码微缩
                Button {
                    coordinator.switchToTab(.code)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("export inputRnfent = AIEElement {")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: "38BDF8"))
                        Text("  wait(element) {")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color(hex: "F472B6"))
                        Text("    dra.GeooInclose('makter');")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color(hex: "34D399"))
                        Text("    false: 'relapse/teo',")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color(hex: "A78BFA"))
                        Text("    essee: 'dearnights.event.prom'")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(Color(hex: "FBBF24"))
                        Text("  }")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color(hex: "F472B6"))
                        Text("}")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color(hex: "38BDF8"))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 122)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(hex: "171424").opacity(scheme == .dark ? 0.95 : 0.90))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AppUI.electricViolet.opacity(0.35), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.20), radius: 10, y: 4)
                }
                .buttonStyle(PhysicalElasticButtonStyle())
                .interactiveTilt(maxAngle: 5.0, cornerRadius: 18)
            }
        }
    }

    // MARK: - 5. 进行中的会话与任务流 (Current Conversations)

    private var currentConversationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CURRENT CONVERSATIONS")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                // 如果本地有真实会话，优先展示前 3 条；否则展示精美预设会话
                if !conversations.isEmpty {
                    ForEach(Array(conversations.prefix(3))) { convo in
                        conversationRow(
                            title: convo.title.isEmpty ? "新对话" : convo.title,
                            subtitle: (convo.lastMessage?.text.isEmpty == false ? convo.lastMessage?.text : nil) ?? "点击继续进行多轮深度推理…",
                            time: convo.updatedAt.formatted(.relative(presentation: .named)),
                            onTap: {
                                coordinator.openConversation(id: convo.id)
                            }
                        )
                    }
                } else {
                    conversationRow(
                        title: "Space Exploration AI Prompt",
                        subtitle: "Refining orbital dynamics query & Lagrange equations...",
                        time: "2 hrs ago",
                        onTap: {
                            coordinator.navigateToAssistant(withPrompt: "继续推进太空轨道力学推导：")
                        }
                    )
                    conversationRow(
                        title: "The Future of AI in Healthcare",
                        subtitle: "Analyzing current trends and automated clinical trials...",
                        time: "Yesterday",
                        onTap: {
                            coordinator.navigateToAssistant(withPrompt: "回顾医疗 AI 预测分析：")
                        }
                    )
                    conversationRow(
                        title: "Creative Copy for Marketing",
                        subtitle: "Generating slogans for the new liquid glass product line...",
                        time: "2 days ago",
                        onTap: {
                            coordinator.navigateToAssistant(withPrompt: "撰写液态玻璃主题创意文案：")
                        }
                    )
                }

                // 底部固定毛玻璃发光胶囊按钮：START NEW CHAT
                Button {
                    Haptics.impact(.medium)
                    coordinator.startNewChat()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 14, weight: .semibold))
                        Text("START NEW CHAT")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .tracking(0.5)
                    }
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule(style: .continuous)
                                    .fill(AppUI.electricViolet.opacity(scheme == .dark ? 0.20 : 0.12))
                            )
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(scheme == .dark ? 0.50 : 0.85),
                                        AppUI.electricViolet.opacity(0.40)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.1
                            )
                    }
                    .shadow(color: AppUI.electricViolet.opacity(scheme == .dark ? 0.35 : 0.16), radius: 10, y: 3)
                }
                .buttonStyle(PhysicalElasticCapsuleButtonStyle())
                .padding(.top, 4)
            }
            .padding(16)
            .softGlassCard(cornerRadius: 22)
            .interactiveTilt(maxAngle: 4.5, cornerRadius: 22)
        }
    }

    private func conversationRow(title: String, subtitle: String, time: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                        .lineLimit(1)
                }

                Spacer()

                Text(time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    .padding(.top, 1)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PhysicalElasticButtonStyle())
    }

    // MARK: - 6. 底部精选多模态资产展示卡片 (Artwork Showcase)

    private var artworkShowcaseCard: some View {
        Button {
            coordinator.switchToTab(.files)
        } label: {
            ZStack(alignment: .bottomLeading) {
                // 模拟参考图下方的星穹神树生成图
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "0B0916"),
                                Color(hex: "1F143B"),
                                Color(hex: "0E1A33")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 140)
                    .overlay {
                        // 星云微光与树状微粒视觉
                        CosmicTreeArtworkView()
                    }
                    .clipped()

                // 底部半透明浮层
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("星穹神树 · 8K 多模态生成")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("提示词：Bioluminescent cosmic sacred tree, nebula stars...")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.white.opacity(0.70))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppUI.auroraViolet)
                }
                .padding(14)
                .background {
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AppUI.electricViolet.opacity(0.40), lineWidth: 1.2)
            }
            .shadow(color: AppUI.electricViolet.opacity(0.28), radius: 14, y: 6)
        }
        .buttonStyle(PhysicalElasticButtonStyle())
        .interactiveTilt(maxAngle: 5.0, cornerRadius: 22)
    }

    // MARK: - 通用辅助组件

    private func sectionHeader(title: String, destinationTab: AppTab) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
            Spacer()
            Button {
                coordinator.switchToTab(destinationTab)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var helpGuideSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Mimir 全局架构与工作区指南")
                        .font(.title2.bold())
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))

                    Text("• **智能助手 (AI Assistant)**：核心多轮对话、星尘四档思考滑块与工具调用。\n• **工作台仪表盘 (Dashboard)**：多智能体协作中心、数据指标监控与近期任务流。\n• **知识资产库 (Files & Assets)**：本地项目文件夹安全挂载、RAG 向量检索与多模态资产。\n• **代码工坊 (Code Workspace)**：代码审查、Web 实时内联运行预览与 MCP 远程编译。")
                        .font(.system(size: 14))
                        .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                        .lineSpacing(6)
                }
                .padding(20)
            }
            .navigationTitle("使用指南")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { showHelpGuide = false }
            }
        }
    }
}

/// 贝塞尔发光平滑折线图 (Objective Curve)
private struct ObjectiveLineChart: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            // 关键点：(0.0, 0.7), (0.25, 0.55), (0.45, 0.70), (0.65, 0.20), (0.85, 0.35), (1.0, 0.25)
            let pts: [CGPoint] = [
                CGPoint(x: 0, y: h * 0.75),
                CGPoint(x: w * 0.22, y: h * 0.60),
                CGPoint(x: w * 0.42, y: h * 0.72),
                CGPoint(x: w * 0.65, y: h * 0.18),
                CGPoint(x: w * 0.85, y: h * 0.38),
                CGPoint(x: w, y: h * 0.22)
            ]

            ZStack {
                // 渐变填充阴影
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: pts[0])
                    for i in 1..<pts.count {
                        let prev = pts[i - 1]
                        let curr = pts[i]
                        let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                        path.addQuadCurve(to: mid, control: prev)
                        path.addLine(to: curr)
                    }
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "7C5CFC").opacity(0.38), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // 发光折线
                Path { path in
                    path.move(to: pts[0])
                    for i in 1..<pts.count {
                        let prev = pts[i - 1]
                        let curr = pts[i]
                        let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                        path.addQuadCurve(to: mid, control: prev)
                        path.addLine(to: curr)
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "7C5CFC"), Color(hex: "38BDF8")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 2.2
                )
                .shadow(color: Color(hex: "7C5CFC").opacity(0.75), radius: 4, y: 1)
            }
        }
    }
}

/// 底部星穹神树艺术图绘制组件
private struct CosmicTreeArtworkView: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let center = CGPoint(x: w / 2, y: h * 0.6)

            // 发光神树主干
            var trunk = Path()
            trunk.move(to: CGPoint(x: center.x - 12, y: h))
            trunk.addQuadCurve(to: CGPoint(x: center.x, y: h * 0.45), control: CGPoint(x: center.x - 6, y: h * 0.7))
            trunk.addQuadCurve(to: CGPoint(x: center.x + 12, y: h), control: CGPoint(x: center.x + 6, y: h * 0.7))
            context.fill(trunk, with: .color(Color(hex: "A78BFA").opacity(0.8)))

            // 树冠星云光晕
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 70, y: h * 0.15, width: 140, height: 80)),
                with: .radialGradient(
                    Gradient(colors: [Color(hex: "7C5CFC").opacity(0.7), Color.clear]),
                    center: CGPoint(x: center.x, y: h * 0.35),
                    startRadius: 5,
                    endRadius: 75
                )
            )

            // 散布枝杈与星光微粒
            for i in 0..<36 {
                let angle = Double(i) * (Double.pi * 2 / 36)
                let r = 25.0 + Double((i * 17) % 45)
                let px = center.x + CGFloat(cos(angle) * r)
                let py = (h * 0.35) + CGFloat(sin(angle) * r * 0.6)
                let dotSize = CGFloat((i % 3) + 2)
                context.fill(
                    Path(ellipseIn: CGRect(x: px, y: py, width: dotSize, height: dotSize)),
                    with: .color(Color.white.opacity(0.85))
                )
            }
        }
    }
}
