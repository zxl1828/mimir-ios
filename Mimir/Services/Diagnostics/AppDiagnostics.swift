import Foundation
import UIKit

/// 轻量诊断记录：关键步骤写进沙盒文件，崩溃时留下原因。
///
/// 语音模式闪退这类问题（AVAudioEngine 抛的是 ObjC 异常）没法 try/catch，
/// 装上 `NSSetUncaughtExceptionHandler` 后，下次启动就能读到异常名 + 原因 + 崩溃栈。
final class AppDiagnostics: @unchecked Sendable {

    static let shared = AppDiagnostics()

    private let lock = NSLock()
    private let logURL: URL
    private let crashURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        logURL = directory.appendingPathComponent("mimir-steps.log")
        crashURL = directory.appendingPathComponent("mimir-last-crash.txt")
    }

    /// App 启动时调用一次。
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            AppDiagnostics.shared.recordCrash(
                name: exception.name.rawValue,
                reason: exception.reason ?? "(没有原因)",
                stack: exception.callStackSymbols.joined(separator: "\n")
            )
        }
        AppDiagnostics.shared.log("app: launch")
    }

    /// 记录一步操作（同步写盘，崩溃前的最后一行一定在文件里）。
    func log(_ step: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "[\(Self.stamp())] \(step)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    func recordCrash(name: String, reason: String, stack: String) {
        lock.lock()
        defer { lock.unlock() }
        let text = """
        时间：\(Self.stamp())
        异常：\(name)
        原因：\(reason)
        最近步骤：
        \(recentLogTail(60))
        崩溃栈：
        \(stack)
        """
        try? text.write(to: crashURL, atomically: true, encoding: .utf8)
    }

    /// 最近一次崩溃内容；没有崩溃返回 nil。
    func lastCrash() -> String? {
        guard let text = try? String(contentsOf: crashURL, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    func clearCrash() {
        try? FileManager.default.removeItem(at: crashURL)
    }

    /// 最近的步骤日志（默认最后 120 行）。
    func logTail(_ lines: Int = 120) -> String {
        recentLogTail(lines)
    }

    private func recentLogTail(_ lines: Int) -> String {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return "(暂无日志)" }
        return text.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
