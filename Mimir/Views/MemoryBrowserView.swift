import SwiftUI
import SwiftData
import UIKit

/// 记忆浏览器：查看、搜索、编辑、删除、导出、按时间线回顾。
struct MemoryBrowserView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MemoryEntry.updatedAt, order: .reverse) private var memories: [MemoryEntry]

    @State private var searchText = ""
    @State private var editingEntry: MemoryEntry?
    @State private var showsTimeline = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    emptyState
                } else if showsTimeline {
                    timelineList
                } else {
                    flatList
                }
            }
            .navigationTitle("记忆")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索记忆内容")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        withAnimation(AppAnimation.chip) { showsTimeline.toggle() }
                    } label: {
                        Image(systemName: showsTimeline ? "list.bullet" : "clock.arrow.circlepath")
                    }
                    .accessibilityLabel(showsTimeline ? "切换到列表" : "切换到时间线")

                    Button {
                        exportAll()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("导出记忆")

                    Button {
                        addEntry()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增记忆")
                }
            }
            .sheet(item: $editingEntry) { entry in
                MemoryEditorView(entry: entry)
            }
            .overlay(alignment: .bottom) {
                if let notice {
                    Text(notice)
                        .font(AppFont.chip)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 18)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    // MARK: - 数据

    private var filtered: [MemoryEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return memories }
        return memories.filter {
            $0.text.localizedCaseInsensitiveContains(keyword)
                || $0.summary.localizedCaseInsensitiveContains(keyword)
                || $0.sourceConversationTitle.localizedCaseInsensitiveContains(keyword)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(keyword) }
        }
    }

    private var grouped: [(title: String, entries: [MemoryEntry])] {
        let calendar = Calendar.current
        let now = Date()
        var buckets: [String: [MemoryEntry]] = [:]
        for entry in filtered {
            let key: String
            if calendar.isDateInToday(entry.createdAt) {
                key = "今天"
            } else if calendar.isDate(entry.createdAt, equalTo: now, toGranularity: .weekOfYear) {
                key = "本周"
            } else if calendar.isDate(entry.createdAt, equalTo: now, toGranularity: .month) {
                key = "本月"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy 年 M 月"
                key = formatter.string(from: entry.createdAt)
            }
            buckets[key, default: []].append(entry)
        }
        return buckets
            .map { (title: $0.key, entries: $0.value) }
            .sorted { ($0.entries.first?.createdAt ?? .distantPast) > ($1.entries.first?.createdAt ?? .distantPast) }
    }

    // MARK: - 视图

    private var flatList: some View {
        List {
            ForEach(filtered) { entry in
                row(entry)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
    }

    private var timelineList: some View {
        List {
            ForEach(grouped, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.entries) { entry in
                        row(entry)
                    }
                    .onDelete { offsets in
                        delete(in: group.entries, offsets: offsets)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ entry: MemoryEntry) -> some View {
        Button {
            editingEntry = entry
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if entry.localOnly {
                        tag("仅本地", color: AppColor.brandTeal)
                    }
                    if entry.isUserEdited {
                        tag("已编辑", color: AppColor.brandIndigo)
                    }
                    if !entry.isAutoExtracted {
                        tag("手动", color: AppColor.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Text(entry.updatedAt, format: .dateTime.month().day().hour().minute())
                        .font(AppFont.chipCompact)
                        .foregroundStyle(AppColor.tertiaryText)
                }

                Text(entry.displaySummary)
                    .font(AppFont.sidebarRow)
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10))
                    Text(entry.sourceLabel)
                        .lineLimit(1)
                    if entry.useCount > 0 {
                        Text("· 引用 \(entry.useCount) 次")
                    }
                }
                .font(AppFont.chipCompact)
                .foregroundStyle(AppColor.tertiaryText)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Haptics.impact(.medium)
                modelContext.delete(entry)
                try? modelContext.save()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AppFont.chipCompact)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.13)))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppColor.brandPurple.opacity(0.7))
            Text(memories.isEmpty ? "还没有记忆条目" : "没有匹配的记忆")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.primaryText)
            Text(memories.isEmpty
                 ? "对话中值得长期记住的信息会自动沉淀到这里，你也可以手动添加。"
                 : "换个关键词再试试。")
                .font(AppFont.hint)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 行为

    private func delete(_ offsets: IndexSet) {
        for index in offsets where filtered.indices.contains(index) {
            modelContext.delete(filtered[index])
        }
        try? modelContext.save()
        Haptics.impact(.medium)
    }

    private func delete(in entries: [MemoryEntry], offsets: IndexSet) {
        for index in offsets where entries.indices.contains(index) {
            modelContext.delete(entries[index])
        }
        try? modelContext.save()
        Haptics.impact(.medium)
    }

    private func addEntry() {
        let entry = MemoryEntry(
            text: "",
            summary: "新的记忆条目",
            tags: [],
            isAutoExtracted: false
        )
        modelContext.insert(entry)
        try? modelContext.save()
        editingEntry = entry
        Haptics.impact(.light)
    }

    private func exportAll() {
        guard let url = MemoryExporter.exportMemories(context: modelContext) else {
            flash("导出失败")
            return
        }
        presentShareSheet([url])
    }

    private func flash(_ text: String) {
        withAnimation(AppAnimation.chip) { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(AppAnimation.chip) { notice = nil }
        }
    }
}

// MARK: - 编辑单条记忆

struct MemoryEditorView: View {

    let entry: MemoryEntry

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var summary: String = ""
    @State private var tagsText: String = ""
    @State private var localOnly: Bool = false
    @State private var importance: Double = 0.5

    var body: some View {
        NavigationStack {
            Form {
                Section("摘要") {
                    TextField("一句话概括", text: $summary, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("完整内容") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                }

                Section("标签") {
                    TextField("用逗号分隔", text: $tagsText)
                }

                Section {
                    Toggle("仅本地使用", isOn: $localOnly)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("重要程度")
                            Spacer()
                            Text(String(format: "%.1f", importance))
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        Slider(value: $importance, in: 0...1, step: 0.1)
                    }
                } footer: {
                    Text("标记为“仅本地使用”的记忆不会随对话发送到云端接口。")
                }

                Section("来源") {
                    HStack {
                        Text("对话")
                        Spacer()
                        Text(entry.sourceLabel)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    if !entry.sourceQuote.isEmpty {
                        Text(entry.sourceQuote)
                            .font(AppFont.codeSmall)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    HStack {
                        Text("创建时间")
                        Spacer()
                        Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute())
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    HStack {
                        Text("最后更新")
                        Spacer()
                        Text(entry.updatedAt, format: .dateTime.year().month().day().hour().minute())
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
            }
            .navigationTitle("编辑记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  && summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                text = entry.text
                summary = entry.summary
                tagsText = entry.tags.joined(separator: ", ")
                localOnly = entry.localOnly
                importance = entry.importance
            }
        }
    }

    private func save() {
        entry.text = text
        entry.summary = summary
        entry.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        entry.localOnly = localOnly
        entry.importance = importance
        entry.isUserEdited = true
        entry.updatedAt = Date()
        try? modelContext.save()
        Haptics.notify(.success)
        dismiss()
    }
}
