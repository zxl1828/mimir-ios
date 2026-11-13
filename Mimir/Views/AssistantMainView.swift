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
    @Environment(\.dismiss) private var dismiss

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
    @State private var showBeamSetup = false
    @State private var beamModelDraft = "gpt-4o-mini, deepseek-chat"
    @State private var beamPromptDraft = ""
    @State private var showWeatherDetail = false
    @State private var isImageGenerationMode = false
    @State private var isGeneratingImage = false
    @State private var imageGenerationTask: Task<Void, Never>?

    @State private var coordinator = TabNavigationCoordinator.shared
    @FocusState private var isFieldFocused: Bool

    /// 环境摘要文案（接入实时天气 / 日程数据源前的统一出口，避免散落魔法字符串）。
    private let weatherSummaryText = "今天 晴 · 24°C"
    private let agendaSummaryText = "日程已同步"

    /// 从首页 Push 进入时的入参。
    /// - `initialConversationID`：直接打开指定会话；
    /// - `startsNewConversation`：直接开一条新会话；
    /// - `showsBackButton`：Push 场景下顶栏左侧显示返回键，根场景显示头像。
    private let initialConversationID: UUID?
    private let startsNewConversation: Bool
    private let showsBackButton: Bool

    public init(
        initialConversationID: UUID? = nil,
        startsNewConversation: Bool = false,
        showsBackButton: Bool = false
    ) {
        self.initialConversationID = initialConversationID
        self.startsNewConversation = startsNewConversation
        self.showsBackButton = showsBackButton
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Task 3: Split-Prism Arena 对比浮层
            if let chat, chat.showBeamArena {
                BeamSynthesisView(
                    responses: chat.beamResponses,
                    isStreaming: chat.isBeamStreaming,
                    synthesis: chat.beamSynthesis,
                    synthesisError: chat.beamSynthesisError,
                    isSynthesizing: chat.isBeamSynthesizing,
                    onSynthesize: { chat.synthesizeBeamResponses() },
                    onCommit: { response, synthesized in chat.commitBeamResponse(response, synthesized: synthesized) },
                    onDismiss: { chat.showBeamArena = false }
                )
                .padding(.top, 64)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
                .zIndex(150)
            }

            // Status-bar lighting and blur sit behind controls so they never frost the top bar.
            mainColumn
                .background { topStatusBarAmbientGlow }
        }
        // 本页自带顶栏，隐藏系统导航栏与系统返回键，避免出现两条返回键。
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task {
            // 从首页点进来时不要自动弹键盘，让用户先看清这一页。
            isFieldFocused = false
            // 聊天页是 Push 出来的独立页面，底部导航坞必须收起：
            // 否则它悬浮在输入框上方，既挡视线也吃掉输入框的点击。
            coordinator.isTabBarVisible = false
            await bootstrap()
        }
        .sheet(isPresented: $showBeamSetup) {
            beamSetupSheet
        }
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
        .onChange(of: coordinator.pendingAttachedFile) { _, file in
            if let file { attachWorkspaceFileContext(file) }
        }
        .onChange(of: coordinator.pendingImageGenerationPromptToChat) { _, prompt in
            guard let prompt else { return }
            isImageGenerationMode = true
            chat?.inputText = prompt
            coordinator.pendingImageGenerationPromptToChat = nil
            isFieldFocused = true
            if !imageGenerationAvailable {
                showToast("请先在设置中配置图像生成模型。")
                showSettings = true
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
                VoiceDuplexView(chat: chat)
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

    private var isConversationEmpty: Bool {
        chat?.messages.isEmpty ?? true
    }

    // MARK: - Status bar lighting and blur

    private var topStatusBarAmbientGlow: some View {
        ZStack(alignment: .top) {
            // 1. 高斯模糊毛玻璃层：向下平滑羽化渐隐
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white.opacity(0.85), location: 0.45),
                            .init(color: .white.opacity(0.25), location: 0.80),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

        }
        .frame(height: 92)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    // MARK: - 2. 主列布局

    private var mainColumn: some View {
        VStack(spacing: 0) {
            topBar

            if isConversationEmpty {
                lockedEmptyStateViewport
            } else {
                messageList
            }
        }
        .background(Color.clear)
        // 控制组固定在屏幕底部：键盘弹起时由 safeAreaInset 随键盘自动平滑提升，悬浮于键盘上方 8~12pt
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomControlGroup
        }
    }

    // MARK: - 3. 顶栏 Command Header

    private var leadingHeaderButton: some View {
        Group {
            if showsBackButton {
                Button {
                    Haptics.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppUI.label)
                        .frame(width: 38, height: 38)
                        .nativeGlass(.circle)
                        .contentShape(Circle())
                }
                .buttonStyle(StaticButtonFeedbackStyle())
                .accessibilityLabel("返回")
            } else {
                Button {
                    if showReasoningCard {
                        withAnimation(AppUI.snap) { showReasoningCard = false }
                    }
                    showSettings = true
                } label: {
                    ProfileAvatarBadge(size: 30)
                        .frame(width: 38, height: 38)
                        .nativeGlass(.circle)
                        .contentShape(Circle())
                }
                .buttonStyle(StaticButtonFeedbackStyle())
                .accessibilityLabel("个人资料与设置")
                .contextMenu {
                    Button {
                        Haptics.impact(.light)
                        titleDraft = chat?.conversation?.title ?? ""
                        editingTitle = true
                    } label: {
                        Label("重命名当前对话", systemImage: "pencil")
                    }
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            leadingHeaderButton

            // 两行标题：第一行是会话名（粗体、可截断），第二行是"状态点 + 模型"。
            // 参照截图里这一块完全不加底色——顶栏是透明浮在页面上的，不是一条玻璃横条。
            VStack(alignment: .leading, spacing: 2) {
                Text(chat?.conversation?.title ?? "新对话")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(AppUI.label)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // 模型名本身就是下拉菜单：不吃宽度、不截断，点一下就能换模型。
                Menu {
                    ForEach(currentModelOptions, id: \.id) { option in
                        Button {
                            selectModel(option.id)
                        } label: {
                            if option.id == currentModelID {
                                Label(ModelCatalog.cardLabel(for: option.id), systemImage: "checkmark")
                            } else {
                                Text(ModelCatalog.cardLabel(for: option.id))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(accent.opacity(0.85))
                            .frame(width: 5, height: 5)
                        Text(ModelCatalog.cardLabel(for: currentModelID))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppUI.label2)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            // 模型切换已经挪到副标题的下拉菜单里，这里只留会话级操作。
            Menu {
                Button {
                    Haptics.impact(.light)
                    titleDraft = chat?.conversation?.title ?? ""
                    editingTitle = true
                } label: {
                    Label("重命名对话", systemImage: "pencil")
                }

                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppUI.label)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(headerGlassFill))
                    .overlay(Circle().strokeBorder(headerHairline, lineWidth: 1))
            }
            .accessibilityLabel("更多操作")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// 顶栏玻璃圆钮的底与描边：足够的通透感，但只用 1px hairline，不做高光渐变。
    private var headerGlassFill: Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.70)
    }

    private var headerHairline: Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06)
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

    // MARK: - 5. 锁定不滚动自适应全屏视口（Non-Scrollable Locked Viewport & Adaptive Layout）

    /// Top-edge blur fades out over 48pt.
    ///
    /// 用 `.ultraThinMaterial` 做渐进模糊，再以纯 alpha 蒙版控制淡出。
    /// 向下淡出——不带任何颜色叠加，因此不会产生脏灰块。
    /// 遮罩 `allowsHitTesting(false)`，完全不影响顶栏按钮的点击。
    private var topBlurScrim: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: 48)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0.0),
                        .init(color: .white, location: 0.62),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

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
        .softGlassCard(cornerRadius: 18)
        .accessibilityElement(children: .contain)
    }

    private var lockedEmptyStateViewport: some View {
        GeometryReader { proxy in
            let availableHeight = proxy.size.height
            // 依据可用视口高度自适应调整猫头鹰尺寸 (140 ~ 210pt)，在所有机型上绝不发生文本截断或挤压碰撞
            let isCompact = availableHeight < 360
            let mascotSize = min(210, max(isCompact ? 64 : 112, availableHeight * (isCompact ? 0.22 : 0.28)))

            VStack(spacing: 0) {
                // 顶栏避让弹性间距
                Spacer(minLength: 8)

                // 1. 悬浮天气与日程微胶囊（保留充足呼吸空间，杜绝与顶栏或灵动岛碰撞重叠）
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
                .padding(.top, 4)
                .padding(.bottom, 6)

                Spacer(minLength: 8)

                // 2. 中央猫头鹰 RAG 知识共振轨道与状态
                CyberOwlHeaderView(mascotSize: mascotSize, isCompact: isCompact)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)

                // 3. 轻量快捷指令：把"能做什么"直接摆出来，比一句口号有用。
                if !isCompact {
                    quickStarterChips
                        .padding(.top, 12)
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                if showReasoningCard {
                    withAnimation(AppUI.snap) { showReasoningCard = false }
                }
                if isFieldFocused {
                    isFieldFocused = false
                }
            }
        }
    }

    // MARK: - 6. 底部控制区（思考强度面板 + 输入框）

    /// 空对话时给出的三条轻量快捷指令。
    private struct QuickStarter: Identifiable {
        let id: String
        let title: String
        let icon: String
    }

    private var quickStarterChips: some View {
        let starters: [QuickStarter] = [
            QuickStarter(id: "schedule", title: "总结今天的日程", icon: "calendar"),
            QuickStarter(id: "files", title: "看看工作区文件", icon: "folder"),
            QuickStarter(id: "search", title: "帮我查个资料", icon: "magnifyingglass")
        ]
        return HStack(spacing: 8) {
            ForEach(starters) { starter in
                Button {
                    Haptics.selectionChanged()
                    chat?.inputText = starter.title
                    isFieldFocused = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: starter.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(starter.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(AppUI.label2)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(AppUI.consolePanel(scheme: scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(AppUI.consoleHairline(scheme: scheme), lineWidth: 1)
                    )
                }
                .buttonStyle(StaticButtonFeedbackStyle())
            }
        }
    }

    /// 长对话被滚动压缩后的一次性提示。说来就够，不用做成可交互的东西。
    private var compressedNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(accent)

            Text("上下文已压缩")
                .font(AppUI.mono(10.5, weight: .medium))
                .foregroundStyle(AppUI.label2)

            Spacer(minLength: 4)

            Button {
                chat?.contextCompressedNotice = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AppUI.label3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(StaticButtonFeedbackStyle())
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .nativeGlassRect(cornerRadius: 14, interactive: false)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// 思考强度入口：当前模型不支持调节推理深度时整条隐藏。
    @ViewBuilder
    private var reasoningBar: some View {
        if ModelCatalog.supportsReasoningControl(for: currentModelID) {
            ThinkingControl(
                mode: Binding(
                    get: { chat?.thinkingMode ?? .thinking },
                    set: { chat?.thinkingMode = $0 }
                ),
                modelID: currentModelID,
                options: currentModelOptions,
                onSelectModel: selectModel
            )
        }
    }

    private var bottomControlGroup: some View {
        VStack(spacing: 8) {
            // 任务面板：模型用 update_plan 写下步骤后才出现，平时完全不占位。
            TaskBoardCard()

            if chat?.contextCompressedNotice == true {
                compressedNotice
            }

            reasoningBar

            if let quoted = chat?.quotedMessage {
                quotedBar(quoted)
            }

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
                isGenerating: (chat?.isGenerating ?? false) || isGeneratingImage,
                placeholder: "询问 Mimir…",
                onSend: {
                    if showReasoningCard {
                        withAnimation(AppUI.snap) { showReasoningCard = false }
                    }
                    if isImageGenerationMode {
                        generateImage()
                    } else {
                        chat?.send()
                    }
                },
                onStop: {
                    if isGeneratingImage { imageGenerationTask?.cancel() }
                    else { chat?.stopGenerating() }
                },
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
        // 键盘弹起时距离键盘上沿保留 8pt；无键盘时留 28pt，
        // 让输入框和 Home 指示条之间有一点呼吸空间。
        .padding(.bottom, (isFieldFocused || isKeyboardVisible) ? 8 : 28)
        .background {
            LinearGradient(
                colors: [
                    Color.clear,
                    (scheme == .dark ? Color(hex: "0B0713") : Color(hex: "F7F4FD")).opacity(0.85),
                    (scheme == .dark ? Color(hex: "170E27") : Color.white).opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
    }

    private var beamSetupSheet: some View {
        NavigationStack {
            Form {
                Section("参与模型 · 2 至 4 个") {
                    TextEditor(text: $beamModelDraft)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 90)
                    Text("每行一个模型 ID。所有请求使用当前 API 凭据与服务地址；网关需开放这些模型。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Section("本次问题") {
                    TextEditor(text: $beamPromptDraft)
                        .frame(minHeight: 72)
                    if beamPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("先在这里写入要比较的问题。")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Text("候选模型并行流式回答，随后由当前会话模型裁判融合。所有并行调用都会分别计入 API 成本。")
                        .font(.system(size: 12))
                }
            }
            .navigationTitle("Beam Synthesis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showBeamSetup = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") {
                        let ids = beamModelDraft
                            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        guard (2...4).contains(Set(ids).count) else { return }
                        chat?.triggerBeamSynthesis(prompt: beamPromptDraft, modelIDs: ids, images: chat?.attachedImages ?? [])
                        showBeamSetup = false
                    }
                    .disabled(beamPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !(2...4).contains(Set(beamModelDraft.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).count))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }


    private func quotedBar(_ message: ChatMessage) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

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
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
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
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppUI.label)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(StaticButtonFeedbackStyle())
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

    private func attachWorkspaceFileContext(_ file: WorkspaceFileItem) {
        coordinator.pendingAttachedFile = nil
        guard !file.isDirectory, let fileURL = file.url,
              let rootURL = WorkspaceManager.shared.activeWorkspaceURL?.standardizedFileURL else {
            showToast("请选择工作区内的文本或代码文件。")
            return
        }
        let needsSecurityScope = !WorkspaceManager.shared.isInAppDocuments(rootURL)
        Task {
            do {
                let content = try await Task.detached(priority: .userInitiated) { () throws -> String in
                    let accessing = !needsSecurityScope || rootURL.startAccessingSecurityScopedResource()
                    guard accessing else { throw WorkspaceAccessError.accessDenied }
                    defer { if needsSecurityScope { rootURL.stopAccessingSecurityScopedResource() } }
                    let root = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
                    let target = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
                    guard target.hasPrefix(root + "/") else { throw WorkspaceAccessError.invalidPath }
                    let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true else { throw WorkspaceAccessError.invalidPath }
                    guard (values.fileSize ?? 0) <= 256_000 else { throw WorkspaceAccessError.fileTooLarge }
                    let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                    guard data.count <= 256_000, let text = String(data: data, encoding: .utf8) else {
                        throw WorkspaceAccessError.unreadableFile
                    }
                    return text
                }.value
                chat?.inputText += "\n\n--- \(file.path) ---\n\(content)\n--- 文件结束 ---"
                isFieldFocused = true
                showToast("文件内容已加入输入框，请检查后发送。")
            } catch {
                showToast("读取文件失败：\(error.localizedDescription)")
            }
        }
    }

    private var imageGenerationAvailable: Bool {
        let credential = settings.resolvedImageGenerationCredential
        return !credential.key.isEmpty
            && !credential.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !credential.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func generateImage() {
        guard !isGeneratingImage else { return }
        guard imageGenerationAvailable else {
            isImageGenerationMode = false
            showToast("请先在设置中填写支持图像生成的模型 ID。")
            showSettings = true
            return
        }
        guard let chat, let conversation = chat.conversation else {
            showToast("当前没有可用会话。")
            return
        }
        let prompt = chat.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let credential = settings.resolvedImageGenerationCredential
        let imageModelID = credential.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let userMessage = ChatMessage(
            role: .user,
            text: "生成图片：\(prompt)",
            orderIndex: conversation.nextOrderIndex,
            thinkingMode: chat.thinkingMode
        )
        modelContext.insert(userMessage)
        userMessage.conversation = conversation
        conversation.updatedAt = Date()
        conversation.regenerateTitleIfNeeded()
        chat.inputText = ""
        chat.handleInputChange("")
        try? modelContext.save()

        isGeneratingImage = true
        isImageGenerationMode = false
        imageGenerationTask = Task {
            do {
                let imageData = try await ImageGenerationService.generate(
                    prompt: prompt,
                    modelID: imageModelID,
                    credential: credential
                )
                try Task.checkCancellation()
                let response = ChatMessage(
                    role: .assistant,
                    text: "图像生成完成",
                    orderIndex: conversation.nextOrderIndex,
                    thinkingMode: chat.thinkingMode
                )
                response.attachmentData = imageData
                response.attachmentKind = "image"
                modelContext.insert(response)
                response.conversation = conversation
                conversation.updatedAt = Date()
                try modelContext.save()
                showToast("图像已生成")
            } catch {
                if chat.conversation?.id == conversation.id {
                    chat.inputText = prompt
                    isImageGenerationMode = true
                }
                showToast(Task.isCancelled ? "已停止图像生成" : error.localizedDescription)
            }
            isGeneratingImage = false
            imageGenerationTask = nil
        }
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
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color(red: 0.18, green: 0.12, blue: 0.32).opacity(0.90))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(accent.opacity(0.45), lineWidth: 0.8)
                        )
                        .shadow(color: accent.opacity(0.30), radius: 10, y: 4)
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

        // 首页 Push 进入：优先打开指定会话，其次新会话，最后才是"最近一条"。
        if let target = initialConversationID.flatMap({ id in
            listViewModel.conversations.first(where: { $0.id == id })
        }) {
            chatViewModel.attach(to: target)
        } else if startsNewConversation {
            chatViewModel.attach(to: listViewModel.createConversation())
        } else if let last = listViewModel.conversations.first {
            chatViewModel.attach(to: last)
        } else {
            chatViewModel.attach(to: listViewModel.createConversation())
        }
        listViewModel.applyRetentionPolicy()
    }
}

// MARK: - 猫头鹰能量舞台

/// 无卡片边界的光学舞台：轨道、粒子与环境辉光围绕猫头鹰构成纵深焦点。
