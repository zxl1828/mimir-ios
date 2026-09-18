import Foundation

/// 本地系统工具的注册表。
///
/// 这些工具完全在本机执行，模型只负责决定“要不要用”，
/// 因此不涉及任何数据外发。
enum SystemToolRegistry {

    static let ocrToolName = "ocr_extract_text"
    static let barcodeToolName = "barcode_scan"
    static let spotlightToolName = "spotlight_search"
    static let webSearchToolName = "web_search"

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
            ),
            LLMToolDefinition(
                name: webSearchToolName,
                description: """
                联网搜索最新信息。当问题涉及时效性内容（新闻、价格、版本号、近期事件、\
                你不确定或可能过时的事实时）主动调用。返回结果带有来源编号，回答时请标注引用。
                """,
                parametersJSON: """
                {"type":"object","properties":{"query":{"type":"string","description":"搜索关键词，尽量具体"}},"required":["query"]}
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

        case webSearchToolName:
            let query = (Self.stringArgument("query", in: argumentsJSON) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return "没有提供搜索关键词。" }

            let settings = AppSettings()
            guard settings.webSearch.isEnabled else {
                return "用户关闭了联网搜索，无法查询实时信息。请基于已有知识回答，并说明这一点。"
            }
            do {
                let results = try await WebSearchService.search(
                    query: query,
                    configuration: settings.webSearch,
                    apiKey: settings.resolvedWebSearchKey
                )
                return WebSearchService.formatForModel(
                    results,
                    query: query,
                    cite: settings.webSearch.citeSources
                )
            } catch {
                return "联网搜索失败：\(error.localizedDescription)"
            }

        default:
            return "未知的本地工具：\(name)"
        }
    }

    static func isLocalTool(_ name: String) -> Bool {
        name == ocrToolName
            || name == barcodeToolName
            || name == spotlightToolName
            || name == webSearchToolName
    }

    private static func stringArgument(_ key: String, in json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object[key] as? String
    }
}
