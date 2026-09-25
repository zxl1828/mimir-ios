import SwiftUI
import SwiftData
import UIKit

/// 设置：个性化与功能、API 账户、主题、应用设置。
/// 根页只用 4 个分组呈现，具体参数分别下钻到各自子页，保证首屏干净。
struct SettingsView: View {

    let chat: ChatViewModel
    let list: ConversationListViewModel

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showDataFlow = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            List {
                // 分组 1：个性化与功能
                Section {
                    NavigationLink {
                        PersonalizationSettingsView()
                    } label: {
                        SettingsRow(icon: "face.smiling", title: "个性化")
                    }

                    NavigationLink {
                        MemorySettingsView()
                    } label: {
                        SettingsRow(icon: "book", title: "记忆")
                    }

                    NavigationLink {
                        PluginsSettingsView()
                    } label: {
                        SettingsRow(icon: "puzzlepiece", title: "插件")
                    }
                }

                // 分组 2：API 账户（BYOK，无订阅与内购）
                Section {
                    NavigationLink {
                        APIConfigSettingsView()
                    } label: {
                        SettingsRow(
                            icon: "key",
                            title: "API 配置",
                            detail: settings.hasUsableCredential ? "已配置" : "未配置"
                        )
                    }

                    NavigationLink {
                        UsageSettingsView(list: list)
                    } label: {
                        SettingsRow(icon: "chart.bar", title: "用量统计", detail: "按量计费")
                    }

                    Button {
                        Haptics.impact(.light)
                        showDataFlow = true
                    } label: {
                        SettingsRow(icon: "arrow.left.arrow.right", title: "数据流向")
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("API 账户")
                } footer: {
                    Text("自带 API Key 按调用量计费，App 内没有订阅与内购。全部费用由服务商按实际用量结算。")
                }

                // 分组 3：主题
                Section {
                    HStack(spacing: 12) {
                        SettingsIcon(name: "sun.max")
                        Text("外观")
                            .font(AppUI.rowTitle)
                            .foregroundStyle(AppUI.label)
                        Spacer(minLength: 8)
                        Picker("外观", selection: $settings.appearance) {
                            ForEach(AppAppearance.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    NavigationLink {
                        BackgroundSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(name: "photo.on.rectangle.angled")
                            Text("聊天背景")
                                .font(AppUI.rowTitle)
                                .foregroundStyle(AppUI.label)
                            Spacer(minLength: 8)
                            Text(settings.background.title)
                                .font(AppUI.subheadline)
                                .foregroundStyle(AppUI.label2)
                        }
                    }

                    NavigationLink {
                        AccentSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(name: "paintpalette")
                            Text("强调色")
                                .font(AppUI.rowTitle)
                                .foregroundStyle(AppUI.label)
                            Spacer(minLength: 8)
                            Circle()
                                .fill(settings.accent.color)
                                .frame(width: 14, height: 14)
                        }
                    }
                } header: {
                    Text("主题")
                }

                // 分组 4：应用设置
                Section {
                    NavigationLink {
                        GeneralSettingsView(list: list)
                    } label: {
                        SettingsRow(icon: "gearshape", title: "常规")
                    }
                } header: {
                    Text("应用设置")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showDataFlow) { DataFlowPanelView() }
    }
}

// MARK: - 复用行部件

/// 与 `SettingsRow` 图标样式一致的行首图标。
private struct SettingsIcon: View {

    let name: String

    @Environment(\.appAccent) private var accent

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(accent)
            .frame(width: 26, height: 26)
    }
}

/// 标题 + 当前值 + 滑杆。
private struct SettingsSlider: View {

    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var display: (Double) -> String = { String(format: "%.2f", $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display(value))
                    .foregroundStyle(AppUI.label2)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

// MARK: - 个性化

private struct PersonalizationSettingsView: View {

    @Environment(AppSettings.self) private var settings

    @State private var showAgentManager = false
    @State private var showTonePicker = false

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Button {
                    Haptics.impact(.light)
                    showAgentManager = true
                } label: {
                    SettingsRow(icon: "person.2.badge.gearshape", title: "智能体管理")
                }
                .buttonStyle(.plain)
            } header: {
                Text("智能体")
            } footer: {
                Text("智能体决定默认人设与系统提示词，可随时切换或新建。")
            }

            Section {
                Picker(
                    "合成引擎",
                    selection: Binding(
                        get: { settings.voice.resolvedSynthesisPreference },
                        set: { settings.voice.synthesisPreference = $0 }
                    )
                ) {
                    ForEach(VoiceSynthesisPreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Toggle("使用内置语音合成模型", isOn: $settings.voice.prefersBuiltInTTS)

                Button {
                    Haptics.impact(.light)
                    showTonePicker = true
                } label: {
                    SettingsRow(
                        icon: "waveform",
                        title: "音色",
                        detail: VoiceToneCatalog.summary(
                            voiceIdentifier: settings.voice.voiceIdentifier,
                            systemVoiceIdentifier: settings.voice.systemVoiceIdentifier
                        )
                    )
                }
                .buttonStyle(.plain)

                Toggle("允许打断（Barge-in）", isOn: $settings.voice.allowsBargeIn)

                SettingsSlider(
                    title: "语速",
                    value: $settings.voice.speechRate,
                    range: 0.6...1.6,
                    step: 0.05
                ) { String(format: "%.2f×", $0) }

                SettingsSlider(
                    title: "静音判定",
                    value: $settings.voice.silenceDuration,
                    range: 0.6...3.0,
                    step: 0.1
                ) { String(format: "%.1f 秒", $0) }

                Toggle("允许云端语音识别回退", isOn: $settings.voice.allowsCloudSTTFallback)
            } header: {
                Text("语音")
            } footer: {
                Text("语音识别与合成都默认在本机完成，音频不会离开设备。")
            }

            Section {
                Toggle("端侧回复建议", isOn: $settings.suggestionsEnabled)
                Toggle("锁屏实时活动", isOn: $settings.liveActivitiesEnabled)
            } header: {
                Text("智能提示")
            } footer: {
                Text("回复建议由本机模型生成，不会上传对话内容。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("个性化")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAgentManager) { AgentManagerView() }
        .sheet(isPresented: $showTonePicker) { VoiceTonePickerView() }
    }
}

// MARK: - 记忆

private struct MemorySettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @State private var showMemoryBrowser = false
    @State private var confirmClearMemories = false
    @State private var exportFailure: String?

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Toggle("启用本地记忆", isOn: $settings.memoryEnabled)
                Toggle("长对话自动摘要", isOn: $settings.autoSummarizeEnabled)
            } header: {
                Text("记忆")
            } footer: {
                Text("只有你明确说「记住…」时才会写入记忆，其它对话不会被自动收录。记忆与向量检索都在本机完成。")
            }

            Section {
                Button {
                    Haptics.impact(.light)
                    showMemoryBrowser = true
                } label: {
                    SettingsRow(icon: "book.closed", title: "记忆浏览器")
                }
                .buttonStyle(.plain)

                Button {
                    exportMemories()
                } label: {
                    SettingsRow(icon: "square.and.arrow.up", title: "导出记忆为 JSON")
                }
                .buttonStyle(.plain)

                if let exportFailure {
                    Text(exportFailure)
                        .font(AppUI.footnote)
                        .foregroundStyle(AppUI.label2)
                }

                Button("清空全部记忆", role: .destructive) { confirmClearMemories = true }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMemoryBrowser) { MemoryBrowserView() }
        .alert("清空全部记忆？", isPresented: $confirmClearMemories) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { clearMemories() }
        } message: {
            Text("该操作不可撤销，导出的备份不受影响。")
        }
    }

    private func exportMemories() {
        if let url = MemoryExporter.exportMemories(context: modelContext) {
            exportFailure = nil
            presentShareSheet([url])
        } else {
            exportFailure = "导出失败，请稍后再试。"
        }
    }

    private func clearMemories() {
        let descriptor = FetchDescriptor<MemoryEntry>()
        if let entries = try? modelContext.fetch(descriptor) {
            for entry in entries { modelContext.delete(entry) }
            try? modelContext.save()
        }
    }
}

// MARK: - 插件

private struct PluginsSettingsView: View {

    @Environment(AppSettings.self) private var settings

    @State private var showSkillManager = false
    @State private var showMCPServers = false
    @State private var showWebSearchSettings = false
    @State private var showScheduledTasks = false

    var body: some View {
        List {
            Section {
                Button {
                    Haptics.impact(.light)
                    showSkillManager = true
                } label: {
                    SettingsRow(icon: "wand.and.stars", title: "技能管理")
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.impact(.light)
                    showMCPServers = true
                } label: {
                    SettingsRow(icon: "point.3.connected.trianglepath.dotted", title: "MCP 服务器")
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.impact(.light)
                    showWebSearchSettings = true
                } label: {
                    SettingsRow(
                        icon: "globe",
                        title: "联网搜索",
                        detail: settings.webSearch.isEnabled ? "已开启" : "已关闭"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.impact(.light)
                    showScheduledTasks = true
                } label: {
                    SettingsRow(icon: "clock.badge.checkmark", title: "定时任务")
                }
                .buttonStyle(.plain)
            } header: {
                Text("扩展")
            } footer: {
                Text("MCP 工具的返回值默认只在本机使用，需要为每台服务器单独授权后才会随对话发送到云端。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("插件")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSkillManager) { SkillManagerView() }
        .sheet(isPresented: $showMCPServers) { MCPServersView() }
        .sheet(isPresented: $showWebSearchSettings) { WebSearchSettingsView() }
        .sheet(isPresented: $showScheduledTasks) { ScheduledTasksView() }
    }
}

// MARK: - API 配置

private struct APIConfigSettingsView: View {

    @Environment(AppSettings.self) private var settings

    @State private var keyDraft: String = ""
    @State private var showsKey: Bool = false
    @State private var validationMessage: String?
    @State private var isValidating = false

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                HStack(spacing: 10) {
                    Group {
                        if showsKey {
                            TextField("sk-...", text: $keyDraft)
                        } else {
                            SecureField("sk-...", text: $keyDraft)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppFont.onboardingField)

                    Button {
                        Haptics.impact(.light)
                        showsKey.toggle()
                    } label: {
                        Image(systemName: showsKey ? "eye.slash" : "eye")
                            .foregroundStyle(AppUI.label2)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Text("接口格式")
                    Spacer()
                    Text(settings.credential.format.displayName)
                        .foregroundStyle(AppUI.label2)
                }

                TextField("Base URL", text: $settings.credential.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppFont.codeSmall)

                TextField("模型 ID", text: $settings.credential.modelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppFont.codeSmall)

                Button {
                    Task { await saveAndValidate() }
                } label: {
                    HStack {
                        Text(isValidating ? "正在验证…" : "保存并验证")
                        Spacer()
                        if isValidating { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isValidating || keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let validationMessage {
                    Text(validationMessage)
                        .font(AppFont.hint)
                        .foregroundStyle(AppUI.label2)
                }

                Button("退出登录并清除 Key", role: .destructive) {
                    settings.signOut()
                    keyDraft = ""
                    validationMessage = nil
                }
            } header: {
                Text("接入")
            } footer: {
                Text("Key 只保存在本机钥匙串中。根据前缀自动识别格式：sk-ant- 为 Anthropic，sk- 为 OpenAI 兼容，其余按 DeepSeek 原生处理。")
            }

            Section {
                SettingsSlider(
                    title: "温度",
                    value: $settings.parameters.temperature,
                    range: 0...2,
                    step: 0.05
                )

                SettingsSlider(
                    title: "Top P",
                    value: $settings.parameters.topP,
                    range: 0.1...1,
                    step: 0.05
                )

                Stepper(
                    "最大输出 \(settings.parameters.maxTokens) tokens",
                    value: $settings.parameters.maxTokens,
                    in: 512...32_768,
                    step: 512
                )

                Toggle("流式输出", isOn: $settings.parameters.streamsResponse)

                VStack(alignment: .leading, spacing: 6) {
                    Text("系统提示词")
                        .font(AppUI.subheadline)
                        .foregroundStyle(AppUI.label)
                    TextEditor(text: $settings.parameters.systemPrompt)
                        .font(AppFont.codeSmall)
                        .frame(minHeight: 110)
                }
            } header: {
                Text("模型参数")
            } footer: {
                Text("思考档位会覆盖温度与最大输出；这里的数值作为手动微调的基线。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("API 配置")
        .navigationBarTitleDisplayMode(.inline)
        .task { keyDraft = settings.resolvedCredential.key }
    }

    private func saveAndValidate() async {
        isValidating = true
        validationMessage = nil
        defer { isValidating = false }

        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        var credential = APICredential.inferred(from: trimmed)
        credential.baseURL = settings.credential.baseURL
        credential.modelID = settings.credential.modelID

        let client = LLMClientFactory.make(for: credential)
        let result = await client.validate(credential: credential)

        if result.isReachable {
            do {
                try settings.storeCredential(credential)
                validationMessage = "验证通过，已保存到钥匙串。"
                Haptics.notify(.success)
            } catch {
                validationMessage = error.localizedDescription
                Haptics.notify(.error)
            }
        } else {
            validationMessage = result.message
            Haptics.notify(.error)
        }
    }
}

// MARK: - 用量统计

private struct UsageSettingsView: View {

    let list: ConversationListViewModel

    var body: some View {
        List {
            Section {
                usageRow("累计输入 tokens", value: "\(totalUsage.promptTokens)")
                usageRow("累计输出 tokens", value: "\(totalUsage.completionTokens + totalUsage.reasoningTokens)")
                usageRow("对话数量", value: "\(list.conversations.count)")
            } header: {
                Text("本机用量")
            } footer: {
                Text("统计仅基于本机记录，可能与服务商账单存在差异；费用按实际 API 调用量结算。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("用量统计")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var totalUsage: TokenUsage {
        list.conversations.reduce(TokenUsage.zero) { $0 + $1.totalUsage }
    }

    private func usageRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(AppUI.label2)
        }
    }
}

// MARK: - 强调色

private struct AccentSettingsView: View {

    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                ForEach(AppAccent.allCases) { option in
                    Button {
                        Haptics.impact(.light)
                        settings.accent = option
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(option.color)
                                .frame(width: 18, height: 18)
                            Text(option.title)
                                .foregroundStyle(AppUI.label)
                            Spacer(minLength: 8)
                            if settings.accent == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(option.color)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("强调色会影响按钮、开关与选中态。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("强调色")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 聊天背景

private struct BackgroundSettingsView: View {

    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                ForEach(AppBackground.allCases) { option in
                    Button {
                        Haptics.impact(.light)
                        settings.background = option
                    } label: {
                        HStack(spacing: 12) {
                            thumbnail(option)

                            Text(option.title)
                                .font(AppUI.rowTitle)
                                .foregroundStyle(AppUI.label)

                            Spacer(minLength: 8)

                            if settings.background == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(settings.accent.color)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("背景只作用于对话页；深浅色模式下会自动加一层底衬，保证正文可读。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("聊天背景")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func thumbnail(_ option: AppBackground) -> some View {
        Group {
            if let name = option.assetName {
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                AppUI.secondary
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppUI.separator.opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - 常规

private struct GeneralSettingsView: View {

    let list: ConversationListViewModel

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @State private var confirmClearConversations = false
    @State private var showDiagnostics = false

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Picker("对话保留", selection: $settings.retention) {
                    ForEach(RetentionPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                Button("删除全部对话", role: .destructive) { confirmClearConversations = true }
            } header: {
                Text("数据")
            } footer: {
                Text("保留策略按最后更新时间自动清理未置顶的对话。")
            }

            Section {
                Button {
                    Haptics.impact(.light)
                    showDiagnostics = true
                } label: {
                    SettingsRow(icon: "stethoscope", title: "崩溃与语音日志")
                }
                .buttonStyle(.plain)
            } header: {
                Text("诊断")
            }

            Section {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(versionString)
                        .foregroundStyle(AppUI.label2)
                }
                if let repositoryURL = URL(string: "https://github.com/zxl1828/mimir-ios") {
                    Link(destination: repositoryURL) {
                        Text("GitHub 仓库")
                    }
                }
            } header: {
                Text("关于")
            } footer: {
                Text("本地优先的私人 AI 客户端。界面、交互与数据策略均以你的设备为中心设计。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("常规")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        .alert("删除全部对话？", isPresented: $confirmClearConversations) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { clearConversations() }
        } message: {
            Text("所有对话记录会从本机删除，该操作不可撤销。")
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func clearConversations() {
        let descriptor = FetchDescriptor<Conversation>()
        if let conversations = try? modelContext.fetch(descriptor) {
            for conversation in conversations { modelContext.delete(conversation) }
            try? modelContext.save()
        }
        list.refresh()
    }
}
