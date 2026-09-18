import SwiftUI
import SwiftData

/// 数据流向面板：把“什么留在本机、什么会发出去”讲清楚。
struct DataFlowPanelView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Query private var memories: [MemoryEntry]
    @Query private var conversations: [Conversation]

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    localSection
                    cloudSection
                    controlSection(settings: $settings)
                    footnote
                }
                .padding(18)
            }
            .background(AppColor.canvas)
            .navigationTitle("数据流向")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(AppColor.brandTeal)
                Text("本地优先")
                    .font(.system(size: 16, weight: .semibold))
            }
            Text("本机保存 \(conversations.count) 段对话、\(memories.count) 条记忆。除对话内容外，没有任何数据会离开这台设备。")
                .font(AppFont.hint)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 18)
        .glassHairline(cornerRadius: 18)
    }

    private var localSection: some View {
        group(
            title: "只在本机完成",
            tint: AppColor.brandTeal,
            items: [
                ("waveform", "语音识别", "音频流只在设备内处理，不写入文件、不上传"),
                ("speaker.wave.2.fill", "语音合成", "内置模型在本机合成语音"),
                ("brain.head.profile", "记忆与向量检索", "嵌入计算与检索全部离线"),
                ("sparkle.magnifyingglass", "意图识别与技能推荐", "关键词匹配与端侧语义分类"),
                ("doc.text.viewfinder", "OCR 与条码识别", "图片在本机解析"),
                ("text.bubble", "回复建议与输入预测", "端侧模型生成")
            ]
        )
    }

    private var cloudSection: some View {
        group(
            title: "会发送到云端接口",
            tint: AppColor.brandIndigo,
            items: [
                ("bubble.left.and.bubble.right", "对话文本", "你发送的消息与必要的上下文"),
                ("photo", "你附加的图片", "仅在提问包含图片时发送"),
                ("memory", "非“仅本地”的记忆", "作为背景参考随请求发送，可在记忆里逐条关闭"),
                ("wrench.and.screwdriver", "你授权的 MCP 工具数据", "默认不发送，需为该工具单独开启")
            ]
        )
    }

    private func controlSection(settings: Bindable<AppSettings>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("控制开关")
                .font(AppFont.sidebarSection)
                .foregroundStyle(AppColor.secondaryText)

            Toggle("记忆随对话发送", isOn: settings.memoryEnabled)
            Toggle("允许云端语音识别回退", isOn: settings.voice.allowsCloudSTTFallback)

            Text("云回退默认关闭。打开后，音频会上传到云端识别，用于系统离线识别不可用的设备。")
                .font(AppFont.chipCompact)
                .foregroundStyle(AppColor.tertiaryText)
        }
        .padding(16)
        .liquidGlassClear(cornerRadius: 18)
    }

    private var footnote: some View {
        Text("MCP 工具的数据可上传开关位于每个工具的配置里，默认关闭。任何数据都不会被用于训练。")
            .font(AppFont.chipCompact)
            .foregroundStyle(AppColor.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func group(
        title: String,
        tint: Color,
        items: [(String, String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title)
                    .font(AppFont.sidebarSection)
                    .foregroundStyle(AppColor.secondaryText)
            }

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: item.0)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(tint.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.1)
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(AppColor.primaryText)
                        Text(item.2)
                            .font(AppFont.chipCompact)
                            .foregroundStyle(AppColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassClear(cornerRadius: 18)
    }
}
