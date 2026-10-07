import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

/// 工作区文件资产结构模型。
struct WorkspaceFileItem: Identifiable, Hashable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var isDirectory: Bool
    var size: Int64
    var modifiedAt: Date
    var fileExtension: String
    var url: URL?
    var category: AssetCategory

    enum AssetCategory: String, CaseIterable, Identifiable, Sendable {
        case all = "全部"
        case document = "文档"
        case code = "代码"
        case media = "媒体"
        case prompt = "Prompt 模板"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .document: return "doc.text"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .media: return "photo.on.rectangle"
            case .prompt: return "sparkles"
            }
        }
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: modifiedAt, relativeTo: Date())
    }

    var systemIcon: String {
        switch fileExtension.lowercased() {
        case "swift": return "swift"
        case "py", "python": return "terminal"
        case "js", "ts", "html", "css": return "chevron.left.forwardslash.chevron.right"
        case "json", "yml", "yaml": return "curlybraces"
        case "md", "txt", "pdf", "doc", "docx": return "doc.text.fill"
        case "png", "jpg", "jpeg", "webp", "gif": return "photo.fill"
        case "mp3", "wav", "m4a": return "waveform"
        default: return isDirectory ? "folder.fill" : "doc.fill"
        }
    }
}

enum WorkspaceAccessError: LocalizedError, Sendable {
    case noFolder
    case accessDenied
    case invalidPath
    case fileTooLarge
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .noFolder: return "请先选择一个工作区文件夹。"
        case .accessDenied: return "无法访问所选项目。请重新选择文件夹并允许 Mimir 读取。"
        case .invalidPath: return "文件路径超出当前工作区。"
        case .fileTooLarge: return "Agent 目前只读取或修改小于 256 KB 的文本文件。"
        case .unreadableFile: return "无法按 UTF-8 文本读取这个文件。"
        }
    }
}

private enum WorkspaceFileTypes {
    static let editable: Set<String> = [
        "swift", "m", "mm", "h", "hh", "c", "cc", "cpp", "metal",
        "json", "yml", "yaml", "plist", "pbxproj", "xcconfig", "entitlements",
        "strings", "stringsdict", "md", "txt", "sh", "py", "js", "ts", "html", "css"
    ]

    static func category(for name: String, extension ext: String) -> WorkspaceFileItem.AssetCategory {
        if editable.contains(ext) || ["rs", "go", "rb", "kt", "java"].contains(ext) {
            return .code
        }
        if ["png", "jpg", "jpeg", "webp", "gif", "svg", "heic"].contains(ext) {
            return .media
        }
        if name.localizedCaseInsensitiveContains("prompt") || ext == "prompt" {
            return .prompt
        }
        return .document
    }
}

private enum WorkspaceFolderScanner {
    static func scan(_ url: URL) -> [WorkspaceFileItem] {
        let keys: [URLResourceKey] = [
            .nameKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let skippedDirectories: Set<String> = [".git", ".build", "Build", "DerivedData", "node_modules", "Pods", "Carthage"]
        var items: [WorkspaceFileItem] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            let isDirectory = values.isDirectory ?? false
            if isDirectory && skippedDirectories.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard values.isSymbolicLink != true else { continue }

            let name = values.name ?? fileURL.lastPathComponent
            let ext = fileURL.pathExtension.lowercased()
            items.append(WorkspaceFileItem(
                name: name,
                path: fileURL.path,
                isDirectory: isDirectory,
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? Date(),
                fileExtension: ext,
                url: fileURL,
                category: WorkspaceFileTypes.category(for: name, extension: ext)
            ))
        }
        return items
    }
}

/// 工作区与文件服务管理器（支持 Security-Scoped URL 本地安全挂载与读写）。
@MainActor
@Observable
final class WorkspaceManager {

    static let shared = WorkspaceManager()

    var mountedWorkspaces: [URL] = []
    var activeWorkspaceURL: URL?
    var allFiles: [WorkspaceFileItem] = []
    var selectedCategory: WorkspaceFileItem.AssetCategory = .all
    var searchText: String = ""

    /// 当前选中的代码文件（用于代码工坊直接打开编辑与运行）。
    var currentActiveCodeFile: WorkspaceFileItem?
    var currentCodeContent: String = ""

    private let bookmarkStorageKey = "mimir.workspace.bookmarks"
    private var lastSavedCodeContent = ""

    private init() {
        loadBookmarks()
    }

    // MARK: - 过滤文件

    var filteredFiles: [WorkspaceFileItem] {
        allFiles.filter { item in
            let matchesCategory = (selectedCategory == .all) || (item.category == selectedCategory)
            let matchesSearch = searchText.isEmpty
                || item.name.localizedCaseInsensitiveContains(searchText)
                || item.path.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var sourceFiles: [WorkspaceFileItem] {
        guard let root = activeWorkspaceURL?.standardizedFileURL.path else { return [] }
        return allFiles
            .filter { item in
                guard !item.isDirectory, let url = item.url else { return false }
                return url.standardizedFileURL.path.hasPrefix(root + "/")
                    && WorkspaceFileTypes.editable.contains(item.fileExtension)
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: - 挂载本地真实项目/文件夹 (Security-Scoped URL)

    func mountFolder(url: URL) async throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw WorkspaceAccessError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // iOS persists document-picker access in the bookmark itself; .withSecurityScope is macOS-only.
        let bookmarkData = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        saveBookmark(bookmarkData, for: url)
        addFolderURL(url)
        let scannedItems = await Task.detached(priority: .userInitiated) {
            WorkspaceFolderScanner.scan(url)
        }.value
        guard activeWorkspaceURL?.standardizedFileURL == url.standardizedFileURL else { return }
        applyScannedItems(scannedItems)
    }

    private func addFolderURL(_ url: URL) {
        if !mountedWorkspaces.contains(url) {
            mountedWorkspaces.append(url)
        }
        activeWorkspaceURL = url
    }

    /// 扫描挂载目录内容。
    func scanFolder(url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        let scannedItems = await Task.detached(priority: .userInitiated) {
            WorkspaceFolderScanner.scan(url)
        }.value
        guard activeWorkspaceURL?.standardizedFileURL == url.standardizedFileURL else { return }
        applyScannedItems(scannedItems)
    }

    private func applyScannedItems(_ scannedItems: [WorkspaceFileItem]) {
        let selectedPath = currentActiveCodeFile?.url?.standardizedFileURL.path
        let activeRoot = activeWorkspaceURL?.standardizedFileURL.path
        let selectionBelongsToWorkspace = activeRoot.map { root in
            selectedPath?.hasPrefix(root + "/") == true
        } ?? false
        self.allFiles = scannedItems

        if let selectedPath, let refreshed = scannedItems.first(where: { $0.url?.standardizedFileURL.path == selectedPath }) {
            currentActiveCodeFile = refreshed
            if currentCodeContent == lastSavedCodeContent {
                currentCodeContent = readFileContent(for: refreshed)
                lastSavedCodeContent = currentCodeContent
            }
        } else if !selectionBelongsToWorkspace {
            selectCodeFile(scannedItems.first(where: { $0.category == .code && $0.fileExtension == "swift" })
                ?? scannedItems.first(where: { $0.category == .code }))
        }
    }

    func refreshActiveWorkspace() async {
        guard let activeWorkspaceURL else { return }
        await scanFolder(url: activeWorkspaceURL)
    }

    func refreshCurrentCodeFile() {
        guard let file = currentActiveCodeFile,
              let url = file.url,
              let root = activeWorkspaceURL else { return }
        let accessing = root.startAccessingSecurityScopedResource()
        guard accessing else { return }
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate else { return }
        let size = Int64(values.fileSize ?? 0)
        guard size != file.size || modifiedAt != file.modifiedAt else { return }

        var refreshed = file
        refreshed.size = size
        refreshed.modifiedAt = modifiedAt
        currentActiveCodeFile = refreshed
        if let index = allFiles.firstIndex(where: { $0.id == file.id }) {
            allFiles[index] = refreshed
        }
        guard currentCodeContent == lastSavedCodeContent,
              let path = relativePath(for: refreshed),
              let text = try? readWorkspaceText(path: path) else { return }
        currentCodeContent = text
        lastSavedCodeContent = text
    }

    // MARK: - 文件读写（支持直接修改并保存手机上的文件）

    func readFileContent(for item: WorkspaceFileItem) -> String {
        if let url = item.url,
           let root = activeWorkspaceURL,
           root.startAccessingSecurityScopedResource() {
            defer { root.stopAccessingSecurityScopedResource() }
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize,
               size > 256_000 {
                return "// 文件超过 256 KB，当前编辑器不会加载它"
            }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return "// 文件内容为空或二进制不可读"
    }

    func saveFileContent(item: WorkspaceFileItem, newContent: String) throws {
        guard let path = relativePath(for: item) else { throw WorkspaceAccessError.invalidPath }
        try writeWorkspaceText(path: path, content: newContent)
        currentCodeContent = newContent
        lastSavedCodeContent = newContent
    }

    func selectCodeFile(_ item: WorkspaceFileItem?) {
        guard let item else {
            currentActiveCodeFile = nil
            currentCodeContent = ""
            lastSavedCodeContent = ""
            return
        }
        guard item.category == .code, item.url != nil else { return }
        currentActiveCodeFile = item
        currentCodeContent = readFileContent(for: item)
        lastSavedCodeContent = currentCodeContent
    }

    func relativePath(for item: WorkspaceFileItem) -> String? {
        guard let root = activeWorkspaceURL?.standardizedFileURL.path,
              let file = item.url?.standardizedFileURL.path,
              file.hasPrefix(root + "/") else { return nil }
        return String(file.dropFirst(root.count + 1))
    }

    func readWorkspaceText(path: String) throws -> String {
        guard let root = activeWorkspaceURL else { throw WorkspaceAccessError.noFolder }
        let accessing = root.startAccessingSecurityScopedResource()
        guard accessing else { throw WorkspaceAccessError.accessDenied }
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        let url = try validatedWorkspaceURL(path: path)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw WorkspaceAccessError.invalidPath }
        guard (values.fileSize ?? 0) <= 256_000 else { throw WorkspaceAccessError.fileTooLarge }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw WorkspaceAccessError.unreadableFile }
        return text
    }

    func writeWorkspaceText(path: String, content: String) throws {
        guard content.utf8.count <= 256_000 else { throw WorkspaceAccessError.fileTooLarge }
        guard let root = activeWorkspaceURL else { throw WorkspaceAccessError.noFolder }
        let accessing = root.startAccessingSecurityScopedResource()
        guard accessing else { throw WorkspaceAccessError.accessDenied }
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        let url = try validatedWorkspaceURL(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        let updated = WorkspaceFileItem(
            name: url.lastPathComponent,
            path: url.path,
            isDirectory: false,
            size: Int64(content.utf8.count),
            modifiedAt: Date(),
            fileExtension: url.pathExtension.lowercased(),
            url: url,
            category: WorkspaceFileTypes.category(for: url.lastPathComponent, extension: url.pathExtension.lowercased())
        )
        if let index = allFiles.firstIndex(where: { $0.url?.standardizedFileURL == url }) {
            allFiles[index] = updated
        } else {
            allFiles.insert(updated, at: 0)
        }
        currentActiveCodeFile = updated
        currentCodeContent = content
        lastSavedCodeContent = content
    }

    private func validatedWorkspaceURL(path: String) throws -> URL {
        guard let root = activeWorkspaceURL?.standardizedFileURL else { throw WorkspaceAccessError.noFolder }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw WorkspaceAccessError.invalidPath
        }
        let candidate = root.appending(path: path).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"),
              candidate.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
            throw WorkspaceAccessError.invalidPath
        }
        return candidate
    }

    func createNewFile(name: String, content: String, category: WorkspaceFileItem.AssetCategory) -> WorkspaceFileItem {
        let newItem = WorkspaceFileItem(
            name: name,
            path: "/workspace/\(name)",
            isDirectory: false,
            size: Int64(content.utf8.count),
            modifiedAt: Date(),
            fileExtension: (name as NSString).pathExtension,
            url: nil,
            category: category
        )
        allFiles.insert(newItem, at: 0)
        return newItem
    }

    func deleteFile(_ item: WorkspaceFileItem) {
        if let url = item.url {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            try? FileManager.default.removeItem(at: url)
        }
        allFiles.removeAll { $0.id == item.id }
    }

    // MARK: - 书签持久化

    private func saveBookmark(_ data: Data, for url: URL) {
        var dict = UserDefaults.standard.dictionary(forKey: bookmarkStorageKey) as? [String: Data] ?? [:]
        dict[url.path] = data
        UserDefaults.standard.set(dict, forKey: bookmarkStorageKey)
    }

    private func loadBookmarks() {
        guard let dict = UserDefaults.standard.dictionary(forKey: bookmarkStorageKey) as? [String: Data] else { return }
        for (_, data) in dict {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                mountedWorkspaces.append(resolvedURL)
                if activeWorkspaceURL == nil {
                    activeWorkspaceURL = resolvedURL
                    Task { await scanFolder(url: resolvedURL) }
                }
            }
        }
    }

}
