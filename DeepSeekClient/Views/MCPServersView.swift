import SwiftUI
import SwiftData
import UIKit

/// MCP 服务器管理：连接状态、工具目录、数据上传授权。
struct MCPServersView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MCPServerConfig.createdAt) private var servers: [MCPServerConfig]

    @State private var draft: MCPServerDraft?
    @State private var notice: String?
    private var manager = MCPClientManager.shared

    var body: some View {
        NavigationStack {
            List {
                if servers.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("还没有配置 MCP 服务器")
                                .font(.system(size: 15, weight: .medium))
                            Text("添加一个 HTTP / SSE 端点后，服务器提供的工具就能在对话里被调用。工具返回的数据默认不会上传到云端，需要你逐台授权。")
                                .font(AppFont.hint)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        .padding(.vertical, 6)
                    }
                }

                ForEach(servers) { server in
                    Section {
                        serverRow(server)
                        toolsList(server)
                    } header: {
                        Text(server.displayName)
                    }
                }
            }
            .navigationTitle("MCP 服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        draft = MCPServerDraft()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加 MCP 服务器")
                }
            }
            .sheet(item: $draft) { value in
                MCPServerEditorView(draft: value)
            }
            .overlay(alignment: .bottom) {
                if let notice {
                    Text(notice)
                        .font(AppFont.chip)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - 行

    private func serverRow(_ server: MCPServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                statusDot(for: server)
                Text(server.endpoint)
                    .font(AppFont.codeSmall)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(statusText(for: server))
                    .font(AppFont.chipCompact)
                    .foregroundStyle(statusColor(for: server))
            }

            HStack(spacing: 8) {
                Toggle("启用", isOn: Binding(
                    get: { server.isEnabled },
                    set: { server.isEnabled = $0; try? modelContext.save() }
                ))
                .labelsHidden()
                Toggle("允许工具数据上传云端", isOn: Binding(
                    get: { server.allowsDataUpload },
                    set: { server.allowsDataUpload = $0; try? modelContext.save() }
                ))
                .labelsHidden()
                Spacer()
            }
            .font(AppFont.chipCompact)

            HStack(spacing: 10) {
                Text(server.allowsDataUpload ? "数据可上传" : "数据仅本机")
                    .font(AppFont.chipCompact)
                    .foregroundStyle(server.allowsDataUpload ? AppColor.warning : AppColor.brandTeal)

                Spacer()

                Button {
                    Task { await toggle(server) }
                } label: {
                    Text(manager.states[server.id]?.isConnected == true ? "断开" : "连接")
                        .font(AppFont.chip)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(AppColor.accentGradient))
                }
                .buttonStyle(.plain)

                Button {
                    draft = MCPServerDraft(server: server)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColor.secondaryText)
                }
                .buttonStyle(.plain)
            }

            if !server.lastError.isEmpty {
                Text(server.lastError)
                    .font(AppFont.chipCompact)
                    .foregroundStyle(AppColor.danger)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                manager.disconnect(id: server.id)
                modelContext.delete(server)
                try? modelContext.save()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func toolsList(_ server: MCPServerConfig) -> some View {
        let tools = manager.toolsByServer[server.id] ?? []
        if tools.isEmpty {
            Text(manager.states[server.id]?.isConnected == true ? "这台服务器没有提供工具" : "连接后这里会列出可用工具")
                .font(AppFont.chipCompact)
                .foregroundStyle(AppColor.tertiaryText)
        } else {
            ForEach(tools) { tool in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColor.brandIndigo)
                        Text(tool.displayName)
                            .font(AppFont.sidebarRow)
                        Spacer()
                        Text(tool.allowsDataUpload ? "可上传" : "仅本机")
                            .font(AppFont.chipCompact)
                            .foregroundStyle(tool.allowsDataUpload ? AppColor.warning : AppColor.brandTeal)
                    }
                    if !tool.summary.isEmpty {
                        Text(tool.summary)
                            .font(AppFont.chipCompact)
                            .foregroundStyle(AppColor.tertiaryText)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func statusDot(for server: MCPServerConfig) -> some View {
        Circle()
            .fill(statusColor(for: server))
            .frame(width: 8, height: 8)
    }

    private func statusColor(for server: MCPServerConfig) -> Color {
        switch manager.states[server.id] ?? .disconnected {
        case .connected: return AppColor.success
        case .connecting: return AppColor.warning
        case .failed: return AppColor.danger
        case .disconnected: return AppColor.tertiaryText
        }
    }

    private func statusText(for server: MCPServerConfig) -> String {
        switch manager.states[server.id] ?? .disconnected {
        case .connected(let count): return "已连接 · \(count) 个工具"
        case .connecting: return "连接中…"
        case .failed: return "连接失败"
        case .disconnected: return "未连接"
        }
    }

    private func toggle(_ server: MCPServerConfig) async {
        Haptics.impact(.light)
        if manager.states[server.id]?.isConnected == true {
            manager.disconnect(id: server.id)
            flash("已断开 \(server.displayName)")
        } else {
            await manager.connect(config: server)
            try? modelContext.save()
            if manager.states[server.id]?.isConnected == true {
                flash("已连接 \(server.displayName)")
            } else {
                flash("连接失败，请检查地址")
            }
        }
    }

    private func flash(_ text: String) {
        withAnimation(AppAnimation.chip) { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(AppAnimation.chip) { notice = nil }
        }
    }
}

// MARK: - 编辑

struct MCPServerDraft: Identifiable {
    var id = UUID()
    var existing: MCPServerConfig?
    var name: String = ""
    var endpoint: String = ""
    var usesStreaming: Bool = true
    var isEnabled: Bool = true
    var allowsDataUpload: Bool = false
    var token: String = ""

    init() {}

    init(server: MCPServerConfig) {
        existing = server
        id = server.id
        name = server.name
        endpoint = server.endpoint
        usesStreaming = server.usesStreaming
        isEnabled = server.isEnabled
        allowsDataUpload = server.allowsDataUpload
        token = KeychainService.shared.string(for: server.keychainAccount) ?? ""
    }
}

struct MCPServerEditorView: View {

    @State var draft: MCPServerDraft

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称（可选）", text: $draft.name)
                    TextField("https://example.com/mcp", text: $draft.endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(AppFont.codeSmall)
                }

                Section {
                    Toggle("使用 SSE 流式传输", isOn: $draft.usesStreaming)
                    Toggle("启用这台服务器", isOn: $draft.isEnabled)
                    SecureField("访问令牌（可选）", text: $draft.token)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("连接")
                }

                Section {
                    Toggle("允许这台服务器的工具数据上传到云端模型", isOn: $draft.allowsDataUpload)
                } footer: {
                    Text("关闭时，这台服务器的工具不会被模型调用，返回的数据也不会离开设备。")
                }
            }
            .navigationTitle(draft.existing == nil ? "添加 MCP 服务器" : "编辑 MCP 服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let endpoint = draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = draft.existing {
            existing.name = draft.name
            existing.endpoint = endpoint
            existing.usesStreaming = draft.usesStreaming
            existing.isEnabled = draft.isEnabled
            existing.allowsDataUpload = draft.allowsDataUpload
            if draft.token.isEmpty {
                try? KeychainService.shared.remove(account: existing.keychainAccount)
            } else {
                try? KeychainService.shared.setString(draft.token, for: existing.keychainAccount)
            }
        } else {
            let config = MCPServerConfig(
                name: draft.name,
                endpoint: endpoint,
                usesStreaming: draft.usesStreaming,
                isEnabled: draft.isEnabled,
                allowsDataUpload: draft.allowsDataUpload
            )
            modelContext.insert(config)
            if !draft.token.isEmpty {
                try? KeychainService.shared.setString(draft.token, for: config.keychainAccount)
            }
        }
        try? modelContext.save()
        Haptics.notify(.success)
        dismiss()
    }
}
