import SwiftUI
import UIKit

/// 诊断面板：显示最近一次崩溃与最近步骤日志，可一键复制。
struct DiagnosticsView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var crash: String?
    @State private var log: String = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section("最近一次崩溃") {
                    if let crash {
                        Text(crash)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                        Button("清除崩溃记录", role: .destructive) {
                            AppDiagnostics.shared.clearCrash()
                            self.crash = AppDiagnostics.shared.lastCrash()
                        }
                    } else {
                        Text("还没有捕获到崩溃")
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }

                Section("步骤日志（最后 120 行）") {
                    Text(log.isEmpty ? "(暂无日志)" : log)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copied ? "已复制" : "复制全部") {
                        UIPasteboard.general.string = """
                        == 崩溃 ==
                        \(crash ?? "(无)")

                        == 日志 ==
                        \(log)
                        """
                        copied = true
                    }
                }
            }
            .task {
                crash = AppDiagnostics.shared.lastCrash()
                log = AppDiagnostics.shared.logTail(120)
            }
        }
    }
}
