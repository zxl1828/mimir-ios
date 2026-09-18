import SwiftUI
import SwiftData
import UIKit

/// 设置：接入、模型参数、语音、数据与隐私、用量、关于。
struct SettingsView: View {

    let chat: ChatViewModel
    let list: ConversationListViewModel

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var keyDraft: String = ""
    @State private var showsKey: Bool = false
    @State private var validationMessage: String?
    @State private var isValidating = false
    @State private var showDataFlow = false
    @State private var showAgentManager = false
    @State private var showMemoryBrowser = false
    @State private var showSkillManager = false
    @State private var showMCPServers = false
    @State private var confirmClearMemories = false
    @State private var confirmClearConversations = false
    @State private var exportURL: URL?

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                accessSection(settings: $settings)
                parameterSection(settings: $settings)
                voiceSection(settings: $settings)
                privacySection(settings: $settings)
                extensionsSection
                usageSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { keyDraft = settings.resolvedCredential.key }
        .sheet(isPresented: $showDataFlow) { DataFlowPanelView() }
        .sheet(isPresented: $showMemoryBrowser) { MemoryBrowserView() }
        .sheet(isPresented: $showAgentManager) { AgentManagerView() }
        .sheet(isPresented: $showSkillManager) { SkillManagerView() }
        .sheet(isPresented: $showMCPServers) { MCPServersView() }
        .alert("清空全部记忆？", isPresented: $confirmClearMemories) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { clearMemories() }
        } message: {
            Text("该操作不可撤销，导出的备份不受影响。")
        }
        .alert("删除全部对话？", isPresented: $confirmClearConversations) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { clearConversations() }
        } message: {
            Text("所有对话记录会从本机删除，该操作不可撤销。")
        }
    }

    // MARK: - 接入

    private func accessSection(settings: Bindable<AppSettings>) -> some View {
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
                        .foregroundStyle(AppColor.secondaryText)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("接口格式")
                Spacer()
                Text(settings.wrappedValue.credential.format.displayName)
                    .foregroundStyle(AppColor.secondaryText)
            }

            TextField("Base URL", text: settings.credential.baseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppFont.codeSmall)

            TextField("模型 ID", text: settings.credential.modelID)
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
                    .foregroundStyle(AppColor.secondaryText)
            }

            Button("退出登录并清除 Key", role: .destructive) {
                settings.wrappedValue.signOut()
                keyDraft = ""
                validationMessage = nil
            }
        } header: {
            Text("接入")
        } footer: {
            Text("Key 只保存在本机钥匙串中。根据前缀自动识别格式：sk-ant- 为 Anthropic，sk- 为 OpenAI 兼容，其余按 DeepSeek 原生处理。")
        }
    }

    // MARK: - 模型参数

    private func parameterSection(settings: Bindable<AppSettings>) -> some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("温度")
                    Spacer()
                    Text(String(format: "%.2f", settings.wrappedValue.parameters.temperature))
                        .foregroundStyle(AppColor.secondaryText)
                }
                Slider(value: settings.parameters.temperature, in: 0...2, step: 0.05)
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("Top P")
                    Spacer()
                    Text(String(format: "%.2f", settings.wrappedValue.parameters.topP))
                        .foregroundStyle(AppColor.secondaryText)
                }
                Slider(value: settings.parameters.topP, in: 0.1...1, step: 0.05)
            }

            Stepper(
                "最大输出 \(settings.wrappedValue.parameters.maxTokens) tokens",
                value: settings.parameters.maxTokens,
                in: 512...32_768,
                step: 512
            )

            Toggle("流式输出", isOn: settings.parameters.streamsResponse)

            VStack(alignment: .leading, spacing: 6) {
                Text("系统提示词")
                    .font(.system(size: 14, weight: .medium))
                TextEditor(text: settings.parameters.systemPrompt)
                    .font(AppFont.codeSmall)
                    .frame(minHeight: 110)
            }
        } header: {
            Text("模型参数")
        } footer: {
            Text("思考档位会覆盖温度与最大输出；这里的数值作为手动微调的基线。")
        }
    }

    // MARK: - 语音

    private func voiceSection(settings: Bindable<AppSettings>) -> some View {
        Section {
            Picker(
                "合成引擎",
                selection: Binding(
                    get: { settings.wrappedValue.voice.resolvedSynthesisPreference },
                    set: { settings.voice.synthesisPreference.wrappedValue = $0 }
                )
            ) {
                ForEach(VoiceSynthesisPreference.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            Toggle("使用内置语音合成模型", isOn: settings.voice.prefersBuiltInTTS)
            Toggle("允许打断（Barge-in）", isOn: settings.voice.allowsBargeIn)

            VStack(alignment: .leading) {
                HStack {
                    Text("语速")
                    Spacer()
                    Text(String(format: "%.2f×", settings.wrappedValue.voice.speechRate))
                        .foregroundStyle(AppColor.secondaryText)
                }
                Slider(value: settings.voice.speechRate, in: 0.6...1.6, step: 0.05)
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("静音判定")
                    Spacer()
                    Text(String(format: "%.1f 秒", settings.wrappedValue.voice.silenceDuration))
                        .foregroundStyle(AppColor.secondaryText)
                }
                Slider(value: settings.voice.silenceDuration, in: 0.6...3.0, step: 0.1)
            }

            Toggle("允许云端语音识别回退", isOn: settings.voice.allowsCloudSTTFallback)
        } header: {
            Text("语音")
        } footer: {
            Text("语音识别与合成都默认在本机完成，音频不会离开设备。内置模型随 App 一起打包，中文朗读会自动使用系统语音以保证自然度。")
        }
    }

    // MARK: - 数据与隐私

    private func privacySection(settings: Bindable<AppSettings>) -> some View {
        Section {
            Toggle("启用本地记忆", isOn: settings.memoryEnabled)
            Toggle("后台自动整理记忆", isOn: settings.backgroundMemoryReview)
            Toggle("长对话自动摘要", isOn: settings.autoSummarizeEnabled)
            Toggle("端侧回复建议", isOn: settings.suggestionsEnabled)
            Toggle("锁屏实时活动", isOn: settings.liveActivitiesEnabled)

            Picker("对话保留", selection: settings.retention) {
                ForEach(RetentionPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }

            Button {
                showDataFlow = true
            } label: {
                HStack {
                    Text("数据流向")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }

            Button {
                showMemoryBrowser = true
            } label: {
                HStack {
                    Text("记忆浏览器")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }

            Button {
                if let url = MemoryExporter.exportMemories(context: modelContext) {
                    exportURL = url
                    presentShareSheet([url])
                } else {
                    validationMessage = "导出失败，请稍后再试。"
                }
            } label: {
                Text("导出记忆为 JSON")
            }

            Button("清空全部记忆", role: .destructive) { confirmClearMemories = true }
            Button("删除全部对话", role: .destructive) { confirmClearConversations = true }
        } header: {
            Text("数据与隐私")
        } footer: {
            Text("向量检索、记忆存储、意图识别、语音处理全部在本机完成。只有对话内容会发送到你配置的云端接口。")
        }
    }

    // MARK: - 用量

    private var extensionsSection: some View {
        Section {
            Button {
                showSkillManager = true
            } label: {
                extensionRow(title: "技能管理", icon: "wand.and.stars", tint: AppColor.brandPurple)
            }

            Button {
                showAgentManager = true
            } label: {
                extensionRow(title: "智能体管理", icon: "person.2.badge.gearshape", tint: AppColor.brandIndigo)
            }

            Button {
                showMCPServers = true
            } label: {
                extensionRow(title: "MCP 服务器", icon: "point.3.connected.trianglepath.dotted", tint: AppColor.brandTeal)
            }
        } header: {
            Text("扩展")
        } footer: {
            Text("MCP 工具的返回值默认只在本机使用，需要为每台服务器单独授权后才会随对话发送到云端。")
        }
    }

    private func extensionRow(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint.opacity(0.12)))
            Text(title)
                .foregroundStyle(AppColor.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.tertiaryText)
        }
    }

    private var usageSection: some View {
        Section {
            let usage = totalUsage
            HStack {
                Text("累计输入 tokens")
                Spacer()
                Text("\(usage.promptTokens)").foregroundStyle(AppColor.secondaryText)
            }
            HStack {
                Text("累计输出 tokens")
                Spacer()
                Text("\(usage.completionTokens + usage.reasoningTokens)")
                    .foregroundStyle(AppColor.secondaryText)
            }
            HStack {
                Text("对话数量")
                Spacer()
                Text("\(list.conversations.count)").foregroundStyle(AppColor.secondaryText)
            }
        } header: {
            Text("用量统计")
        } footer: {
            Text("统计仅基于本机记录，可能与服务商账单存在差异。")
        }
    }

    private var totalUsage: TokenUsage {
        list.conversations.reduce(TokenUsage.zero) { $0 + $1.totalUsage }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text(versionString).foregroundStyle(AppColor.secondaryText)
            }
            Link(destination: URL(string: "https://github.com/zxl1828/deepseek-ios")!) {
                Text("GitHub 仓库")
            }
        } header: {
            Text("关于")
        } footer: {
            Text("本地优先的 DeepSeek 客户端。界面、交互与数据策略均以你的设备为中心设计。")
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: - 行为

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

    private func clearMemories() {
        let descriptor = FetchDescriptor<MemoryEntry>()
        if let entries = try? modelContext.fetch(descriptor) {
            for entry in entries { modelContext.delete(entry) }
            try? modelContext.save()
        }
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
