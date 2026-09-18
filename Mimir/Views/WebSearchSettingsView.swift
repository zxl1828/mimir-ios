import SwiftUI
import UIKit

/// 联网搜索配置：选后端、填凭据、当场测一次。
struct WebSearchSettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyDraft: String = ""
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var showsKey = false
    @State private var testQuery = ""

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Toggle("启用联网搜索", isOn: $settings.webSearch.isEnabled)
                    Picker("搜索后端", selection: $settings.webSearch.backend) {
                        ForEach(WebSearchBackend.allCases) { backend in
                            Text(backend.title).tag(backend)
                        }
                    }
                } header: {
                    Text("开关")
                } footer: {
                    Text(settings.webSearch.backend.detail)
                }

                if settings.webSearch.backend.requiresEndpoint {
                    Section {
                        TextField("http://192.168.0.105:8848", text: $settings.webSearch.customEndpoint)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(AppFont.codeSmall)
                    } header: {
                        Text("服务地址")
                    } footer: {
                        Text("填到端口即可，App 会自动拼接 /search?q=。服务需返回 {\"results\":[{\"title\",\"url\",\"snippet\"}]} 形式的 JSON。")
                    }
                }

                if settings.webSearch.backend.requiresAPIKey {
                    Section {
                        HStack(spacing: 10) {
                            Group {
                                if showsKey {
                                    TextField("API Key", text: $apiKeyDraft)
                                } else {
                                    SecureField("API Key", text: $apiKeyDraft)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(AppFont.codeSmall)

                            Button {
                                Haptics.impact(.light)
                                showsKey.toggle()
                            } label: {
                                Image(systemName: showsKey ? "eye.slash" : "eye")
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }

                        Button("保存 Key 到钥匙串") {
                            do {
                                try settings.storeWebSearchKey(apiKeyDraft)
                                testMessage = "已保存。"
                                testSucceeded = true
                                Haptics.notify(.success)
                            } catch {
                                testMessage = error.localizedDescription
                                testSucceeded = false
                                Haptics.notify(.error)
                            }
                        }
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: {
                        Text("凭据")
                    } footer: {
                        Text("Key 只保存在本机钥匙串里，不会随代码或对话外发。")
                    }
                }

                Section("行为") {
                    Stepper(
                        "每次返回 \(settings.webSearch.resultCount) 条结果",
                        value: $settings.webSearch.resultCount,
                        in: 3...15
                    )
                    Toggle("要求模型标注来源编号", isOn: $settings.webSearch.citeSources)
                }

                Section {
                    TextField("测试用的搜索词（留空则用默认）", text: $testQuery)

                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            Text(isTesting ? "正在搜索…" : "测试一下")
                            Spacer()
                            if isTesting { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isTesting)

                    if let testMessage {
                        Text(testMessage)
                            .font(AppFont.hint)
                            .foregroundStyle(testSucceeded ? AppColor.success : AppColor.danger)
                    }
                } header: {
                    Text("验证")
                } footer: {
                    Text("测试会在本机发起一次真实搜索，用来确认当前网络和后端配置能不能用。")
                }
            }
            .navigationTitle("联网搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                apiKeyDraft = settings.resolvedWebSearchKey ?? ""
            }
        }
    }

    private func runTest() async {
        isTesting = true
        testMessage = nil
        defer { isTesting = false }

        let query = testQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = query.isEmpty ? "Mimir 本地优先 AI 客户端" : query

        do {
            let results = try await WebSearchService.search(
                query: effective,
                configuration: settings.webSearch,
                apiKey: settings.resolvedWebSearchKey
            )
            let first = results.first?.title ?? ""
            testMessage = "成功，返回 \(results.count) 条结果：\(first)"
            testSucceeded = true
            Haptics.notify(.success)
        } catch {
            testMessage = error.localizedDescription
            testSucceeded = false
            Haptics.notify(.error)
        }
    }
}
