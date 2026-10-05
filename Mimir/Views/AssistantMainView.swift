import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// 页面一：智能助手主工作区（AssistantMainView）。
///
/// 1:1 还原设计系统与动效规格：
/// 1. 废除应用内伪灵动岛，保留并精修悬浮天气/日程微胶囊（悬浮于中央大卡片上方 8~12pt 处）；
/// 2. 顶部状态栏背后集成 96pt 主题色流光微渐变层；
/// 3. 中央全息玻璃大卡片应用旋转 Conic Gradient 描边与呼吸弥散背光；
/// 4. 键盘弹起精准避让与四大金刚 TabBar 平滑下沉（offset: 100, opacity: 0）；
/// 5. 控制组（思考强度微胶囊 + 消息输入栏）通过 safeAreaInset(edge: .bottom) 悬浮贴合键盘上方 8~12pt；
/// 6. 全量绑定当前主题色与 6 大物理微动效引擎。
public struct AssistantMainView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme

    @State private var chat: ChatViewModel?
    @State private var list: ConversationListViewModel?
    @State private var agents: [AgentDockItem] = []
    @State private var skills: [Skill] = []
    @State private var mcpConfigs: [MCPServerConfig] = []

    @State private var isKeyboardVisible = false
    @State private var showReasoningCard = false
    @State private var showSettings = false
    @State private var showVoiceMode = false
    @State private var showScheduledTasks = false
    @State private var showMemoryBrowser = false
    @State private var showMCPServers = false
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var editingMessage: ChatMessage?
    @State private var editingText = ""
    @State private var branchTarget: ChatMessage?
    @State private var pendingScrollTarget: UUID?
    @State private var highlightedMessageID: UUID?
    @State private var lastScrollAt: Date = .distantPast
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showAttachmentOptions = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var toast: String?
    @State private var previewImage: UIImage?
    @State private var showToolsDrawer = false
    @State private var showWeatherDetail = false

    @State private var coordinator = TabNavigationCoordinator.shared
    @FocusState private var isFieldFocused: Bool

    /// 环境摘要文案（接入实时天气 / 日程数据源前的统一出口，避免散落魔法字符串）。
    private let weatherSummaryText = "今天 晴 · 24°C"
    private let agendaSummaryText = "日程已同步"

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            // 1. 顶部状态栏 96pt 主题色微光流光渐变层
            topStatusBarAmbientGlow
                .zIndex(20)

            // 2. 主列布局
            mainColumn
                .background(AppBackgroundView(background: settings.background))
        }
        .task { await bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isKeyboardVisible = true
                coordinator.isTabBarVisible = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                isKeyboardVisible = false
                if !isFieldFocused {
                    coordinator.isTabBarVisible = true
                }
            }
        }
        .onChange(of: isFieldFocused) { _, focused in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                coordinator.isTabBarVisible = !focused && !isKeyboardVisible
            }
            if focused && showReasoningCard {
                withAnimation(AppUI.snap) { showReasoningCard = false }
            }
        }
        .onChange(of: photoItem) { _, newValue in loadPickedPhoto(newValue) }
        .onChange(of: coordinator.pendingPromptToChat) { _, newPrompt in
            if let newPrompt {
                chat?.inputText = newPrompt
                coordinator.pendingPromptToChat = nil
                isFieldFocused = true
            }
        }
        .onChange(of: coordinator.shouldStartNewChat) { _, shouldStart in
            if shouldStart {
                newConversation()
                coordinator.shouldStartNewChat = false
            }
        }
        .onChange(of: coordinator.pendingOpenConversationID) { _, convoID in
            if let convoID {
                openSearchResult(conversationID: convoID, messageID: nil)
                coordinator.pendingOpenConversationID = nil
            }
        }
        .sheet(isPresented: $showSettings) {
            if let chat, let list {
                SettingsView(chat: chat, list: list)
            }
        }
        .sheet(isPresented: $showScheduledTasks) {
            ScheduledTasksView()
        }
        .fullScreenCover(isPresented: $showVoiceMode) {
            if let chat {
                VoiceModeView(chat: chat)
            }
        }
        .sheet(isPresented: $showMemoryBrowser) {
            MemoryBrowserView()
        }
        .sheet(isPresented: $showMCPServers) {
            MCPServersView()
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView(
                onCapture: { image in
                    appendImage(image)
                    showCamera = false
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showScanner) {
            DocumentScannerView(
                onFinish: { images in
                    images.forEach(appendImage)
                    showScanner = false
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .alert("重命名对话", isPresented: $editingTitle) {
            TextField("对话名称", text: $titleDraft)
            Button("取消", role: .cancel) {}
            Button("保存") { commitTitle() }
        }
        .alert("编辑消息", isPresented: Binding(
            get: { editingMessage != nil },
            set: { if !$0 { editingMessage = nil } }
        )) {
            TextField("消息内容", text: $editingText, axis: .vertical)
            Button("取消", role: .cancel) { editingMessage = nil }
            Button("重发") {
                if let message = editingMessage {
                    chat?.resend(editing: message, newText: editingText)
                }
                editingMessage = nil
            }
        }
        .alert("从这里重新生成？", isPresented: Binding(
            get: { branchTarget != nil },
            set: { if !$0 { branchTarget = nil } }
        )) {
            Button("取消", role: .cancel) { branchTarget = nil }
            Button("继续") {
                if let target = branchTarget {
                    chat?.regenerateFrom(message: target)
                }
                branchTarget = nil
            }
        } message: {
            Text(branchDeletionHint)
        }
        .overlay(alignment: .top) { toastView }
        .overlay {
            if let image = previewImage {
                SharedElementTransitionView(image: image) {
                    previewImage = nil
                }
                .zIndex(100)
            }
        }
        .overlay {
            VelocitySnappingDrawer(isPresented: $showToolsDrawer, minHeight: 180, maxHeight: 420) {
                toolsDrawerContent
            }
            .zIndex(90)
        }
    }

    // MARK: - 1. 顶部状态栏 96pt 主题色微光流光渐变层

    private var topStatusBarAmbientGlow: some View {
        LinearGradient(
            colors: [
                accent.opacity(scheme == .dark ? 0.24 : 0.16),
                accent.opacity(scheme == .dark ? 0.09 : 0.05),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 96)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    // MARK: - 2. 主列布局

    private var mainColumn: some View {
        VStack(spacing: 0) {
            topBar

            messageList
        }
        .background(Color.clear)
        // 控制组固定在屏幕底部：键盘弹起时由 safeAreaInset 随键盘自动平滑提升，悬浮于键盘上方 8~12pt
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomControlGroup
        }
    }

    // MARK: - 3. 顶栏 Command Header

    private var topBar: some View {
        HStack(spacing: 8) {
            UIBarButton(icon: "line.3.horizontal", label: "全局设置与中心") {
                if showReasoningCard {
                    withAnimation(AppUI.snap) { showReasoningCard = false }
                }
                showSettings = true
            }
            .contextMenu {
                Button {
                    Haptics.impact(.light)
                    titleDraft = chat?.conversation?.title ?? ""
                    editingTitle = true
                } label: {
                    Label("重命名当前对话", systemImage: "pencil")
                }
            }

            Spacer(minLength: 2)

            // 中间：模型命令胶囊滑块（Codex 桌面端样式）
            ModelSegmentedSwitcher(
                options: currentModelOptions,
                selectedID: Binding(
                    get: { currentModelID },
                    set: { selectModel($0) }
                ),
                onOpenSettings: { showSettings = true }
            )
            .frame(maxWidth: 236)

            Spacer(minLength: 2)

            // 右侧：思考档位脉冲触发圆钮
            UIBarButton(
                icon: "waveform.path.ecg",
                label: "思考强度：\(chat?.thinkingMode.heroTitle ?? "High")",
                isHighlighted: showReasoningCard
            ) {
                withAnimation(AppUI.snap) {
                    showReasoningCard.toggle()
                }
            }

            UIBarButton(icon: "square.and.pencil", label: "新建对话") {
                if showReasoningCard {
                    withAnimation(AppUI.snap) { showReasoningCard = false }
                }
                newConversation()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlass(.regular, in: .rect)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(scheme == .dark ? 0.25 : 0.60),
                            accent.opacity(0.35)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.8)
                .allowsHitTesting(false)
        }
    }

    private var currentModelID: String {
        chat?.activeModelID ?? settings.credential.modelID
    }

    private var currentModelOptions: [ModelCatalog.Option] {
        ModelCatalog.options(for: settings.credential, customModels: settings.customModels)
    }

    private func selectModel(_ modelID: String) {
        Haptics.selectionChanged()
        chat?.setModel(modelID)
        showToast("已切换到 \(ModelCatalog.cardLabel(for: modelID))")
    }

    // MARK: - 4. 消息列表视口

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if chat?.messages.isEmpty ?? true {
                        emptyStateMascotCard
                    }

                    ForEach(Array((chat?.messages ?? []).enumerated()), id: \.element.id) { index, message in
                        MessageBubble(
                            message: message,
                            isHighlighted: highlightedMessageID == message.id,
                            onCopy: {},
                            onRegenerate: { chat?.regenerate(message: message) },
                            onRegenerateHere: { branchTarget = message },
                            onSwitchVersion: { index in
                                chat?.switchVersion(of: message, to: index)
                            },
                            onQuote: { quote(message) },
                            onEdit: {
                                editingText = message.text
                                editingMessage = message
                            },
                            onDelete: {
                                Haptics.impact(.medium)
                                chat?.delete(message: message)
                            },
                            onOpenMemory: { _ in showMemoryBrowser = true },
                            onTapImage: { image in
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    previewImage = image
                                }
                            }
                        )
                        .staggerCascade(index: index)
                        .id(message.id)
                    }

                    Color.clear
                        .frame(height: 24)
                        .id(Self.bottomAnchor)
                }
                .padding(.vertical, 16)
            }
            .correctedSoftFadeMask(topFade: 20, bottomFade: 50)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    if showReasoningCard {
                        withAnimation(AppUI.snap) {
                            showReasoningCard = false
                        }
                    }
                }
            )
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scrollToBottom(proxy, animated: false) }
            .onChange(of: chat?.messages.count ?? 0) { _, _ in
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: lastMessageLength) { _, _ in
                throttleScrollToBottom(proxy)
            }
            .task(id: pendingScrollTarget) {
                guard let target = pendingScrollTarget else { return }
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(AppAnimation.bubble) {
                    proxy.scrollTo(target, anchor: .center)
                }
                highlightedMessageID = target
                pendingScrollTarget = nil
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeOut(duration: 0.3)) {
                    highlightedMessageID = nil
                }
            }
        }
    }

    // MARK: - 5. 空对话页：悬浮微胶囊 + 中央全息大卡片（Conic 旋转流光与呼吸背光）

    /// 天气 / 日程详情面板（胶囊的流体展开态）。
    private var ambientDetailPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(weatherSummaryText, systemImage: "cloud.sun.fill")
                .font(AppUI.subheadline)
                .foregroundStyle(AppUI.label)

            Label(agendaSummaryText, systemImage: "calendar")
                .font(AppUI.subheadline)
                .foregroundStyle(AppUI.label)

            Button {
                withAnimation(.interpolatingSpring(stiffness: 280, damping: 24)) {
                    showWeatherDetail = false
                }
            } label: {
                Text("收起")
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .correctedLiquidGlassCard(cornerRadius: 18)
        .accessibilityElement(children: .contain)
    }

    private var emptyStateMascotCard: some View {
        VStack(spacing: 12) {
            // 悬浮天气与日程胶囊：点击后由 FluidMorphContainer 流体变形为详情面板
            // （第 2 项物理动效：interpolatingSpring 驱动尺寸与圆角连续变形）
            FluidMorphContainer(isExpanded: $showWeatherDetail) {
                FloatingWeatherAgendaCapsule(
                    weatherText: weatherSummaryText,
                    agendaText: agendaSummaryText,
                    onTap: {
                        withAnimation(.interpolatingSpring(stiffness: 280, damping: 24)) {
                            showWeatherDetail = true
                        }
                    }
                )
            } expanded: {
                ambientDetailPanel
            }
            .padding(.bottom, 2)

            // 中央全息大卡片
            VStack(spacing: 16) {
                MimirMascot(size: 260, mood: .calm)
                    .padding(.bottom, 6)

                Text("Assistant Turn Workspace")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppUI.label)

                Text("Mimir Cyber-Owl Mascot")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent)

                Text("输入问题，用 / 唤起技能，或点按下方胶囊调节思考强度")
                    .font(AppUI.footnote)
                    .foregroundStyle(AppUI.label2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            // 第一阶段：内衬 Liquid Glass
            .liquidGlass(.regular.interactive(), in: .rect(cornerRadius: 30))
            // 第一阶段：360° 旋转渐变折射描边 (内部 strokeBorder)
            .conicGlowBorder(cornerRadius: 30, lineWidth: 1.2, isAnimated: true, isBreathing: false)
            // 第一、二、三阶段：流光、强硬圆角裁剪 (clipShape + contentShape)、
            // 动态呼吸弥散背光 (.shadow)、栅格化合成组 (.compositingGroup())、3D 透视倾斜与弹性微缩
            .tiltGlareCard(
                maxAngle: 7.5,
                cornerRadius: 30,
                showsSpecularSheen: true,
                hasAmbientBacklight: true
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
        }
        .padding(.top, 20)
        .padding(.bottom, 36)
    }

    // MARK: - 6. 底部控制区（思考胶囊 + 输入框）

    private var bottomControlGroup: some View {
        VStack(spacing: 8) {
            floatingPanels

            if let quoted = chat?.quotedMessage {
                quotedBar(quoted)
            }

            quickActionBar

            MessageInputBar(
                text: Binding(
                    get: { chat?.inputText ?? "" },
                    set: { chat?.inputText = $0 }
                ),
                attachments: Binding(
                    get: { chat?.attachedImages ?? [] },
                    set: { chat?.attachedImages = $0 }
                ),
                focus: $isFieldFocused,
                isGenerating: chat?.isGenerating ?? false,
                placeholder: "询问 Mimir…",
                onSend: {
                    if showReasoningCard {
                        withAnimation(AppUI.snap) { showReasoningCard = false }
                    }
                    chat?.send()
                },
                onStop: { chat?.stopGenerating() },
                showAttachMenu: $showAttachmentOptions,
                onPickPhoto: { showPhotoPicker = true },
                onCamera: { showCamera = true },
                onScan: { showScanner = true },
                onVoice: { showVoiceMode = true },
                onTextChanged: { chat?.handleInputChange($0) },
                onKeyCommand: { chat?.handleKeyCommand($0) ?? false }
            )
        }
        .padding(.horizontal, AppUI.hPadding)
        .padding(.top, 6)
        // 键盘弹起时距离键盘上沿精确保留 10pt 呼吸间距，无键盘时保留 TabBar 避让高度
        .padding(.bottom, (isFieldFocused || isKeyboardVisible) ? 10 : 80)
        .background {
            LinearGradient(
                colors: [
                    Color.clear,
                    (scheme == .dark ? Color.black : Color.white).opacity(0.82),
                    (scheme == .dark ? Color.black : Color.white).opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
    }

    /// 输入框上方的浮层：思考强度浮动卡片、MCP 工具进度、技能选择器与意图推荐
    @ViewBuilder
    private var floatingPanels: some View {
        VStack(spacing: 10) {
            if showReasoningCard {
                ReasoningEffortCard(
                    level: Binding(
                        get: { chat?.thinkingMode ?? .thinking },
                        set: { chat?.thinkingMode = $0 }
                    ),
                    options: currentModelOptions,
                    selectedModelID: Binding(
                        get: { currentModelID },
                        set: { selectModel($0) }
                    ),
                    onOpenSettings: {
                        withAnimation(AppUI.snap) { showReasoningCard = false }
                        showSettings = true
                    }
                )
                .padding(.horizontal, 16)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.90, anchor: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .offset(y: 12)),
                        removal: .scale(scale: 0.94, anchor: .bottom)
                            .combined(with: .opacity)
                    )
                )
            }

            if let chat {
                if !MCPClientManager.shared.activeCalls.isEmpty {
                    ToolProgressView(calls: MCPClientManager.shared.activeCalls)
                        .padding(.horizontal, 8)
                } else if chat.isSkillPickerVisible {
                    SkillPicker(
                        skills: chat.filteredSkills,
                        query: chat.slashQuery ?? "",
                        highlightedIndex: chat.highlightedSkillIndex,
                        onHighlight: { chat.highlightedSkillIndex = $0 },
                        onSelect: { chat.applySkill($0) },
                        onDismiss: { chat.dismissSkillPicker(removingCommand: false) }
                    )
                    .padding(.horizontal, 8)
                } else if !chat.skillSuggestions.isEmpty || !chat.replySuggestions.isEmpty {
                    SuggestionChips(
                        skillSuggestions: chat.skillSuggestions,
                        replySuggestions: chat.replySuggestions,
                        confidence: chat.recommendationConfidence,
                        onPickSkill: { chat.applySkill($0) },
                        onPickReply: { reply in
                            chat.inputText = reply
                            isFieldFocused = true
                        },
                        onDismiss: { chat.dismissRecommendations() }
                    )
                    .padding(.horizontal, 8)
                }
            }
        }
        .padding(.bottom, 2)
        .animation(.interpolatingSpring(stiffness: 280, damping: 24), value: showReasoningCard)
    }

    /// 输入框上方的快捷功能栏
    private var quickActionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ReasoningStatusChip(
                    modelID: currentModelID,
                    level: chat?.thinkingMode ?? .thinking,
                    isExpanded: showReasoningCard
                ) {
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 24)) {
                        showReasoningCard.toggle()
                    }
                }

                Rectangle()
                    .fill(AppUI.separator.opacity(0.5))
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, 2)

                UIQuickChip(icon: "photo", title: "生成图片") {
                    insertPrompt("画一张图片，画面是：")
                }

                UIQuickChip(icon: "pencil", title: "撰写或编辑") {
                    insertPrompt("帮我撰写或改写下面这段内容：")
                }

                UIQuickChip(icon: "globe", title: "搜索网页") {
                    insertPrompt("联网搜索并总结：")
                }

                Rectangle()
                    .fill(AppUI.separator.opacity(0.5))
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, 2)

                UIQuickChip(icon: "sparkles", title: "通用", isSelected: chat?.activeAgent == nil) {
                    chat?.activeAgent = nil
                }

                ForEach(agents) { agent in
                    UIQuickChip(
                        icon: agent.icon,
                        title: agent.name,
                        isSelected: chat?.activeAgent?.id == agent.id
                    ) {
                        chat?.activeAgent = agent
                        settings.selectedAgentName = agent.name
                    }
                }

                UIQuickChip(icon: "slider.horizontal.3", title: "工具箱") {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        showToolsDrawer = true
                    }
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
    }

    private func quotedBar(_ message: ChatMessage) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(message.role == .user ? "引用你的消息" : "引用 Mimir")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)

                Text(message.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12))
                    .foregroundStyle(AppUI.label2)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                withAnimation(AppUI.snap) {
                    chat?.quotedMessage = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppUI.label3)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlass(.regular, in: .rect(cornerRadius: 12))
        .glassHairline(cornerRadius: 12)
    }

    private var toolsDrawerContent: some View {
        VStack(spacing: 16) {
            HStack {
                Text("快捷工具箱")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppUI.label)
                Spacer()
                Button("完成") {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        showToolsDrawer = false
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
            }
            .padding(.horizontal, 18)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                toolDrawerItem(icon: "camera", title: "拍摄提问") {
                    showToolsDrawer = false
                    showCamera = true
                }
                toolDrawerItem(icon: "doc.viewfinder", title: "扫描文档") {
                    showToolsDrawer = false
                    showScanner = true
                }
                toolDrawerItem(icon: "mic.fill", title: "语音对话") {
                    showToolsDrawer = false
                    showVoiceMode = true
                }
                toolDrawerItem(icon: "clock.arrow.circlepath", title: "定时任务") {
                    showToolsDrawer = false
                    showScheduledTasks = true
                }
                toolDrawerItem(icon: "brain.head.profile", title: "记忆看板") {
                    showToolsDrawer = false
                    showMemoryBrowser = true
                }
                toolDrawerItem(icon: "network", title: "MCP 状态") {
                    showToolsDrawer = false
                    showMCPServers = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func toolDrawerItem(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .liquidGlass(.regular.interactive(), in: .circle)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8))

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppUI.label)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .pressScaleOvershoot(scale: 0.94, cornerRadius: 14)
    }

    // MARK: - 辅助状态与逻辑

    private static let bottomAnchor = "assistant.chat.bottom.anchor"

    private var lastMessageLength: Int {
        (chat?.messages.last?.text.count ?? 0) + (chat?.messages.last?.thinkingText.count ?? 0)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(AppAnimation.bubble) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    private func throttleScrollToBottom(_ proxy: ScrollViewProxy) {
        let now = Date()
        guard now.timeIntervalSince(lastScrollAt) >= 0.08 else { return }
        lastScrollAt = now
        scrollToBottom(proxy, animated: false)
    }

    private func insertPrompt(_ text: String) {
        chat?.inputText = text
        isFieldFocused = true
    }

    private func quote(_ message: ChatMessage) {
        chat?.quotedMessage = message
        isFieldFocused = true
    }

    private func newConversation() {
        guard let list, let chat else { return }
        let conversation = list.createConversation()
        chat.attach(to: conversation)
        isFieldFocused = true
        showToast("已新建对话")
    }

    private func commitTitle() {
        guard let conversation = chat?.conversation else { return }
        list?.rename(conversation, to: titleDraft)
        editingTitle = false
    }

    private var branchDeletionHint: String {
        guard let target = branchTarget,
              let ordered = chat?.conversation?.orderedMessages,
              let index = ordered.firstIndex(where: { $0.id == target.id }) else {
            return "这条消息会被重新生成，旧版本保留，可随时切换对比。"
        }
        let trailing = ordered.count - index - 1
        if trailing <= 0 {
            return "这条消息会保留旧版本，生成一个新的回答，之后可以左右切换对比。"
        }
        return "这条消息之后的 \(trailing) 条消息会收进分支（不会丢失），切回旧版本时可以原样恢复。"
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if toast == text { toast = nil }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.78))
                        .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
                )
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(200)
        }
    }

    private func appendImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        chat?.attachedImages.append(data)
        Haptics.impact(.light)
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    chat?.attachedImages.append(data)
                }
            }
            photoItem = nil
        }
    }

    private func openSearchResult(conversationID: UUID, messageID: UUID?) {
        guard let list, let chat else { return }
        guard let conversation = list.conversations.first(where: { $0.id == conversationID }) else { return }
        chat.attach(to: conversation)
        list.markUsed(conversation)
        if let messageID {
            pendingScrollTarget = messageID
        }
    }

    private func bootstrap() async {
        guard chat == nil else { return }
        let chatViewModel = ChatViewModel(modelContext: modelContext, settings: settings)
        let listViewModel = ConversationListViewModel(modelContext: modelContext, settings: settings)
        listViewModel.refresh()

        agents = (try? modelContext.fetch(
            FetchDescriptor<AgentDockItem>(sortBy: [SortDescriptor(\AgentDockItem.sortIndex)])
        )) ?? []
        skills = (try? modelContext.fetch(
            FetchDescriptor<Skill>(sortBy: [SortDescriptor(\Skill.sortIndex)])
        )) ?? []

        chat = chatViewModel
        list = listViewModel
        chatViewModel.skills = skills
        mcpConfigs = (try? modelContext.fetch(FetchDescriptor<MCPServerConfig>())) ?? []
        chatViewModel.mcpConfigs = mcpConfigs
        MemoryStore.shared.warmUp(context: modelContext)

        Task {
            await MCPClientManager.shared.reconnectAll(configs: mcpConfigs)
        }

        if let last = listViewModel.conversations.first {
            chatViewModel.attach(to: last)
        } else {
            let fresh = listViewModel.createConversation()
            chatViewModel.attach(to: fresh)
        }
        listViewModel.applyRetentionPolicy()
    }
}
