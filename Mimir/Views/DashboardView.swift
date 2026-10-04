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

    @State private var showSettings = false
    @State private var showHelpGuide = false
    @State private var showAgentManager = false
    @State private var showSkillManager = false
    @State private var showMCPServers = false
    @State private var showScheduledTasks = false
    @State private var showGlobalSearch = false
    @State private var showMemoryBrowser = false
    @State private var showDataFlow = false
    @State private var previewArtwork = false
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
                    .staggeredSlideEntrance(index: 0)

                // 2. 顶部快捷指令行（Quick Tools Grid）
                quickToolsRow
                    .staggeredSlideEntrance(index: 1)

                // 3. 四大核心业务工作区（智能体中心、技能工具箱、定时任务与项目、知识与记忆检索）
                coreWorkspaceCardsSection
                    .staggeredSlideEntrance(index: 2)

                // 4. 进行中的会话与任务流（CURRENT CONVERSATIONS）
                currentConversationsSection
                    .staggeredSlideEntrance(index: 3)

                // 5. 底部星穹神树精选多模态资产微展台
                artworkShowcaseCard
                    .staggeredSlideEntrance(index: 4)
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
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .frame(width: 34, height: 34)
                    .liquidGlass(.clear.interactive(), in: .circle)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.25 : 0.6), lineWidth: 0.8)
                            .allowsHitTesting(false)
                    }
            }
            .buttonStyle(PhysicalElasticCircleButtonStyle())

            // 设置按钮
            Button {
                Haptics.impact(.light)
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .frame(width: 34, height: 34)
                    .liquidGlass(.clear.interactive(), in: .circle)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.25 : 0.6), lineWidth: 0.8)
                            .allowsHitTesting(false)
                    }
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

    // MARK: - 3. 四大核心业务工作区 (4 大核心功能卡片)

    private var coreWorkspaceCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WORKSPACE CAPABILITIES")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .padding(.horizontal, 4)
                Spacer()
                Text("长按展开操作蒙版")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
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
                        .fill(AppUI.electricViolet.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "cpu")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppUI.electricViolet)
                }

                Spacer()

                Text("\(max(agents.count, 1)) 智能体")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppUI.electricViolet)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppUI.electricViolet.opacity(0.12)))
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
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppUI.electricViolet.opacity(0.32), lineWidth: 1.1)
                .allowsHitTesting(false)
        }
        .shadow(color: AppUI.electricViolet.opacity(0.12), radius: 10, y: 4)
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
        .interactiveTilt(maxAngle: 5.0, cornerRadius: 18)
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
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(hex: "38BDF8").opacity(0.32), lineWidth: 1.1)
                .allowsHitTesting(false)
        }
        .shadow(color: Color(hex: "38BDF8").opacity(0.12), radius: 10, y: 4)
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
        .interactiveTilt(maxAngle: 5.0, cornerRadius: 18)
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
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(hex: "34D399").opacity(0.32), lineWidth: 1.1)
                .allowsHitTesting(false)
        }
        .shadow(color: Color(hex: "34D399").opacity(0.12), radius: 10, y: 4)
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
        .interactiveTilt(maxAngle: 5.0, cornerRadius: 18)
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

                Text("\(MemoryStore.shared.factsCount) 记忆")
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
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(hex: "F472B6").opacity(0.32), lineWidth: 1.1)
                .allowsHitTesting(false)
        }
        .shadow(color: Color(hex: "F472B6").opacity(0.12), radius: 10, y: 4)
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
        .interactiveTilt(maxAngle: 5.0, cornerRadius: 18)
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
                    ForEach(Array(conversations.prefix(4))) { convo in
                        realConversationRow(convo)
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
                        .regular.tint(AppUI.electricViolet.opacity(0.40)).interactive(),
                        in: .capsule
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(scheme == .dark ? 0.50 : 0.85),
                                        AppUI.electricViolet.opacity(0.50)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.1
                            )
                            .allowsHitTesting(false)
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
