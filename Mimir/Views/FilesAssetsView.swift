import SwiftUI
import UniformTypeIdentifiers

/// 页面二：知识资产库（Files & Assets View）。
///
/// 统一管理 RAG 知识库、提示词库、生成的图像与项目附属文件；
/// 支持真实挂载手机本地项目文件夹（Security-Scoped URL）与读写，并可一键把资产送入当前对话上下文。
struct FilesAssetsView: View {

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appAccent) private var accent

    @State private var workspace = WorkspaceManager.shared
    @State private var isGridView = true
    @State private var showFolderImporter = false
    @State private var showFileImporter = false
    @State private var showNewDocSheet = false
    @State private var showFABMenu = false
    @State private var selectedFileForAction: WorkspaceFileItem?
    @State private var previewFileItem: WorkspaceFileItem?
    @State private var isMountingWorkspace = false
    @State private var workspaceImportError: String?
    @State private var newDocTitle = ""
    @State private var newDocContent = ""

    private var coordinator: TabNavigationCoordinator {
        TabNavigationCoordinator.shared
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. 顶部标题与视图模式切换
                    headerBar
                        .staggerCascade(index: 0)

                    // 2. 搜索框与分类过滤药丸
                    searchAndFilterSection
                        .staggerCascade(index: 1)

                    // 3. 本地文件夹挂载状态横幅（Security-Scoped Workspace Banner）
                    workspaceMountBanner
                        .staggerCascade(index: 2)

                    // 4. 文件资产展示区（网格或列表）
                    if workspace.filteredFiles.isEmpty {
                        emptyStateCard
                            .staggerCascade(index: 3)
                    } else if isGridView {
                        assetGridSection
                            .staggerCascade(index: 3)
                    } else {
                        assetListSection
                            .staggerCascade(index: 3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 110) // 避让底部悬浮 TabBar 与 FAB
                .frame(maxWidth: 1040)
                .frame(maxWidth: .infinity)
            }
            .correctedSoftFadeMask(topFade: 16, bottomFade: 40)

            // 5. 右下角悬浮玻璃圆球 + 操作按钮 (FAB)
            fabMenuButton
                .padding(.trailing, 20)
                .padding(.bottom, 82)
                .zIndex(5)

            // 6. 底部“送入当前对话上下文”浮动栏
            if let target = selectedFileForAction {
                bottomAttachBar(for: target)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 76)
                    .zIndex(6)
            }
        }
        .background {
            AppUI.ambientBackground(scheme: scheme)
                .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let folder = urls.first {
                    mountWorkspace(urls: [folder])
                }
            case .failure:
                break
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                mountWorkspace(urls: urls)
            case .failure:
                break
            }
        }
        .sheet(isPresented: $showNewDocSheet) {
            newDocumentSheet
        }
        .sheet(item: $previewFileItem) { item in
            fileDetailSheet(item)
        }
        .alert("无法读取所选位置", isPresented: Binding(
            get: { workspaceImportError != nil },
            set: { if !$0 { workspaceImportError = nil } }
        )) {
            Button("好", role: .cancel) { workspaceImportError = nil }
        } message: {
            Text(workspaceImportError ?? "")
        }
    }

    // MARK: - 1. 顶部 Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("FILES / LIBRARY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                    Text("知识资产库")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 8)
                Button {
                    Haptics.impact(.light)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        isGridView.toggle()
                    }
                } label: {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                        .frame(width: 36, height: 36)
                        .liquidGlass(.clear, in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                }
                .buttonStyle(StaticButtonFeedbackStyle())
            }

            HStack(spacing: 7) {
                Image(systemName: workspace.activeWorkspaceURL == nil ? "externaldrive" : "externaldrive.fill.badge.checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(workspace.activeWorkspaceURL == nil ? AppUI.textCaption(scheme: scheme) : accent)
                Text(workspace.activeWorkspaceURL?.lastPathComponent ?? "本机资料与项目文件")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(workspace.filteredFiles.count) ITEMS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .softGlassCard(cornerRadius: 24)
    }

    // MARK: - 2. 搜索与分类过滤栏

    private var searchAndFilterSection: some View {
        VStack(spacing: 12) {
            // 极简磨砂搜索框
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))

                TextField("搜索知识库、Prompt 与文件...", text: $workspace.searchText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .autocorrectionDisabled()

                if !workspace.searchText.isEmpty {
                    Button {
                        workspace.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .softGlassCard(cornerRadius: 16)

            // 分类药丸 Segment 切换器
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WorkspaceFileItem.AssetCategory.allCases) { cat in
                        let isSelected = workspace.selectedCategory == cat
                        Button {
                            Haptics.selectionChanged()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                workspace.selectedCategory = cat
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 11.5, weight: isSelected ? .bold : .regular))
                                Text(cat.rawValue)
                                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                            }
                            .foregroundStyle(
                                isSelected
                                    ? Color.white
                                    : AppUI.textSubtitle(scheme: scheme)
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .liquidGlass(
                                isSelected
                                    ? .regular.tint(accent.opacity(0.85))
                                    : .clear,
                                in: .capsule
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        isSelected
                                            ? AnyShapeStyle(AppUI.refractionEdge(accent, scheme: scheme))
                                            : AnyShapeStyle(AppUI.separator),
                                        lineWidth: 1
                                    )
                                    .allowsHitTesting(false)
                            )
                        }
                        .buttonStyle(StaticButtonFeedbackStyle())
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - 3. 本地文件夹安全挂载横幅 (Local Workspace Banner)

    private var workspaceMountBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                if let active = workspace.activeWorkspaceURL {
                    Text("已挂载手机工作区：\(active.lastPathComponent)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                        .lineLimit(1)
                    Text("支持在手机上直接读取、分析并修改工程文件")
                        .font(.system(size: 11))
                        .foregroundStyle(AppUI.textCaption(scheme: scheme))
                } else {
                    Text("挂载手机项目文件夹")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    Text("授权后 Mimir 可对你的项目代码与文档进行读写")
                        .font(.system(size: 11))
                        .foregroundStyle(AppUI.textCaption(scheme: scheme))
                }
            }

            Spacer()

            Button {
                Haptics.impact(.light)
                showFolderImporter = true
            } label: {
                Text(isMountingWorkspace ? "正在读取…" : (workspace.activeWorkspaceURL == nil ? "选择目录" : "重新选择"))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .liquidGlass(
                        .regular.tint(accent.opacity(0.25)),
                        in: .capsule
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(accent.opacity(0.35), lineWidth: 0.8)
                            .allowsHitTesting(false)
                    )
            }
            .buttonStyle(StaticButtonFeedbackStyle())
            .disabled(isMountingWorkspace)
        }
        .padding(12)
        .softGlassCard(cornerRadius: 18)
    }

    private func mountWorkspace(urls: [URL]) {
        guard !urls.isEmpty else { return }
        isMountingWorkspace = true
        workspaceImportError = nil
        Task {
            defer { isMountingWorkspace = false }
            do {
                for url in urls {
                    try await workspace.mountFolder(url: url)
                }
            } catch {
                workspaceImportError = error.localizedDescription
            }
        }
    }

    // MARK: - 4. 网格视图

    private var assetGridSection: some View {
        let columns = [GridItem(.adaptive(minimum: 168, maximum: 280), spacing: 12)]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(workspace.filteredFiles.enumerated()), id: \.element.id) { index, item in
                assetGridCard(item)
                    .staggeredSlideEntrance(index: index)
            }
        }
    }

    private func assetGridCard(_ item: WorkspaceFileItem) -> some View {
        let isSelected = selectedFileForAction?.id == item.id

        return Button {
            Haptics.selectionChanged()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                if selectedFileForAction?.id == item.id {
                    selectedFileForAction = nil
                } else {
                    selectedFileForAction = item
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // 图标 / 缩略图
                if item.category == .media {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "2E1D5B"), Color(hex: "171033")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 72)
                        Image(systemName: "sparkles")
                            .font(.system(size: 26))
                            .foregroundStyle(AppUI.auroraViolet)
                    }
                } else {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(categoryColor(for: item.category).opacity(0.18))
                                .frame(width: 36, height: 36)
                            Image(systemName: item.systemIcon)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(categoryColor(for: item.category))
                        }
                        Spacer()
                        Text(item.fileExtension.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppUI.textCaption(scheme: scheme))
                    }
                }

                // 文件名
                Text(item.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .lineLimit(1)

                // 大小与更新时间
                HStack {
                    Text(item.formattedSize)
                    Spacer()
                    Text(item.relativeTime)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppUI.textCaption(scheme: scheme))
            }
            .padding(12)
            .softGlassCard(cornerRadius: 16)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent, lineWidth: 1.8)
                        .shadow(color: accent.opacity(0.4), radius: 6)
                }
            }
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .interactiveGlassCard(
            cornerRadius: 16,
            actions: [
                GlassCardAction(title: "挂载上下文", icon: "arrowshape.turn.up.right") {
                    coordinator.attachFileToChat(item)
                },
                GlassCardAction(title: "快速预览", icon: "eye") {
                    previewFileItem = item
                },
                GlassCardAction(title: "删除文件", icon: "trash", role: .destructive) {
                    workspace.deleteFile(item)
                }
            ]
        )
        .contextMenu {
            Button {
                coordinator.attachFileToChat(item)
            } label: {
                Label("送入当前对话上下文", systemImage: "arrowshape.turn.up.right")
            }
            Button {
                previewFileItem = item
            } label: {
                Label("查看文件详情/代码", systemImage: "doc.text.magnifyingglass")
            }
            if item.category == .code {
                Button {
                    workspace.currentActiveCodeFile = item
                    workspace.currentCodeContent = workspace.readFileContent(for: item)
                    coordinator.switchToTab(.code)
                } label: {
                    Label("在代码工坊中打开", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
    }

    // MARK: - 4. 列表视图

    private var assetListSection: some View {
        VStack(spacing: 8) {
            ForEach(Array(workspace.filteredFiles.enumerated()), id: \.element.id) { index, item in
                let isSelected = selectedFileForAction?.id == item.id
                Button {
                    Haptics.selectionChanged()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        if selectedFileForAction?.id == item.id {
                            selectedFileForAction = nil
                        } else {
                            selectedFileForAction = item
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.systemIcon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(categoryColor(for: item.category))
                            .frame(width: 32, height: 32)
                            .background(categoryColor(for: item.category).opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppUI.textTitle(scheme: scheme))
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text(item.formattedSize)
                                Text("•")
                                Text(item.relativeTime)
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(AppUI.textCaption(scheme: scheme))
                        }

                        Spacer()

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                            .font(.system(size: 14))
                            .foregroundStyle(isSelected ? accent : AppUI.textCaption(scheme: scheme))
                    }
                    .padding(12)
                    .softGlassCard(cornerRadius: 14)
                }
                .buttonStyle(StaticButtonFeedbackStyle())
                .staggeredSlideEntrance(index: index)
            }
        }
    }

    private var emptyStateCard: some View {
        let isSearching = !workspace.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(accent.opacity(scheme == .dark ? 0.16 : 0.09))
                    .frame(width: 76, height: 76)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(AppUI.refractionEdge(accent, scheme: scheme), lineWidth: 1)
                    }
                Image(systemName: isSearching ? "doc.text.magnifyingglass" : "folder.badge.plus")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(accent.gradient)
            }
            .padding(.bottom, 3)

            Text(isSearching ? "没有匹配项目" : "资料空间为空")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppUI.textTitle(scheme: scheme))
            Text(isSearching ? "0 个匹配项目" : "LOCAL LIBRARY  ·  0 ITEMS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppUI.textSubtitle(scheme: scheme))
            if !isSearching {
                Text("文件留存在本机")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
            }
            if !isSearching && workspace.activeWorkspaceURL == nil {
                Button {
                    showFolderImporter = true
                } label: {
                    Label("选择项目文件夹", systemImage: "folder.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .softGlassCard(cornerRadius: 26)
    }

    // MARK: - 5. 浮动操作按钮 (FAB)

    private var fabMenuButton: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if showFABMenu {
                VStack(alignment: .trailing, spacing: 8) {
                    fabSubAction(title: "挂载项目文件夹", icon: "folder.badge.plus") {
                        showFolderImporter = true
                    }
                    fabSubAction(title: "导入本地文件", icon: "doc.badge.plus") {
                        showFileImporter = true
                    }
                    fabSubAction(title: "新建知识文档", icon: "square.and.pencil") {
                        showNewDocSheet = true
                    }
                }
                .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }

            Button {
                Haptics.impact(.medium)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    showFABMenu.toggle()
                }
            } label: {
                Image(systemName: showFABMenu ? "xmark" : "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 52, height: 52)
                    .background {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.85), accent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .liquidGlass(.regular.tint(accent.opacity(0.60)), in: .circle)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.65), lineWidth: 1.2)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: accent.opacity(0.55), radius: 12, y: 5)
                    .rotationEffect(.degrees(showFABMenu ? 90 : 0))
            }
            .buttonStyle(StaticButtonFeedbackStyle())
        }
    }

    private func fabSubAction(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            showFABMenu = false
            action()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .liquidGlass(.regular, in: .capsule)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.35 : 0.70), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .shadow(color: accent.opacity(scheme == .dark ? 0.20 : 0.08), radius: 8, y: 3)
        }
        .buttonStyle(StaticButtonFeedbackStyle())
    }

    // MARK: - 6. 底部“送入当前对话上下文”浮动条

    private func bottomAttachBar(for item: WorkspaceFileItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemIcon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("已选定：\(item.name)")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(AppUI.textTitle(scheme: scheme))
                    .lineLimit(1)
                Text("点击一键挂载到输入框发起推理")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppUI.textCaption(scheme: scheme))
            }

            Spacer()

            Button {
                Haptics.impact(.medium)
                coordinator.attachFileToChat(item)
                selectedFileForAction = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("Attach to Chat")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .liquidGlass(
                    .regular.tint(accent.opacity(0.85)),
                    in: .capsule
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.9)
                        .allowsHitTesting(false)
                }
                .shadow(color: accent.opacity(0.4), radius: 6, y: 2)
            }
            .buttonStyle(StaticButtonFeedbackStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .softGlassCard(cornerRadius: 20)
        .padding(.horizontal, 16)
    }

    // MARK: - 辅助样式与弹窗

    private func categoryColor(for cat: WorkspaceFileItem.AssetCategory) -> Color {
        switch cat {
        case .all: return accent
        case .document: return Color(hex: "38BDF8")
        case .code: return Color(hex: "7C5CFC")
        case .media: return Color(hex: "F472B6")
        case .prompt: return Color(hex: "FBBF24")
        }
    }

    private var newDocumentSheet: some View {
        NavigationStack {
            Form {
                Section("文档名称") {
                    TextField("例如：SystemArchitecture.md", text: $newDocTitle)
                }
                Section("文档正文") {
                    TextEditor(text: $newDocContent)
                        .frame(minHeight: 180)
                }
            }
            .navigationTitle("新建知识文档")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showNewDocSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        if !newDocTitle.isEmpty {
                            _ = workspace.createNewFile(
                                name: newDocTitle,
                                content: newDocContent,
                                category: .document
                            )
                            newDocTitle = ""
                            newDocContent = ""
                            showNewDocSheet = false
                        }
                    }
                    .disabled(newDocTitle.isEmpty)
                }
            }
        }
    }

    private func fileDetailSheet(_ item: WorkspaceFileItem) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: item.systemIcon)
                            .font(.system(size: 24))
                            .foregroundStyle(categoryColor(for: item.category))
                        VStack(alignment: .leading) {
                            Text(item.name).font(.title3.bold())
                            Text(item.path).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 8)

                    Text(workspace.readFileContent(for: item))
                        .font(.system(size: 13, design: .monospaced))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            scheme == .dark
                                ? Color(hex: "120D1D").opacity(0.96)
                                : Color(hex: "F8F6FD")
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(16)
            }
            .navigationTitle("文件详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { previewFileItem = nil }
                }
            }
        }
    }
}
