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

/// 挂载状态机。
///
/// 存在的理由：过去用户点完文件夹选择器之后界面毫无反馈——不知道是选择器没回调、
/// 还是安全作用域没拿到、还是扫描到 0 个文件。把状态显式建模出来，UI 才能如实
/// 告诉用户"卡在哪一步"，而不是让按钮看起来像坏了。
enum WorkspaceMountState: Equatable, Sendable {
    case idle
    case mounting(String)
    case mounted(folderName: String, path: String, fileCount: Int, scopeHeld: Bool)
    case failed(String)

    var isBusy: Bool {
        if case .mounting = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .idle: return "未挂载文件夹"
        case .mounting(let text): return text
        case .mounted(let name, _, _, _): return name
        case .failed: return "挂载失败"
        }
    }

    var detail: String {
        switch self {
        case .idle: return "点右上角文件夹按钮，选一个本地项目目录"
        case .mounting: return "正在申请访问权限并扫描文件…"
        case .mounted(_, let path, let count, let held):
            return "\(path) · \(count) 个文件" + (held ? " · 安全作用域已持有" : " · App 沙盒内")
        case .failed(let reason): return reason
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
        case .fileTooLarge: return "文件超过 4 MB，当前编辑器不会加载它。"
        case .unreadableFile: return "这个文件不是可编辑的文本格式。"
        }
    }
}

private enum WorkspaceFileTypes {
    static let maxTextFileBytes: Int64 = 4_000_000

    // Source files are plain text on disk; the extension only controls grouping and the icon.
    static let editable: Set<String> = [
        "swift", "m", "mm", "h", "hh", "hpp", "c", "cc", "cpp", "cxx", "metal",
        "py", "pyw", "pyi", "js", "jsx", "mjs", "cjs", "ts", "tsx", "vue", "svelte",
        "ipynb", "astro", "tf", "tfvars", "hcl", "nix", "scala", "sc", "groovy",
        "clj", "cljs", "cljc", "edn", "pl", "pm", "jl", "hs", "lhs", "elm", "purs",
        "prisma", "thrift", "cue", "awk", "tex", "typ", "gradle.kts", "properties",
        "html", "htm", "css", "scss", "sass", "less", "xml", "xhtml",
        "json", "jsonc", "json5", "yml", "yaml", "toml", "ini", "cfg", "conf",
        "plist", "pbxproj", "xcconfig", "entitlements", "strings", "stringsdict",
        "md", "markdown", "mdx", "txt", "rtf", "rst", "adoc", "log",
        "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd",
        "rs", "go", "rb", "php", "kt", "kts", "java", "gradle", "dart", "ex", "exs",
        "erl", "hrl", "fs", "fsx", "cs", "csx", "sql", "graphql", "gql",
        "proto", "sol", "r", "lua", "nim", "zig", "asm", "s", "make", "cmake"
    ]

    static let knownTextNames: Set<String> = [
        "makefile", "dockerfile", "gemfile", "rakefile", "procfile", "package.swift",
        "package.json", "readme", "license", "changelog", ".gitignore", ".gitattributes",
        ".editorconfig", ".env", ".env.example", "podfile", "cartfile"
    ]

    static func isTextLike(name: String, extension ext: String) -> Bool {
        editable.contains(ext)
            || knownTextNames.contains(name.lowercased())
            || UTType(filenameExtension: ext)?.conforms(to: .sourceCode) == true
    }

    static func isTextFile(at url: URL, size: Int64) -> Bool {
        guard size <= maxTextFileBytes,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let sample = try? handle.read(upToCount: min(Int(size), 8_192)),
              !sample.contains(0) else { return false }
        return sample.isEmpty || String(data: sample, encoding: .utf8) != nil
    }

    static func category(for name: String, extension ext: String, isText: Bool = false) -> WorkspaceFileItem.AssetCategory {
        if name.localizedCaseInsensitiveContains("prompt") || ext == "prompt" {
            return .prompt
        }
        if isText || isTextLike(name: name, extension: ext) {
            return .code
        }
        if ["png", "jpg", "jpeg", "webp", "gif", "svg", "heic"].contains(ext) {
            return .media
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
            // Dotfiles such as .env, .gitignore and .editorconfig are part of a code workspace.
            options: []
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
                category: WorkspaceFileTypes.category(
                    for: name,
                    extension: ext,
                    isText: !isDirectory && WorkspaceFileTypes.isTextFile(at: fileURL, size: Int64(values.fileSize ?? 0))
                )
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

    var isUsingDefaultWorkspace: Bool {
        guard let activeWorkspaceURL else { return true }
        return activeWorkspaceURL.standardizedFileURL == defaultWorkspaceURL.standardizedFileURL
    }

    private let bookmarkStorageKey = "mimir.workspace.bookmarks"
    private var lastSavedCodeContent = ""
    private var workspaceFiles: [WorkspaceFileItem] = []
    private var libraryFiles: [WorkspaceFileItem] = []
    private var libraryRevision = 0
    private var activeSecurityScopedURL: URL?

    /// 当前挂载进度（UI 直接读它，不再靠猜）。
    private(set) var mountState: WorkspaceMountState = .idle

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var defaultWorkspaceURL: URL {
        documentsURL
            .appendingPathComponent("Mimir Workspace", isDirectory: true)
    }

    private var localLibraryURL: URL {
        documentsURL
            .appendingPathComponent("Mimir Library", isDirectory: true)
    }

    private init() {
        try? FileManager.default.createDirectory(at: localLibraryURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: defaultWorkspaceURL, withIntermediateDirectories: true)
        activeWorkspaceURL = defaultWorkspaceURL
        mountedWorkspaces = [defaultWorkspaceURL]
        let libraryURL = localLibraryURL
        Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let revision = self.libraryRevision
                let items = await Task.detached(priority: .utility) {
                    WorkspaceFolderScanner.scan(libraryURL)
                }.value
                guard !Task.isCancelled else { return }
                guard self.libraryRevision == revision else { continue }
                self.libraryFiles = items
                self.rebuildAllFiles()
                return
            }
        }
        Task { await scanFolder(url: defaultWorkspaceURL) }
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
                    && item.category == .code
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: - 挂载本地真实项目/文件夹 (Security-Scoped URL)

    func mountFolder(
        url: URL,
        bookmarkData providedBookmark: Data? = nil,
        securityScopeAlreadyStarted: Bool = false
    ) async throws {
        let folderName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        mountState = .mounting("正在挂载 \(folderName)…")
        let needsSecurityScope = !isInAppDocuments(url)
        let isAlreadyMountedWithScope = activeSecurityScopedURL?.standardizedFileURL == url.standardizedFileURL
        let shouldStartScope = needsSecurityScope && !securityScopeAlreadyStarted && !isAlreadyMountedWithScope
        let (bookmarkData, scannedItems) = try await Task.detached(priority: .userInitiated) { () throws -> (Data?, [WorkspaceFileItem]) in
            if shouldStartScope && !url.startAccessingSecurityScopedResource() {
                throw WorkspaceAccessError.accessDenied
            }
            do {
                let bookmark = needsSecurityScope
                    ? try (providedBookmark ?? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
                    : nil
                return (bookmark, WorkspaceFolderScanner.scan(url))
            } catch {
                if shouldStartScope { url.stopAccessingSecurityScopedResource() }
                throw error
            }
        }.value
        if let oldScope = activeSecurityScopedURL, oldScope.standardizedFileURL != url.standardizedFileURL {
            oldScope.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
        }
        if shouldStartScope || securityScopeAlreadyStarted || isAlreadyMountedWithScope {
            activeSecurityScopedURL = url
        }
        addFolderURL(url)
        if let bookmarkData { saveBookmark(bookmarkData, for: url) }
        applyScannedItems(scannedItems)
        mountState = .mounted(
            folderName: folderName,
            path: url.path,
            fileCount: scannedItems.count,
            scopeHeld: activeSecurityScopedURL != nil
        )
    }

    /// 兜底通道：把用户选的文件夹**整份复制**进 App 沙盒，再按沙盒内目录挂载。
    ///
    /// 为什么需要它：安全作用域书签在真机上会因 Files 提供方不同、重启、iCloud 登录态
    /// 变化而失效，一旦失效就只剩"挂载失败"。复制进沙盒之后权限问题彻底消失——
    /// 代价是编辑的是副本，需要用户自己把改动搬回去（或走 GitHub 编译链路）。
    @discardableResult
    func mountSandboxCopy(of url: URL) async throws -> URL {
        let folderName = url.lastPathComponent.isEmpty ? "工作区" : url.lastPathComponent
        mountState = .mounting("正在复制 \(folderName) 到 App 内…")
        let destination = defaultWorkspaceURL
            .appendingPathComponent(folderName, isDirectory: true)
        let needsSecurityScope = !isInAppDocuments(url)
        let scanned = try await Task.detached(priority: .userInitiated) { () throws -> [WorkspaceFileItem] in
            let started = needsSecurityScope && url.startAccessingSecurityScopedResource()
            if needsSecurityScope && !started { throw WorkspaceAccessError.accessDenied }
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            let target = destination
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let skipped: Set<String> = [".git", ".build", "Build", "DerivedData", "node_modules", "Pods", "Carthage"]
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            var copiedBytes: Int64 = 0
            let budget: Int64 = 120 * 1_024 * 1_024
            for case let item as URL in enumerator {
                let relative = item.path.dropFirst(url.path.count).drop(while: { $0 == "/" })
                if relative.isEmpty { continue }
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isDirectory = values?.isDirectory ?? false
                if isDirectory, skipped.contains(item.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                let target = destination.appendingPathComponent(String(relative))
                if isDirectory {
                    try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    continue
                }
                if copiedBytes + Int64(values?.fileSize ?? 0) > budget {
                    throw WorkspaceAccessError.fileTooLarge
                }
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: item, to: target)
                copiedBytes += Int64(values?.fileSize ?? 0)
            }
            return WorkspaceFolderScanner.scan(destination)
        }.value
        let mountedFolder = destination
        addFolderURL(mountedFolder)
        applyScannedItems(scanned)
        mountState = .mounted(
            folderName: folderName,
            path: mountedFolder.path,
            fileCount: scanned.count,
            scopeHeld: false
        )
        return mountedFolder
    }

    /// 卸载当前外部工作区并退回 App 默认工作区。
    func unmountActiveWorkspace() async {
        if let scope = activeSecurityScopedURL {
            scope.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
        }
        activeWorkspaceURL = defaultWorkspaceURL
        mountState = .idle
        await scanFolder(url: defaultWorkspaceURL)
    }

    /// 把"挂载失败"写进状态机，让工作区卡片显示红点 + 失败原因，
    /// 而不是永远停在「挂载中」。
    func noteMountFailure(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        mountState = .failed(message.isEmpty ? "挂载失败" : message)
    }

    private func addFolderURL(_ url: URL) {
        if !mountedWorkspaces.contains(url) {
            mountedWorkspaces.append(url)
        }
        activeWorkspaceURL = url
    }

    /// 扫描挂载目录内容。
    func scanFolder(url: URL) async {
        let needsSecurityScope = !isInAppDocuments(url)
        let scopeAlreadyHeld = activeSecurityScopedURL?.standardizedFileURL == url.standardizedFileURL
        let scannedItems = await Task.detached(priority: .userInitiated) { () -> [WorkspaceFileItem]? in
            let started = needsSecurityScope && !scopeAlreadyHeld && url.startAccessingSecurityScopedResource()
            if needsSecurityScope && !scopeAlreadyHeld && !started { return nil }
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            return WorkspaceFolderScanner.scan(url)
        }.value
        guard let scannedItems else {
            if activeWorkspaceURL?.standardizedFileURL == url.standardizedFileURL {
                activeWorkspaceURL = defaultWorkspaceURL
                await scanFolder(url: defaultWorkspaceURL)
            }
            return
        }
        guard activeWorkspaceURL?.standardizedFileURL == url.standardizedFileURL else { return }
        applyScannedItems(scannedItems)
    }

    private func applyScannedItems(_ scannedItems: [WorkspaceFileItem]) {
        workspaceFiles = scannedItems
        rebuildAllFiles()
        let selectedPath = currentActiveCodeFile?.url?.standardizedFileURL.path
        let activeRoot = activeWorkspaceURL?.standardizedFileURL.path
        let selectionBelongsToWorkspace = activeRoot.map { root in
            selectedPath?.hasPrefix(root + "/") == true
        } ?? false

        if let selectedPath, let refreshed = scannedItems.first(where: { $0.url?.standardizedFileURL.path == selectedPath }) {
            if currentCodeContent == lastSavedCodeContent { selectCodeFile(refreshed) }
        } else if !selectionBelongsToWorkspace {
            selectCodeFile(scannedItems.first(where: { $0.category == .code && $0.fileExtension == "swift" })
                ?? scannedItems.first(where: { $0.category == .code }))
        }
    }

    private func rebuildAllFiles() {
        let workspacePaths = Set(workspaceFiles.compactMap { $0.url?.standardizedFileURL.path })
        allFiles = workspaceFiles + libraryFiles.filter { libraryItem in
            guard let path = libraryItem.url?.standardizedFileURL.path else { return true }
            return !workspacePaths.contains(path)
        }
    }

    func refreshActiveWorkspace() async {
        guard let activeWorkspaceURL else { return }
        await scanFolder(url: activeWorkspaceURL)
    }

    func refreshCurrentCodeFile() async {
        guard let file = currentActiveCodeFile,
              let url = file.url,
              let root = activeWorkspaceURL else { return }
        let shouldReload = currentCodeContent == lastSavedCodeContent
        let needsSecurityScope = !isInAppDocuments(root)
        let snapshot = await Task.detached(priority: .utility) { () -> (WorkspaceFileItem, String?)? in
            let accessing = !needsSecurityScope || root.startAccessingSecurityScopedResource()
            guard accessing else { return nil }
            defer { if needsSecurityScope { root.stopAccessingSecurityScopedResource() } }
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let modifiedAt = values.contentModificationDate else { return nil }
            let size = Int64(values.fileSize ?? 0)
            guard size != file.size || modifiedAt != file.modifiedAt else { return nil }
            var refreshed = file
            refreshed.size = size
            refreshed.modifiedAt = modifiedAt
            let text = shouldReload && size <= WorkspaceFileTypes.maxTextFileBytes
                ? Self.decodeText(at: url)
                : nil
            return (refreshed, text)
        }.value
        guard let (refreshed, text) = snapshot, currentActiveCodeFile?.id == file.id else { return }
        currentActiveCodeFile = refreshed
        upsertFile(refreshed)
        if currentCodeContent == lastSavedCodeContent, let text {
            currentCodeContent = text
            lastSavedCodeContent = text
        }
    }

    // MARK: - 文件读写（支持直接修改并保存手机上的文件）

    func readFileContent(for item: WorkspaceFileItem) -> String {
        if let url = item.url {
            let isLocalLibraryFile = url.standardizedFileURL.path.hasPrefix(localLibraryURL.standardizedFileURL.path + "/")
            let scopeRoot = activeWorkspaceURL.flatMap { root in
                url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") ? root : nil
            }
            let accessURL = isLocalLibraryFile ? nil : (scopeRoot ?? url)
            let needsSecurityScope = accessURL.map { !isInAppDocuments($0) } ?? false
            let scopeAlreadyHeld = accessURL.map { activeSecurityScopedURL?.standardizedFileURL == $0.standardizedFileURL } ?? false
            let accessing = !needsSecurityScope || scopeAlreadyHeld || (accessURL?.startAccessingSecurityScopedResource() ?? true)
            guard accessing else { return "// 文件内容为空或二进制不可读" }
            defer { if needsSecurityScope && !scopeAlreadyHeld { accessURL?.stopAccessingSecurityScopedResource() } }
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize,
               Int64(size) > WorkspaceFileTypes.maxTextFileBytes {
                return "// 文件超过 4 MB，当前编辑器不会加载它"
            }
            if let text = Self.decodeText(at: url) {
                return text
            }
        }
        return "// 文件内容为空或二进制不可读"
    }

    func readFileContentAsync(for item: WorkspaceFileItem) async -> String {
        guard let url = item.url else { return "// 文件内容为空或不可读取。" }
        let localLibraryPath = localLibraryURL.standardizedFileURL.path
        let localLibraryFile = url.standardizedFileURL.path.hasPrefix(localLibraryPath + "/")
        let scopeRoot = activeWorkspaceURL.flatMap { root in
            url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") ? root : nil
        }
        let accessURL = localLibraryFile ? nil : (scopeRoot ?? url)
        let needsSecurityScope = accessURL.map { !isInAppDocuments($0) } ?? false
        let scopeAlreadyHeld = accessURL.map { activeSecurityScopedURL?.standardizedFileURL == $0.standardizedFileURL } ?? false
        return await Task.detached(priority: .userInitiated) {
            let accessing = !needsSecurityScope || scopeAlreadyHeld || (accessURL?.startAccessingSecurityScopedResource() ?? true)
            guard accessing else { return "// 无法访问此文件。" }
            defer { if needsSecurityScope && !scopeAlreadyHeld { accessURL?.stopAccessingSecurityScopedResource() } }
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  Int64(values.fileSize ?? 0) <= WorkspaceFileTypes.maxTextFileBytes else {
                return "// 文件超过 4 MB，编辑器不会加载。"
            }
            return Self.decodeText(at: url) ?? "// 文件内容为空或不是可读取的文本格式。"
        }.value
    }

    func saveFileContent(item: WorkspaceFileItem, newContent: String) async throws {
        guard let path = relativePath(for: item) else { throw WorkspaceAccessError.invalidPath }
        try await writeWorkspaceText(path: path, content: newContent)
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
        currentCodeContent = ""
        lastSavedCodeContent = ""
        Task { [weak self] in
            guard let self else { return }
            let content = await self.readFileContentAsync(for: item)
            guard self.currentActiveCodeFile?.id == item.id else { return }
            self.currentCodeContent = content
            self.lastSavedCodeContent = content
        }
    }

    func relativePath(for item: WorkspaceFileItem) -> String? {
        guard let root = activeWorkspaceURL?.standardizedFileURL.path,
              let file = item.url?.standardizedFileURL.path,
              file.hasPrefix(root + "/") else { return nil }
        return String(file.dropFirst(root.count + 1))
    }

    func readWorkspaceText(path: String) async throws -> String {
        guard let root = activeWorkspaceURL else { throw WorkspaceAccessError.noFolder }
        let needsSecurityScope = !isInAppDocuments(root)
        return try await Task.detached(priority: .utility) {
            let accessing = !needsSecurityScope || root.startAccessingSecurityScopedResource()
            guard accessing else { throw WorkspaceAccessError.accessDenied }
            defer { if needsSecurityScope { root.stopAccessingSecurityScopedResource() } }
            let rootURL = root.standardizedFileURL
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw WorkspaceAccessError.invalidPath
            }
            let url = rootURL.appending(path: path).standardizedFileURL
            guard url.path.hasPrefix(rootURL.path + "/"),
                  url.resolvingSymlinksInPath().path.hasPrefix(rootURL.resolvingSymlinksInPath().path + "/") else {
                throw WorkspaceAccessError.invalidPath
            }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw WorkspaceAccessError.invalidPath }
            guard Int64(values.fileSize ?? 0) <= WorkspaceFileTypes.maxTextFileBytes else { throw WorkspaceAccessError.fileTooLarge }
            guard let text = Self.decodeText(at: url) else { throw WorkspaceAccessError.unreadableFile }
            return text
        }.value
    }

    func writeWorkspaceText(path: String, content: String) async throws {
        guard Int64(content.utf8.count) <= WorkspaceFileTypes.maxTextFileBytes else { throw WorkspaceAccessError.fileTooLarge }
        guard let root = activeWorkspaceURL else { throw WorkspaceAccessError.noFolder }
        let needsSecurityScope = !isInAppDocuments(root)
        let updated = try await Task.detached(priority: .userInitiated) { () throws -> WorkspaceFileItem in
            let accessing = !needsSecurityScope || root.startAccessingSecurityScopedResource()
            guard accessing else { throw WorkspaceAccessError.accessDenied }
            defer { if needsSecurityScope { root.stopAccessingSecurityScopedResource() } }
            let rootURL = root.standardizedFileURL
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw WorkspaceAccessError.invalidPath
            }
            let url = rootURL.appending(path: path).standardizedFileURL
            guard url.path.hasPrefix(rootURL.path + "/"),
                  url.resolvingSymlinksInPath().path.hasPrefix(rootURL.resolvingSymlinksInPath().path + "/") else {
                throw WorkspaceAccessError.invalidPath
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return WorkspaceFileItem(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: false,
                size: Int64(content.utf8.count),
                modifiedAt: Date(),
                fileExtension: url.pathExtension.lowercased(),
                url: url,
                category: WorkspaceFileTypes.category(
                    for: url.lastPathComponent,
                    extension: url.pathExtension.lowercased(),
                    isText: true
                )
            )
        }.value
        upsertFile(updated)
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

    nonisolated private static func decodeText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        for encoding in [
            String.Encoding.utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .windowsCP1252,
            .isoLatin1
        ] {
            if let text = String(data: data, encoding: encoding), !text.contains("\u{0000}") {
                return text
            }
        }
        return nil
    }

    func createNewFile(name: String, content: String, category: WorkspaceFileItem.AssetCategory) throws -> WorkspaceFileItem {
        let cleanName = (name as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName == name else { throw WorkspaceAccessError.invalidPath }
        let root = activeWorkspaceURL ?? localLibraryURL
        let needsSecurityScope = activeWorkspaceURL != nil && !isInAppDocuments(root)
        if needsSecurityScope && !root.startAccessingSecurityScopedResource() { throw WorkspaceAccessError.accessDenied }
        defer { if needsSecurityScope { root.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent(cleanName, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw CocoaError(.fileWriteFileExists) }
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        let newItem = WorkspaceFileItem(
            name: cleanName,
            path: fileURL.path,
            isDirectory: false,
            size: Int64(content.utf8.count),
            modifiedAt: Date(),
            fileExtension: fileURL.pathExtension.lowercased(),
            url: fileURL,
            category: category
        )
        upsertFile(newItem)
        return newItem
    }

    func importFiles(_ urls: [URL]) async throws {
        let libraryURL = localLibraryURL
        let items = try await Task.detached(priority: .userInitiated) { () throws -> [WorkspaceFileItem] in
            try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
            var copiedURLs: [URL] = []
            var importedItems: [WorkspaceFileItem] = []
            do {
                for source in urls {
                    guard source.startAccessingSecurityScopedResource() else { throw WorkspaceAccessError.accessDenied }
                    defer { source.stopAccessingSecurityScopedResource() }
                    let stem = source.deletingPathExtension().lastPathComponent
                    let ext = source.pathExtension
                    var target = libraryURL.appendingPathComponent(source.lastPathComponent)
                    if FileManager.default.fileExists(atPath: target.path) {
                        let suffix = UUID().uuidString.prefix(8)
                        let uniqueName = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
                        target = libraryURL.appendingPathComponent(uniqueName)
                    }
                    do {
                        try FileManager.default.copyItem(at: source, to: target)
                        copiedURLs.append(target)
                        let values = try target.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                        let fileExtension = target.pathExtension.lowercased()
                        let importedItem = WorkspaceFileItem(
                            name: target.lastPathComponent,
                            path: target.path,
                            isDirectory: values.isDirectory ?? false,
                            size: Int64(values.fileSize ?? 0),
                            modifiedAt: values.contentModificationDate ?? Date(),
                            fileExtension: fileExtension,
                            url: target,
                            category: WorkspaceFileTypes.category(for: target.lastPathComponent, extension: fileExtension)
                        )
                        importedItems.append(importedItem)
                        if importedItem.isDirectory {
                            importedItems.append(contentsOf: WorkspaceFolderScanner.scan(target))
                        }
                    } catch {
                        try? FileManager.default.removeItem(at: target)
                        throw error
                    }
                }
            } catch {
                copiedURLs.forEach { try? FileManager.default.removeItem(at: $0) }
                throw error
            }
            return importedItems
        }.value
        items.forEach(upsertFile)
    }

    func deleteFile(_ item: WorkspaceFileItem) throws {
        guard let url = item.url else { throw WorkspaceAccessError.invalidPath }
        let isLocalLibraryFile = isInLocalLibrary(url)
        let scopeRoot = activeWorkspaceURL.flatMap { root in
            url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") ? root : nil
        }
        let accessURL = isLocalLibraryFile ? nil : (scopeRoot ?? url)
        let needsSecurityScope = accessURL.map { !isInAppDocuments($0) } ?? false
        let accessing = !needsSecurityScope || (accessURL?.startAccessingSecurityScopedResource() ?? true)
        guard accessing else { throw WorkspaceAccessError.accessDenied }
        defer { if needsSecurityScope { accessURL?.stopAccessingSecurityScopedResource() } }
        try FileManager.default.removeItem(at: url)
        if isLocalLibraryFile { libraryRevision += 1 }
        workspaceFiles.removeAll { $0.id == item.id }
        libraryFiles.removeAll { $0.id == item.id }
        rebuildAllFiles()
    }

    private func isInLocalLibrary(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(localLibraryURL.standardizedFileURL.path + "/")
    }

    func isInAppDocuments(_ url: URL) -> Bool {
        let root = documentsURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    private func upsertFile(_ item: WorkspaceFileItem) {
        if isInLocalLibrary(item.url ?? URL(fileURLWithPath: item.path)) {
            libraryRevision += 1
            if let index = libraryFiles.firstIndex(where: { $0.id == item.id }) {
                libraryFiles[index] = item
            } else {
                libraryFiles.insert(item, at: 0)
            }
        } else if let index = workspaceFiles.firstIndex(where: { $0.id == item.id }) {
            workspaceFiles[index] = item
        } else {
            workspaceFiles.insert(item, at: 0)
        }
        rebuildAllFiles()
    }

    // MARK: - 书签持久化

    private func saveBookmark(_ data: Data, for url: URL) {
        var dict = UserDefaults.standard.dictionary(forKey: bookmarkStorageKey) as? [String: Data] ?? [:]
        dict[url.path] = data
        UserDefaults.standard.set(dict, forKey: bookmarkStorageKey)
    }

    private func loadBookmarks() {
        guard let dict = UserDefaults.standard.dictionary(forKey: bookmarkStorageKey) as? [String: Data] else { return }
        for (storedPath, data) in dict {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if !mountedWorkspaces.contains(resolvedURL) {
                    mountedWorkspaces.append(resolvedURL)
                }
                if !isInAppDocuments(resolvedURL), resolvedURL.startAccessingSecurityScopedResource() {
                    if let previousScope = activeSecurityScopedURL,
                       previousScope.standardizedFileURL != resolvedURL.standardizedFileURL {
                        previousScope.stopAccessingSecurityScopedResource()
                    }
                    activeSecurityScopedURL = resolvedURL
                }
                // The most recently saved bookmark wins over the private default workspace.
                activeWorkspaceURL = resolvedURL
                Task { await scanFolder(url: resolvedURL) }
                if isStale, let refreshed = try? resolvedURL.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    saveBookmark(refreshed, for: resolvedURL)
                } else if storedPath != resolvedURL.path {
                    saveBookmark(data, for: resolvedURL)
                }
            }
        }
    }

}
