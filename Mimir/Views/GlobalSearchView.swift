import SwiftUI
import SwiftData

/// 全局搜索页：跨会话检索标题、正文、推理过程与智能体 / 技能标签，
/// 点击结果跳回对应对话并定位到命中的那条消息。
struct GlobalSearchView: View {

    var onOpen: (UUID, UUID?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model: GlobalSearchViewModel?
    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                filters
                content
            }
            .background(AppColor.canvas)
            .navigationTitle("全局搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                if model == nil {
                    let viewModel = GlobalSearchViewModel(modelContext: modelContext)
                    viewModel.updateQuery(query)
                    model = viewModel
                }
                fieldFocused = true
            }
        }
    }

    // MARK: - 搜索框

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColor.tertiaryText)

            TextField("搜索全部对话内容", text: $query)
                .textFieldStyle(.plain)
                .font(AppFont.sidebarRow)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newValue in
                    model?.updateQuery(newValue)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    model?.updateQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AppColor.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索词")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassClear(cornerRadius: 14)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - 过滤条件

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GlobalSearchScope.allCases) { scope in
                    chip(title: scope.title, isOn: (model?.scope ?? .all) == scope) {
                        model?.scope = scope
                        model?.searchNow()
                    }
                }

                Rectangle()
                    .fill(AppColor.separator.opacity(0.4))
                    .frame(width: 1, height: 18)

                ForEach(GlobalSearchDateFilter.allCases) { filter in
                    chip(title: filter.title, isOn: (model?.dateFilter ?? .any) == filter) {
                        model?.dateFilter = filter
                        model?.searchNow()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.bottom, 10)
    }

    private func chip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selectionChanged()
            action()
        } label: {
            Text(title)
                .font(AppFont.chipCompact)
                .foregroundStyle(isOn ? Color.white : AppColor.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn
                              ? AnyShapeStyle(AppColor.accentGradient)
                              : AnyShapeStyle(AppColor.secondaryText.opacity(0.10)))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 结果

    @ViewBuilder
    private var content: some View {
        if !(model?.hasQuery ?? false) {
            emptyState(
                icon: "magnifyingglass",
                title: "搜索全部对话",
                hint: "标题、正文、推理过程与技能标签都会被检索"
            )
        } else if let results = model?.results, results.isEmpty {
            emptyState(
                icon: "text.magnifyingglass",
                title: "没有找到匹配内容",
                hint: "换个关键词，或放宽时间范围试试"
            )
        } else {
            resultList
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let model {
                    HStack(spacing: 6) {
                        Text("共 \(model.results.count) 条结果 · \(model.conversationHitCount) 个对话")
                            .font(AppFont.chipCompact)
                            .foregroundStyle(AppColor.secondaryText)
                        if model.truncated {
                            Text("（仅显示前 \(model.hitLimit) 条）")
                                .font(AppFont.chipCompact)
                                .foregroundStyle(AppColor.warning)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)

                    ForEach(model.results) { result in
                        Button {
                            Haptics.impact(.light)
                            onOpen(result.conversationID, result.messageID)
                            dismiss()
                        } label: {
                            resultRow(result)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func resultRow(_ result: GlobalSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: iconName(for: result))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(result.matchedInTitle ? AppColor.brandPurple : AppColor.brandIndigo)

                Text(result.conversationTitle)
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)

                Text(result.sourceLabel)
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.tertiaryText)

                Spacer(minLength: 4)

                Text(result.createdAt, format: .dateTime.year().month().day())
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.tertiaryText)
            }

            highlightedText(result.segments)
                .font(AppFont.hint)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 16)
        .glassHairline(cornerRadius: 16)
    }

    private func highlightedText(_ segments: [SearchSnippetSegment]) -> Text {
        segments.reduce(Text("")) { partial, segment in
            let piece = Text(segment.text)
            return partial + (segment.isMatch
                ? piece.foregroundColor(AppColor.brandIndigo).bold()
                : piece.foregroundColor(AppColor.secondaryText))
        }
    }

    private func iconName(for result: GlobalSearchResult) -> String {
        if result.matchedInTitle { return "textformat" }
        switch result.role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        default: return "text.alignleft"
        }
    }

    private func emptyState(icon: String, title: String, hint: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AppColor.brandIndigo.opacity(0.7))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.primaryText)
            Text(hint)
                .font(AppFont.hint)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 60)
    }
}
