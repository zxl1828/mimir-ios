import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 端侧语言模型的统一入口。
///
/// 全部调用都强制走设备本地模型（不使用任何云端推理路径）；
/// 设备不支持或模型未就绪时返回 nil，调用方自动降级为纯规则实现。
@MainActor
enum OnDeviceLanguageModel {

    /// 设备端模型是否可用。
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// 生成一段文本。
    static func generate(
        prompt: String,
        instructions: String? = nil,
        maxTokens: Int = 320
    ) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                let session = instructions.map { LanguageModelSession(instructions: $0) }
                    ?? LanguageModelSession()
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    /// 分类任务：只取一行标签作为结果。
    static func classify(prompt: String) async -> String? {
        guard let output = await generate(
            prompt: prompt,
            instructions: "你是一个意图分类器，只输出一个标签名，不要输出任何解释或标点。",
            maxTokens: 24
        ) else { return nil }

        let firstLine = output
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        guard let firstLine, !firstLine.isEmpty, firstLine.count <= 32 else { return nil }
        return firstLine
    }

    /// 端侧回复建议：给出 3 个可直接点击的短句。
    static func suggestedReplies(for conversationExcerpt: String) async -> [String] {
        let prompt = """
        下面是对话的最后几轮。请给出 3 个用户接下来最可能想说的短句（每条不超过 18 字），
        每行一条，不要编号，不要引号。

        \(conversationExcerpt)
        """
        guard let output = await generate(prompt: prompt, maxTokens: 120) else { return [] }
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty && $0.count <= 24 }
            .prefix(3)
            .map { $0 }
    }
}
