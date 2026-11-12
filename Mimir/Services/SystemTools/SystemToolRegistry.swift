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
    static let planToolName = "update_plan"

    static var definitions: [LLMToolDefinition] {
        localDefinitions + SystemCapabilityGateway.definitions
    }

    private static var localDefinitions: [LLMToolDefinition] {
        [
            LLMToolDefinition(
                name: planToolName,
                description: """
                维护任务面板：把这次要做的事拆成步骤写下来，并在每完成一步后更新状态。
                多步骤任务（改代码、查资料、写长文档）开始时就先调用一次，\
                让用户能一眼看到进度；单步闲聊不要调用。
                """,
                parametersJSON: """
                {"type":"object","properties":{"explanation":{"type":"string","description":"一句话说明当前为什么调整计划"},"plan":{"type":"array","description":"完整计划，每次调用都提交全部步骤","items":{"type":"object","properties":{"step":{"type":"string","description":"一句话描述这一步要做的事"},"status":{"type":"string","enum":["pending","in_progress","completed"]}},"required":["step","status"]}}},"required":["plan"]}
                """
            ),
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
        case planToolName:
            guard let parsed = TaskBoardStore.parse(argumentsJSON: argumentsJSON) else {
                return "计划格式不对：需要一个 plan 数组，每项包含 step 与 status。"
            }
            let stepCount = parsed.steps.count
            let explanation = parsed.explanation
            let line: String = await MainActor.run {
                TaskBoardStore.shared.apply(steps: parsed.steps)
                return TaskBoardStore.shared.summaryLine
            }
            return "任务面板已更新（\(stepCount) 步，\(line)）。"
                + (explanation.isEmpty ? "" : "说明：\(explanation)")

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
            // 系统能力（时间 / 日历 / 提醒 / 通讯录 / 拨号 / 分享 / 定位 / POI / 导出）
            // 由专门的网关处理
            if SystemCapabilityGateway.handles(name) {
                return await SystemCapabilityGateway.invoke(
                    name: name,
                    argumentsJSON: argumentsJSON
                )
            }
            return "未知的本地工具：\(name)"
        }
    }

    static func isLocalTool(_ name: String) -> Bool {
        name == ocrToolName
            || name == barcodeToolName
            || name == spotlightToolName
            || name == webSearchToolName
            || name == planToolName
            || SystemCapabilityGateway.handles(name)
    }

    private static func stringArgument(_ key: String, in json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object[key] as? String
    }
}
