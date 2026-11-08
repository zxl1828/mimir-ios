import SwiftUI
import UIKit

/// 单条消息卡片（Codex 桌面端 Agent Turn 风格，自动适配浅色与深色模式）。
struct MessageBubble: View {

    let message: ChatMessage
    var showsThinkingByDefault: Bool = false
    var isHighlighted: Bool = false
    var onCopy: () -> Void = {}
    var onRegenerate: () -> Void = {}
    var onRegenerateHere: () -> Void = {}
    var onSwitchVersion: (Int) -> Void = { _ in }
    var onQuote: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onOpenMemory: (UUID) -> Void = { _ in }
    var onTapImage: (UIImage) -> Void = { _ in }

    @State private var thinkingExpanded = false
    @State private var showsUsage = false
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(AppSettings.self) private var settings
    /// 单条消息的朗读引擎（懒加载，只在这条气泡里用）。
    @State private var speaker: SystemSpeechEngine?
    @State private var isSpeaking = false
    /// 工具调用遥测（内存态，用于卡片底部的审计胶囊）
    @State private var telemetry = ToolCallTelemetry.shared
    @State private var showTelemetrySheet = false
    @AppStorage("mimir.cost.usdToCNY") private var usdToCNY = 7.2

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 40) }
            content
            if message.role != .user { Spacer(minLength: 18) }
        }
        .padding(.horizontal, 14)
        .onAppear {
            if showsThinkingByDefault && !thinkingExpanded {
                thinkingExpanded = true
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
        .sheet(isPresented: $showTelemetrySheet) {
            ToolCallInspectorSheet(messageID: message.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBubble
        }
    }

    // MARK: - 用户消息

    /// 用户消息：浅灰底圆角块、正文用主色，右下角一个"复制"小图标。
    ///
    /// 和旧版的区别：不再用主题色实心填充白字。实心高饱和气泡是"AI 生成感"最重的
    /// 一处——参照截图里用户气泡几乎是白的，靠明度差而非颜色差来区分角色。
    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if !message.quotedPreview.isEmpty {
                quotedChip
            }

            if let data = message.attachmentData, let image = UIImage(data: data) {
                Button {
                    onTapImage(image)
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(StaticButtonFeedbackStyle())
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .font(AppUI.body)
                    .foregroundStyle(AppUI.label)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(userBubbleFill)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Text(message.createdAt, format: .dateTime.hour().minute())
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppUI.label3)
                Button {
                    UIPasteboard.general.string = message.copyableText
                    Haptics.impact(.light)
                    onCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppUI.label3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制这条消息")
            }
        }
        .contextMenu { menuItems }
    }

    private var userBubbleFill: Color {
        scheme == .dark
            ? Color.white.opacity(0.09)
            : Color(red: 0.945, green: 0.952, blue: 0.970)
    }

    // MARK: - 助手消息

    /// 助手消息：**没有卡片底色**，正文直接排在页面上（与参照截图一致）。
    /// 只有"思考 / 工具 / 状态"这类次要信息才用弱化的折叠行与细状态条。
    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 9) {
            if message.hasVisibleThinking {
                thinkingSection
            }

            if message.isError && !message.errorText.isEmpty {
                statusSlab(
                    message.errorText,
                    icon: "exclamationmark.triangle.fill",
                    tint: Color.orange
                )
            } else if message.text.isEmpty && message.isStreaming {
                HStack(spacing: 9) {
                    MimirMascot(size: 24, mood: .thinking)
                    Text("正在推演生成…")
                        .font(AppUI.footnote)
                        .foregroundStyle(AppUI.label2)
                }
                .padding(.vertical, 2)
            } else {
                MarkdownText(raw: message.renderedText, isStreaming: message.isStreaming)
            }

            if message.isInterrupted {
                statusSlab(
                    "生成已取消",
                    icon: "dot.radiowaves.left.and.right",
                    tint: accent
                )
            }

            if !message.memoryHitIDs.isEmpty {
                memoryChips
            }

            // 本轮真实落过盘时才出现：已编辑 N 个文件 / +新增 / -删除。
            if !message.isStreaming {
                FileEditSummaryCard(runID: message.id)
            }

            if message.versionCount > 1 {
                versionSwitcher
            }

            assistantFooter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent.opacity(0.55), lineWidth: 1.2)
                    .padding(-6)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu { menuItems }
    }

    /// 元数据行：`Agent · N tokens · 工具 N 次 · 时间`，右侧 chevron 打开审计面板。
    private var assistantFooter: some View {
        let counts = telemetry.counts(for: message.id)
        let hasDetail = counts.tools > 0 || counts.accesses > 0
        return HStack(spacing: 5) {
            Button {
                guard hasDetail else { return }
                Haptics.impact(.light)
                showTelemetrySheet = true
            } label: {
                HStack(spacing: 5) {
                    if !message.agentName.isEmpty {
                        Text(message.agentName)
                        Text("·")
                    }
                    if message.usage.total > 0 {
                        Text("\(message.usage.total) tokens")
                        Text("·")
                    }
                    if counts.tools > 0 {
                        Text("\(counts.tools) 次工具调用")
                        Text("·")
                    }
                    Text(message.createdAt, format: .dateTime.hour().minute())
                    if hasDetail {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(AppUI.label3)
                .lineLimit(1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
            speakButton
        }
        .accessibilityElement(children: .contain)
    }

    /// 状态条：浅色圆角底 + 图标 + 一行说明（对照截图的「生成已取消」条）。
    private func statusSlab(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(scheme == .dark ? 0.16 : 0.09))
        )
    }

    /// 悬浮微光液态朗读按钮：用系统原生 `AVSpeechSynthesizer` 念这条回复。
    // MARK: - 工具调用遥测胶囊

    /// 卡片底部的遥测胶囊：`工具调用 · N 次 | 本机数据访问 · M 次`，点击打开审计面板。
    /// 只有真的有记录时才出现，不给普通回复增加噪音。
    @ViewBuilder
    private func telemetryCapsule(for messageID: UUID) -> some View {
        let counts = telemetry.counts(for: messageID)
        if counts.tools > 0 || counts.accesses > 0 {
            Button {
                Haptics.impact(.light)
                showTelemetrySheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("工具调用 · " + String(counts.tools) + "次")
                    Text("|")
                        .foregroundStyle(AppUI.label3)
                    Text("本机数据访问 · " + String(counts.accesses) + "次")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppUI.label3)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppUI.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppUI.separator, lineWidth: 0.6)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看工具调用与数据访问详情")
        }
    }

    private var speakButton: some View {
        Button {
            toggleSpeech()
        } label: {
            Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(AppUI.fill, in: Circle())
                .overlay(Circle().strokeBorder(isSpeaking ? accent : AppUI.separator, lineWidth: isSpeaking ? 1 : 0.6))
                .contentShape(Circle())
        }
        .buttonStyle(StaticButtonFeedbackStyle())
        .accessibilityLabel(isSpeaking ? "停止朗读" : "朗读这条回复")
    }

    @MainActor
    private func toggleSpeech() {
        let engine: SystemSpeechEngine
        if let speaker {
            engine = speaker
        } else {
            let created = SystemSpeechEngine()
            speaker = created
            engine = created
        }
        engine.preferredVoiceIdentifier = settings.voice.systemVoiceIdentifier

        if isSpeaking {
            engine.stop()
            isSpeaking = false
            return
        }

        engine.speak(message.text, rate: settings.voice.speechRate)
        isSpeaking = true
        // 说完自动复位；用轮询而不是代理回调，避免跨隔离域捕获。
        Task {
            while engine.isSpeaking {
                try? await Task.sleep(for: .milliseconds(250))
            }
            isSpeaking = false
        }
    }

    /// 思考折叠行：一行摘要 + chevron。旧版是带紫边与光晕的盒子，视觉噪音太大；
    /// 参照截图里"思考"就是一行灰字 + 右侧箭头。
    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Haptics.selectionChanged()
                withAnimation(AppAnimation.chip) { thinkingExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .medium))
                    Text("思考")
                        .font(.system(size: 12, weight: .medium))
                    Text(thinkingSummary)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(thinkingExpanded ? 90 : 0))
                }
                .foregroundStyle(AppUI.label2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if thinkingExpanded {
                Text(message.thinkingText)
                    .font(.system(size: 12))
                    .foregroundStyle(AppUI.label2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(AppUI.label3.opacity(0.5))
                            .frame(width: 1.5)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 折叠态摘要：把思考正文压成一行，让"它到底在干什么"一眼可见。
    private var thinkingSummary: String {
        let flat = message.thinkingText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if flat.isEmpty {
            return message.isStreaming ? "正在思考…" : ""
        }
        return "· " + String(flat.prefix(40))
    }

    private var errorSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.orange)
            Text(message.errorText)
                .font(AppUI.footnote)
                .foregroundStyle(AppUI.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private var quotedChip: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(accent)
                .frame(width: 2.5, height: 14)
            Text(message.quotedPreview)
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label2)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(AppUI.fill)
        )
    }

    private var memoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.memoryHitIDs, id: \.self) { id in
                    Button {
                        onOpenMemory(id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text("记忆")
                                .font(AppUI.caption)
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(accent.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 多版本切换器：同一位置保留多次生成的回答，横向切换对比。
    private var versionSwitcher: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.selectionChanged()
                onSwitchVersion(message.activeVersionIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(message.activeVersionIndex <= 0)
            .opacity(message.activeVersionIndex <= 0 ? 0.35 : 1)

            Text(message.versionLabel)
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label2)
                .monospacedDigit()

            Button {
                Haptics.selectionChanged()
                onSwitchVersion(message.activeVersionIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(message.activeVersionIndex >= message.versionCount - 1)
            .opacity(message.activeVersionIndex >= message.versionCount - 1 ? 0.35 : 1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(AppUI.label2)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(AppUI.fill)
        )
        .frame(maxWidth: 120, alignment: .leading)
    }

    private func metaRow(isUser: Bool) -> some View {
        HStack(spacing: 8) {
            if message.isInterrupted {
                Text("已打断")
                    .font(AppUI.caption)
                    .foregroundStyle(Color.orange)
            }

            if message.usage.total > 0 {
                Button {
                    showsUsage.toggle()
                } label: {
                    Text(showsUsage
                         ? "输入 \(message.usage.promptTokens) · 输出 \(message.usage.completionTokens + message.usage.reasoningTokens)"
                         : "\(message.usage.total) tokens")
                        .font(AppUI.caption)
                        .foregroundStyle(AppUI.label3)
                }
                .buttonStyle(.plain)
            }

            if let cost = message.estimatedCostUSD {
                Text(String(format: "$%.5f · ¥%.4f", cost, cost * usdToCNY))
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label3)
                    .help("基于 Mimir 内置参考价估算；价格与缓存折扣会因服务商和套餐变化。")
            }

            Text(message.createdAt, format: .dateTime.hour().minute())
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label3)
        }
        .animation(.easeInOut(duration: 0.18), value: showsUsage)
    }

    @ViewBuilder
    private var menuItems: some View {
        Button {
            UIPasteboard.general.string = message.copyableText
            Haptics.impact(.light)
            onCopy()
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }

        Button {
            onQuote()
        } label: {
            Label("引用", systemImage: "quote.opening")
        }

        if message.role == .user {
            Button {
                onEdit()
            } label: {
                Label("编辑并重发", systemImage: "pencil")
            }
        } else {
            Button {
                onRegenerate()
            } label: {
                Label("重新生成", systemImage: "arrow.clockwise")
            }

            Button {
                onRegenerateHere()
            } label: {
                Label("从这里重新生成", systemImage: "arrow.triangle.branch")
            }
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("删除", systemImage: "trash")
        }
    }
}

// MARK: - 工具调用审计面板

/// 点击遥测胶囊后的审计面板：列出这次回答执行过的工具与本机数据访问。
private struct ToolCallInspectorSheet: View {

    let messageID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent
    @State private var telemetry = ToolCallTelemetry.shared

    private var invocations: [ToolCallTelemetry.ToolInvocation] {
        telemetry.invocations(for: messageID)
    }

    private var accesses: [ToolCallTelemetry.LocalDataAccess] {
        telemetry.accesses(for: messageID)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if invocations.isEmpty {
                        Text("这次回答没有调用工具。")
                            .font(AppUI.footnote)
                            .foregroundStyle(AppUI.label2)
                    }
                    ForEach(invocations) { item in
                        toolRow(item)
                    }
                } header: {
                    Text("执行的工具")
                }

                Section {
                    if accesses.isEmpty {
                        Text("这次回答没有读取本机数据。")
                            .font(AppUI.footnote)
                            .foregroundStyle(AppUI.label2)
                    }
                    ForEach(accesses) { item in
                        accessRow(item)
                    }
                } header: {
                    Text("本机数据访问")
                } footer: {
                    Text("记录只保留在本机内存中，退出 App 即清空，不会上传。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("工具调用审计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func toolRow(_ item: ToolCallTelemetry.ToolInvocation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.succeeded == false ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(item.succeeded == false ? Color.red : Color.green)
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(item.statusText)
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label3)
                if let duration = item.duration {
                    Text(String(format: "%.2fs", duration))
                        .font(AppUI.caption)
                        .foregroundStyle(AppUI.label3)
                        .monospacedDigit()
                }
            }
            Text(item.startedAt, format: .dateTime.hour().minute().second())
                .font(AppUI.caption)
                .foregroundStyle(AppUI.label3)
            if !item.argumentsSummary.isEmpty {
                Text("参数：" + item.argumentsSummary)
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label2)
                    .lineLimit(3)
            }
            if !item.resultSummary.isEmpty {
                Text("结果：" + item.resultSummary)
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label3)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }

    private func accessRow(_ item: ToolCallTelemetry.LocalDataAccess) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.framework)
                    .font(.system(size: 13, weight: .semibold))
                Text(item.detail)
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label2)
                Text(item.occurredAt, format: .dateTime.hour().minute().second())
                    .font(AppUI.caption)
                    .foregroundStyle(AppUI.label3)
            }
        }
        .padding(.vertical, 2)
    }
}
