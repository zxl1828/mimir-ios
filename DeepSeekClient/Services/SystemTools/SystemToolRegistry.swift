import Foundation

/// 本地系统工具的注册表。
///
/// 这些工具完全在本机执行，模型只负责决定“要不要用”，
/// 因此不涉及任何数据外发。
enum SystemToolRegistry {

    static let ocrToolName = "ocr_extract_text"
    static let barcodeToolName = "barcode_scan"
    static let spotlightToolName = "spotlight_search"

    static var definitions: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: ocrToolName,
                description: "识别图片中的文字，返回纯文本。用于读取截图、照片、扫描件里的文字。",
                parametersJSON: """
                {"type":"object","properties":{},"required":[]}
                """
            ),
            LLMToolDefinition(
                name: barcodeToolName,
                description: "识别图片中的条形码与二维码，返回编码内容与类型。",
                parametersJSON: """
                {"type":"object","properties":{},"required":[]}
                """
            ),
            LLMToolDefinition(
                name: spotlightToolName,
                description: "在本机 Spotlight 索引中检索内容，返回标题与摘要。",
                parametersJSON: """
                {"type":"object","properties":{"query":{"type":"string","description":"检索关键词"}},"required":["query"]}
                """
            )
        ]
    }

    /// 执行本地工具。返回给模型的文本结果。
    static func invoke(
        name: String,
        argumentsJSON: String,
        attachedImageData: Data?
    ) async -> String {
        switch name {
        case ocrToolName:
            guard let data = attachedImageData else {
                return "当前消息没有附带图片，无法执行文字识别。"
            }
            do {
                let output = try await OCRTool.recognize(imageData: data)
                return output.fullText
            } catch {
                return "文字识别失败：\(error.localizedDescription)"
            }

        case barcodeToolName:
            guard let data = attachedImageData else {
                return "当前消息没有附带图片，无法执行条码识别。"
            }
            do {
                let codes = try await BarcodeReaderTool.detect(in: data)
                guard !codes.isEmpty else { return "图片里没有检测到条形码或二维码。" }
                return codes
                    .map { "\($0.symbology)：\($0.value)" }
                    .joined(separator: "\n")
            } catch {
                return "条码识别失败：\(error.localizedDescription)"
            }

        case spotlightToolName:
            let query = Self.stringArgument("query", in: argumentsJSON) ?? ""
            let hits = await SpotlightSearchTool.search(query)
            guard !hits.isEmpty else { return "没有在本机索引里找到与“\(query)”相关的内容。" }
            return hits
                .map { "- \($0.title)：\($0.snippet)" }
                .joined(separator: "\n")

        default:
            return "未知的本地工具：\(name)"
        }
    }

    static func isLocalTool(_ name: String) -> Bool {
        name == ocrToolName || name == barcodeToolName || name == spotlightToolName
    }

    private static func stringArgument(_ key: String, in json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object[key] as? String
    }
}
