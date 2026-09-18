import Foundation

// MARK: - 后端选择

/// 联网搜索的几种接法，默认用内置抓取，纯手机零配置可用。
enum WebSearchBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 直接请求搜索引擎的结果页，不需要任何 Key 或服务器。
    case builtIn
    /// 自建服务（例如局域网里跑的 Python 版搜索服务）。
    case customEndpoint
    /// 博查，国内可直连。
    case bocha
    case tavily
    case brave

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn: return "内置抓取"
        case .customEndpoint: return "自建服务"
        case .bocha: return "博查"
        case .tavily: return "Tavily"
        case .brave: return "Brave"
        }
    }

    var detail: String {
        switch self {
        case .builtIn:
            return "直接请求搜索引擎结果页，不需要 Key 也不需要电脑。手机能上网就能用，缺点是页面改版后可能失效。"
        case .customEndpoint:
            return "填一个自建搜索服务的地址（例如电脑上跑的本地服务），手机和它在同一网络即可。"
        case .bocha:
            return "国内直连的搜索 API，中文结果好。需要在博查官网申请 API Key。"
        case .tavily:
            return "面向 AI 的搜索 API，返回内容直接可用。免费额度每月 1000 次，国内访问可能需要代理。"
        case .brave:
            return "Brave 搜索 API，每月赠送 5 美元额度。国内访问可能需要代理。"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .builtIn, .customEndpoint: return false
        case .bocha, .tavily, .brave: return true
        }
    }

    var requiresEndpoint: Bool { self == .customEndpoint }
}

/// 联网搜索配置（不含密钥；密钥单独存钥匙串）。
struct WebSearchConfiguration: Codable, Sendable, Equatable {
    var isEnabled: Bool = true
    var backend: WebSearchBackend = .builtIn
    var customEndpoint: String = ""
    var resultCount: Int = 6
    /// 让模型在回答里标注来源编号。
    var citeSources: Bool = true
}

// MARK: - 结果

struct WebSearchResult: Sendable, Equatable, Identifiable {
    var title: String
    var url: String
    var snippet: String
    var source: String

    var id: String { url.isEmpty ? title : url }
}

enum WebSearchError: LocalizedError, Sendable, Equatable {
    case disabled
    case emptyQuery
    case missingEndpoint
    case missingAPIKey(String)
    case http(status: Int, message: String)
    case parsing(String)
    case allSourcesFailed([String])
    case network(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "联网搜索已在设置里关闭。"
        case .emptyQuery:
            return "搜索词为空。"
        case .missingEndpoint:
            return "还没有填写自建搜索服务的地址。"
        case .missingAPIKey(let backend):
            return "\(backend) 还没有配置 API Key。"
        case .http(let status, let message):
            return "搜索接口返回 \(status)：\(message)"
        case .parsing(let message):
            return "搜索结果解析失败：\(message)"
        case .allSourcesFailed(let reasons):
            return "所有搜索源都不可用（\(reasons.joined(separator: "；"))）。如果手机当前网络访问不了搜索引擎，可以改用 API Key 或自建服务。"
        case .network(let message):
            return "网络连接失败：\(message)"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .network, .http, .allSourcesFailed: return true
        default: return false
        }
    }
}

// MARK: - 搜索服务

/// 统一的联网搜索入口。上层只调用 `search`，不用关心用的是哪种后端。
enum WebSearchService {

    private static var session: URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    // MARK: 对外入口

    static func search(
        query: String,
        configuration: WebSearchConfiguration,
        apiKey: String?
    ) async throws -> [WebSearchResult] {
        guard configuration.isEnabled else { throw WebSearchError.disabled }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WebSearchError.emptyQuery }

        let count = min(max(configuration.resultCount, 1), 20)

        switch configuration.backend {
        case .builtIn:
            return try await builtInSearch(query: trimmed, count: count)
        case .customEndpoint:
            return try await customEndpointSearch(
                query: trimmed,
                count: count,
                endpoint: configuration.customEndpoint
            )
        case .bocha:
            guard let key = apiKey?.nonEmpty else { throw WebSearchError.missingAPIKey("博查") }
            return try await bochaSearch(query: trimmed, count: count, apiKey: key)
        case .tavily:
            guard let key = apiKey?.nonEmpty else { throw WebSearchError.missingAPIKey("Tavily") }
            return try await tavilySearch(query: trimmed, count: count, apiKey: key)
        case .brave:
            guard let key = apiKey?.nonEmpty else { throw WebSearchError.missingAPIKey("Brave") }
            return try await braveSearch(query: trimmed, count: count, apiKey: key)
        }
    }

    /// 整理成给模型看的文本，带编号方便引用。
    static func formatForModel(_ results: [WebSearchResult], query: String, cite: Bool) -> String {
        guard !results.isEmpty else { return "没有搜到与「\(query)」相关的结果。" }

        var lines: [String] = ["以下是「\(query)」的联网搜索结果（共 \(results.count) 条）："]
        for (index, result) in results.enumerated() {
            lines.append("")
            lines.append("[\(index + 1)] \(result.title)")
            if !result.url.isEmpty { lines.append(result.url) }
            if !result.snippet.isEmpty { lines.append(result.snippet) }
        }
        lines.append("")
        lines.append(
            cite
                ? "请基于以上结果回答。引用具体信息时用 [1]、[2] 这样的编号标注来源；结果不足以回答时明确说明。"
                : "请基于以上结果回答；结果不足以回答时明确说明。"
        )
        return lines.joined(separator: "\n")
    }

    // MARK: 内置抓取（零配置）

    private static func builtInSearch(query: String, count: Int) async throws -> [WebSearchResult] {
        var failures: [String] = []

        do {
            let results = try await bingRSSSearch(query: query, count: count)
            if !results.isEmpty { return results }
            failures.append("Bing 没有返回结果")
        } catch {
            failures.append("Bing：\(error.localizedDescription)")
        }

        do {
            let results = try await duckDuckGoSearch(query: query, count: count)
            if !results.isEmpty { return results }
            failures.append("DuckDuckGo 没有返回结果")
        } catch {
            failures.append("DuckDuckGo：\(error.localizedDescription)")
        }

        throw WebSearchError.allSourcesFailed(failures)
    }

    /// Bing 的 RSS 输出，结构稳定，国内可直连。
    private static func bingRSSSearch(query: String, count: Int) async throws -> [WebSearchResult] {
        var components = URLComponents(string: "https://cn.bing.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "rss"),
            URLQueryItem(name: "count", value: "\(max(count, 10))")
        ]
        guard let url = components?.url else { throw WebSearchError.parsing("URL 构造失败") }

        let data = try await fetch(url)
        let parser = BingRSSParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else {
            throw WebSearchError.parsing(xml.parserError?.localizedDescription ?? "XML 解析失败")
        }

        return parser.items.prefix(count).map { item in
            WebSearchResult(
                title: item.title,
                url: item.link,
                snippet: item.summary,
                source: "Bing"
            )
        }
    }

    /// DuckDuckGo 的无脚本页面，作为备选源。
    private static func duckDuckGoSearch(query: String, count: Int) async throws -> [WebSearchResult] {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { throw WebSearchError.parsing("URL 构造失败") }

        let data = try await fetch(url)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw WebSearchError.parsing("页面解码失败")
        }

        let linkPattern = try NSRegularExpression(
            pattern: #"<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>(.*?)</a>"#,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )
        let snippetPattern = try NSRegularExpression(
            pattern: #"<a[^>]+class="result__snippet"[^>]*>(.*?)</a>"#,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )

        let nsHTML = html as NSString
        let links = linkPattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        let snippets = snippetPattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        var results: [WebSearchResult] = []
        for (index, match) in links.enumerated() where results.count < count {
            let rawHref = nsHTML.substring(with: match.range(at: 1))
            let title = Self.plainText(nsHTML.substring(with: match.range(at: 2)))
            let snippet = index < snippets.count
                ? Self.plainText(nsHTML.substring(with: snippets[index].range(at: 1)))
                : ""
            let url = Self.unwrapDuckDuckGo(rawHref)
            guard !title.isEmpty, !url.isEmpty else { continue }
            results.append(
                WebSearchResult(title: title, url: url, snippet: snippet, source: "DuckDuckGo")
            )
        }
        return results
    }

    // MARK: 自建服务

    private static func customEndpointSearch(
        query: String,
        count: Int,
        endpoint: String
    ) async throws -> [WebSearchResult] {
        guard let base = endpoint.nonEmpty else { throw WebSearchError.missingEndpoint }
        var trimmed = base
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.hasSuffix("/search") { trimmed.removeLast("/search".count) }
        guard var components = URLComponents(string: trimmed + "/search") else {
            throw WebSearchError.missingEndpoint
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "\(count)")
        ]
        guard let url = components.url else { throw WebSearchError.missingEndpoint }

        let data = try await fetch(url)
        return try parseGenericJSON(data, fallbackSource: "自建服务").prefix(count).map { $0 }
    }

    // MARK: 第三方 API

    private static func bochaSearch(query: String, count: Int, apiKey: String) async throws -> [WebSearchResult] {
        guard let url = URL(string: "https://api.bochaai.com/v1/web-search") else {
            throw WebSearchError.parsing("URL 构造失败")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "count": count,
            "summary": true
        ])

        let data = try await fetch(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebSearchError.parsing("返回内容不是 JSON")
        }
        let pages = ((root["data"] as? [String: Any])?["webPages"] as? [String: Any])?["value"] as? [[String: Any]]
        guard let pages else { throw WebSearchError.parsing("没有找到 webPages 字段") }

        return pages.prefix(count).compactMap { page in
            guard let name = page["name"] as? String, let url = page["url"] as? String else { return nil }
            let snippet = (page["summary"] as? String) ?? (page["snippet"] as? String) ?? ""
            return WebSearchResult(title: name, url: url, snippet: snippet, source: "博查")
        }
    }

    private static func tavilySearch(query: String, count: Int, apiKey: String) async throws -> [WebSearchResult] {
        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw WebSearchError.parsing("URL 构造失败")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "api_key": apiKey,
            "query": query,
            "max_results": count,
            "include_answer": false,
            "search_depth": "basic"
        ])

        let data = try await fetch(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["results"] as? [[String: Any]] else {
            throw WebSearchError.parsing("返回结构不符合预期")
        }

        return items.prefix(count).compactMap { item in
            guard let title = item["title"] as? String, let url = item["url"] as? String else { return nil }
            return WebSearchResult(
                title: title,
                url: url,
                snippet: (item["content"] as? String) ?? "",
                source: "Tavily"
            )
        }
    }

    private static func braveSearch(query: String, count: Int, apiKey: String) async throws -> [WebSearchResult] {
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "\(count)")
        ]
        guard let url = components?.url else { throw WebSearchError.parsing("URL 构造失败") }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")

        let data = try await fetch(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = root["web"] as? [String: Any],
              let items = web["results"] as? [[String: Any]] else {
            throw WebSearchError.parsing("返回结构不符合预期")
        }

        return items.prefix(count).compactMap { item in
            guard let title = item["title"] as? String, let url = item["url"] as? String else { return nil }
            return WebSearchResult(
                title: Self.plainText(title),
                url: url,
                snippet: Self.plainText((item["description"] as? String) ?? ""),
                source: "Brave"
            )
        }
    }

    // MARK: 通用工具

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        return try await fetch(request)
    }

    private static func fetch(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let message = String(data: data.prefix(200), encoding: .utf8) ?? ""
                throw WebSearchError.http(status: http.statusCode, message: message)
            }
            return data
        } catch let error as WebSearchError {
            throw error
        } catch {
            throw WebSearchError.network(error.localizedDescription)
        }
    }

    /// 兼容自建服务的返回格式：数组或 {results: []}。
    private static func parseGenericJSON(_ data: Data, fallbackSource: String) throws -> [WebSearchResult] {
        let object = try? JSONSerialization.jsonObject(with: data)
        let items: [[String: Any]]

        if let array = object as? [[String: Any]] {
            items = array
        } else if let root = object as? [String: Any], let list = root["results"] as? [[String: Any]] {
            items = list
        } else {
            throw WebSearchError.parsing("返回结构不符合预期")
        }

        return items.compactMap { item in
            let title = (item["title"] as? String) ?? (item["name"] as? String) ?? ""
            let url = (item["url"] as? String) ?? (item["link"] as? String) ?? ""
            let snippet = (item["snippet"] as? String)
                ?? (item["description"] as? String)
                ?? (item["content"] as? String)
                ?? ""
            guard !title.isEmpty || !url.isEmpty else { return nil }
            return WebSearchResult(
                title: Self.plainText(title),
                url: url,
                snippet: Self.plainText(snippet),
                source: (item["source"] as? String) ?? fallbackSource
            )
        }
    }

    private static func unwrapDuckDuckGo(_ href: String) -> String {
        var value = href
        if value.hasPrefix("//") { value = "https:" + value }
        guard let components = URLComponents(string: value),
              let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value else {
            return value
        }
        return target
    }

    private static func plainText(_ raw: String) -> String {
        let withoutTags = raw.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        let decoded = withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return decoded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    /// 去掉空白后的值；全空白时返回 nil。
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Bing RSS 解析

private final class BingRSSParser: NSObject, XMLParserDelegate {

    struct Item {
        var title: String
        var link: String
        var summary: String
    }

    private(set) var items: [Item] = []

    private var isInsideItem = false
    private var currentElement = ""
    private var title = ""
    private var link = ""
    private var summary = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "item" {
            isInsideItem = true
            title = ""
            link = ""
            summary = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }
        switch currentElement {
        case "title": title += string
        case "link": link += string
        case "description": summary += string
        default: break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "item" {
            let cleanTitle = Self.clean(title)
            let cleanLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTitle.isEmpty, !cleanLink.isEmpty {
                items.append(Item(title: cleanTitle, link: cleanLink, summary: Self.clean(summary)))
            }
            isInsideItem = false
        }
        currentElement = ""
    }

    private static func clean(_ raw: String) -> String {
        let withoutTags = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
