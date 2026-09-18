import Foundation
import CoreSpotlight

/// Spotlight 检索工具：查询系统索引里已注册的数据。
enum SpotlightSearchTool {

    struct Hit: Sendable, Equatable {
        var title: String
        var snippet: String
        var domain: String
        var identifier: String
    }

    /// 让 App 自己的内容可以被 Spotlight 检索到。
    static func index(
        identifiers: [String],
        titles: [String],
        contents: [String],
        domain: String = "com.zxl.deepseekclient.notes"
    ) async {
        let items: [CSSearchableItem] = zip(identifiers, zip(titles, contents)).map { identifier, pair in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = pair.0
            attributes.contentDescription = pair.1
            return CSSearchableItem(
                uniqueIdentifier: identifier,
                domainIdentifier: domain,
                attributeSet: attributes
            )
        }
        guard !items.isEmpty else { return }
        try? await CSSearchableIndex.default().indexSearchableItems(items)
    }

    static func removeAll(domain: String = "com.zxl.deepseekclient.notes") async {
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
    }

    /// 检索系统索引。
    static func search(_ query: String, limit: Int = 8) async -> [Hit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return await withCheckedContinuation { continuation in
            var hits: [Hit] = []
            let context = CSSearchQueryContext()
            context.fetchAttributes = ["title", "contentDescription", "domainIdentifier"]

            let escaped = trimmed.replacingOccurrences(of: "\"", with: "")
            let searchQuery = CSSearchQuery(
                queryString: "title == \"*\(escaped)*\"c || contentDescription == \"*\(escaped)*\"c",
                context: context
            )

            searchQuery.foundItemsHandler = { items in
                for item in items where hits.count < limit {
                    let attributes = item.attributeSet
                    hits.append(
                        Hit(
                            title: attributes.title ?? "(无标题)",
                            snippet: attributes.contentDescription ?? "",
                            domain: item.domainIdentifier ?? "",
                            identifier: item.uniqueIdentifier
                        )
                    )
                }
            }
            searchQuery.completionHandler = { _ in
                continuation.resume(returning: hits)
            }
            searchQuery.start()
        }
    }
}
