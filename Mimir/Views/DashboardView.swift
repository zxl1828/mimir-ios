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
    @Query(sort: \AgentDockItem.sortIndex)
    private var agents: [AgentDockItem]
    @Query(sort: \Skill.sortIndex)
    private var skills: [Skill]
    @Query
    private var mcpConfigs: [MCPServerConfig]
    @Query
    private var memories: [MemoryEntry]

    @State private var showSettings = false
    @State private var showHelpGuide = false
    @State private var showAgentManager = false
    @State private var showSkillManager = false
    @State private var showMCPServers = false
    @State private var showScheduledTasks = false
    @State private var showGlobalSearch = false
    @State private var showMemoryBrowser = false
    @State private var showDataFlow = false
    @State private var renamingConversation: Conversation?
    @State private var renameText = ""

    private var coordinator: TabNavigationCoordinator {
        TabNavigationCoordinator.shared
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                // 1. 顶部导航行（Header Bar）
                topHeaderRow
                    .staggerCascade(index: 0)

                workflowOverview
                    .staggerCascade(index: 1)

                // 2. 顶部快捷指令行（Quick Tools Grid）
                quickToolsRow
                    .staggerCascade(index: 2)

                // 3. 四大核心业务工作区（智能体中心、技能工具箱、定时任务与项目、知识与记忆检索）
                coreWorkspaceCardsSection
                    .staggerCascade(index: 3)

                // 4. 进行中的会话与任务流（CURRENT CONVERSATIONS）
                currentConversationsSection
                    .staggerCascade(index: 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 96) // 留足底部悬浮 TabBar 的空间
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .correctedSoftFadeMask(topFade: 16, bottomFade: 40)
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
        .sheet(isPresented: $showAgentManager) {
            AgentManagerView()
        }
        .sheet(isPresented: $showSkillManager) {
            SkillManagerView()
        }
        .sheet(isPresented: $showMCPServers) {
            MCPServersView()
        }
        .sheet(isPresented: $showScheduledTasks) {
            ScheduledTasksView()
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalSearchView { conversationID, _ in
                coordinator.openConversation(id: conversationID)
            }
        }
        .sheet(isPresented: $showMemoryBrowser) {
            MemoryBrowserView()
        }
        .sheet(isPresented: $showDataFlow) {
            DataFlowPanelView()
        }
        .alert("重命名对话", isPresented: Binding(
            get: { renamingConversation != nil },
            set: { if !$0 { renamingConversation = nil } }
        )) {
            TextField("对话名称", text: $renameText)
            Button("取消", role: .cancel) { renamingConversation = nil }
            Button("保存") {
                if let convo = renamingConversation {
                    convo.title = renameText
                    try? modelContext.save()
                }
                renamingConversation = nil
            }
        }
    }

    // MARK: - 1. 顶部 Header

    private var topHeaderRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(scheme == .dark ? 0.18 : 0.10))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Circle().strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
                    }
                MimirMascot(size: 36, mood: .calm)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("MIMIR  /  PERSONAL AI")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Text(settings.profileName.isEmpty ? "让想法开始流动" : "欢迎回来，\(settings.profileName)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            Button {
                Haptics.impact(.light)
                showHelpGuide = true
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(scheme == .dark ? 0.06 : 0.44)))
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.62), lineWidth: 0.8) }
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .accessibilityLabel("帮助")

            Button {
                Haptics.impact(.light)
                showSettings = true
            } label: {
                ProfileAvatarBadge(size: 36)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .accessibilityLabel("个人资料与设置")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .softGlassCard(cornerRadius: 24)
    }

    private var workflowOverview: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MIMIR / WORKSPACE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                    Text("工作流概览")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("本机空间")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                }
            }

            HStack(spacing: 0) {
                overviewMetric(value: agents.count, label: "AGENTS", icon: "sparkles")
                metricDivider
                overviewMetric(value: skills.count, label: "SKILLS", icon: "square.grid.2x2")
                metricDivider
                overviewMetric(value: conversations.count, label: "THREADS", icon: "bubble.left.and.bubble.right")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .softGlassCard(cornerRadius: 24)
    }

    private func overviewMetric(value: Int, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
            Text(value, format: .number)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppUI.textTitle(scheme: scheme))
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppUI.textCaption(scheme: scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(AppUI.separator.opacity(0.55))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 12)
    }

    // MARK: - 2. 顶部快捷指令行 (Quick Tools Grid)

    private var quickToolsRow: some View {
        HStack(spacing: 12) {
            // 卡片 1: 图像生成
            Button {
                coordinator.navigateToAssistant(withPrompt: "画一张图片，画面是：")
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("AI")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(accent.opacity(0.14))
                            )

                        Text("图像生成")
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
            }
            .buttonStyle(.plain)

            // 卡片 2: Library
            Button {
                coordinator.switchToTab(.files)
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .frame(height: 28)

                    Text("资料库")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .softGlassCard(cornerRadius: 18)
            }
            .buttonStyle(.plain)

            // 卡片 3: My Projects
            Button {
                coordinator.switchToTab(.code)
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .frame(height: 28)

                    Text("我的项目")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .lineLimit(1)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .softGlassCard(cornerRadius: 18)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 3. 四大核心业务工作区 (4 大核心功能卡片)

    private var coreWorkspaceCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WORKSPACE CAPABILITIES")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .padding(.horizontal, 4)
                Spacer()
                Text("04 MODULES")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(accent.opacity(scheme == .dark ? 0.14 : 0.08), in: Capsule())
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 164, maximum: 244), spacing: 12)], spacing: 12) {
                // 卡片 1: 智能体中心 (Agents & Models)
                agentCenterCard

                // 卡片 2: 技能工具箱 (Skills & Tools)
                skillsToolboxCard

                // 卡片 3: 定时任务与项目 (Tasks & Projects)
                scheduledTasksCard

                // 卡片 4: 知识与记忆检索 (Memory & Context)
                memoryContextCard
            }
        }
    }

    // MARK: - 3.1 智能体中心卡片

    private var agentCenterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "cpu")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Spacer()

                Text("\(max(agents.count, 1)) 智能体")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(accent.opacity(0.12)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("智能体中心")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                Text("Agents & Models")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
            }

            Spacer(minLength: 2)

            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: "34D399"))
                    .frame(width: 6, height: 6)
                Text(ModelCatalog.cardLabel(for: settings.credential.modelID))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .softGlassCard(cornerRadius: 18)
        .interactiveGlassCard(
            cornerRadius: 18,
            actions: [
                GlassCardAction(title: "智能体管理", icon: "slider.horizontal.3") {
                    showAgentManager = true
                },
                GlassCardAction(title: "快速对话", icon: "bubble.left.and.bubble.right") {
                    coordinator.switchToTab(.assistant)
                },
                GlassCardAction(title: "模型配置", icon: "gearshape") {
                    showSettings = true
                }
            ],
            onPrimaryTap: {
                showAgentManager = true
            }
        )
    }

    // MARK: - 3.2 技能工具箱卡片

    private var skillsToolboxCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "38BDF8").opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "38BDF8"))
                }

                Spacer()

                Text("\(skills.count) 技能")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "38BDF8"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "38BDF8").opacity(0.12)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("技能工具箱")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                Text("Skills & MCP")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
            }

            Spacer(minLength: 2)

            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: "38BDF8"))
                    .frame(width: 6, height: 6)
                Text("\(mcpConfigs.count) 个 MCP 协议挂载")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .softGlassCard(cornerRadius: 18)
        .interactiveGlassCard(
            cornerRadius: 18,
            actions: [
                GlassCardAction(title: "技能配置", icon: "slider.horizontal.3") {
                    showSkillManager = true
                },
                GlassCardAction(title: "MCP 服务", icon: "network") {
                    showMCPServers = true
                },
                GlassCardAction(title: "新建技能", icon: "plus.circle") {
                    showSkillManager = true
                }
            ],
            onPrimaryTap: {
                showSkillManager = true
            }
        )
    }

    // MARK: - 3.3 定时任务与项目卡片

    private var scheduledTasksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "34D399").opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "34D399"))
                }

                Spacer()

                Text("调度中")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "34D399"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "34D399").opacity(0.12)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("定时任务与项目")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                Text("Tasks & Projects")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
            }

            Spacer(minLength: 2)

            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: "34D399"))
                    .frame(width: 6, height: 6)
                Text("后台自动化流程活跃")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .softGlassCard(cornerRadius: 18)
        .interactiveGlassCard(
            cornerRadius: 18,
            actions: [
                GlassCardAction(title: "任务调度", icon: "clock.arrow.circlepath") {
                    showScheduledTasks = true
                },
                GlassCardAction(title: "代码工坊", icon: "chevron.left.forwardslash.chevron.right") {
                    coordinator.switchToTab(.code)
                },
                GlassCardAction(title: "工作区目录", icon: "folder") {
                    coordinator.switchToTab(.files)
                }
            ],
            onPrimaryTap: {
                showScheduledTasks = true
            }
        )
    }

    // MARK: - 3.4 知识与记忆检索卡片

    private var memoryContextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "F472B6").opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "F472B6"))
                }

                Spacer()

                Text("\(memories.count) 记忆")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "F472B6"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "F472B6").opacity(0.12)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("知识与记忆检索")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                Text("Memory & Search")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
            }

            Spacer(minLength: 2)

            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: "F472B6"))
                    .frame(width: 6, height: 6)
                Text("全域语义索引支持")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .softGlassCard(cornerRadius: 18)
        .interactiveGlassCard(
            cornerRadius: 18,
            actions: [
                GlassCardAction(title: "全域搜索", icon: "magnifyingglass") {
                    showGlobalSearch = true
                },
                GlassCardAction(title: "记忆看板", icon: "brain") {
                    showMemoryBrowser = true
                },
                GlassCardAction(title: "数据流向", icon: "point.3.connected.trianglepath.dotted") {
                    showDataFlow = true
                }
            ],
            onPrimaryTap: {
                showGlobalSearch = true
            }
        )
    }

    // MARK: - 5. 进行中的会话与任务流 (Current Conversations)

    private var currentConversationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CURRENT CONVERSATIONS")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                // 如果本地有真实会话，展示真实会话；否则展示精美预设会话
                if !conversations.isEmpty {
                    ForEach(Array(conversations.prefix(4).enumerated()), id: \.element.id) { index, convo in
                        realConversationRow(convo)
                            .staggerCascade(index: index)
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
                    .staggerCascade(index: 0)

                    conversationRow(
                        title: "The Future of AI in Healthcare",
                        subtitle: "Analyzing current trends and automated clinical trials...",
                        time: "Yesterday",
                        onTap: {
                            coordinator.navigateToAssistant(withPrompt: "回顾医疗 AI 预测分析：")
                        }
                    )
                    .staggerCascade(index: 1)

                    conversationRow(
                        title: "Creative Copy for Marketing",
                        subtitle: "Generating slogans for the new liquid glass product line...",
                        time: "2 days ago",
                        onTap: {
                            coordinator.navigateToAssistant(withPrompt: "撰写液态玻璃主题创意文案：")
                        }
                    )
                    .staggerCascade(index: 2)
                }

                // 底部固定官方液态玻璃发光胶囊按钮：START NEW CHAT
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
                    .liquidGlass(
                        .regular.tint(accent.opacity(0.40)),
                        in: .capsule
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(scheme == .dark ? 0.50 : 0.85),
                                        accent.opacity(0.50)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.1
                            )
                            .allowsHitTesting(false)
                    }
                    .shadow(color: accent.opacity(scheme == .dark ? 0.35 : 0.16), radius: 10, y: 3)
                }
                .buttonStyle(StaticButtonFeedbackStyle())
                .padding(.top, 4)
            }
            .padding(16)
            .softGlassCard(cornerRadius: 22)
        }
    }

    private func realConversationRow(_ convo: Conversation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(convo.title.isEmpty ? "新对话" : convo.title)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .lineLimit(1)

                Text((convo.lastMessage?.text.isEmpty == false ? convo.lastMessage?.text : nil) ?? "点击继续进行多轮深度推理…")
                    .font(.system(size: 12))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .lineLimit(1)
            }

            Spacer()

            Text(convo.updatedAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppUI.textCaption(scheme: scheme))
                .padding(.top, 1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .interactiveGlassCard(
            cornerRadius: 12,
            actions: [
                GlassCardAction(title: "打开对话", icon: "bubble.left.and.bubble.right") {
                    coordinator.openConversation(id: convo.id)
                },
                GlassCardAction(title: "重命名", icon: "pencil") {
                    renamingConversation = convo
                    renameText = convo.title
                },
                GlassCardAction(title: "删除", icon: "trash", role: .destructive) {
                    Haptics.impact(.medium)
                    modelContext.delete(convo)
                    try? modelContext.save()
                }
            ],
            onPrimaryTap: {
                coordinator.openConversation(id: convo.id)
            }
        )
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
        // 会话列表行：去掉按压缩放/弹跳，点击即时响应
        .buttonStyle(.plain)
    }

    // MARK: - 6. 底部精选多模态资产展示卡片 (Artwork Showcase)


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


/// 底部星穹神树艺术图绘制组件
