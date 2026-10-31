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
        if isText || isTextLike(name: name, extension: ext) {
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
        let needsSecurityScope = !isInAppDocuments(url)
        let startedHere = needsSecurityScope && !securityScopeAlreadyStarted
        if startedHere && !url.startAccessingSecurityScopedResource() {
            throw WorkspaceAccessError.accessDenied
        }
        defer {
            if startedHere || securityScopeAlreadyStarted { url.stopAccessingSecurityScopedResource() }
        }

        // Keep the security-scoped bookmark so the selected folder can be restored after relaunch.
        let bookmarkData: Data
        if let providedBookmark {
            bookmarkData = providedBookmark
        } else {
            bookmarkData = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        if needsSecurityScope { saveBookmark(bookmarkData, for: url) }
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
        let needsSecurityScope = !isInAppDocuments(url)
        let startedAccess = !needsSecurityScope || url.startAccessingSecurityScopedResource()
        guard startedAccess else {
            if activeWorkspaceURL?.standardizedFileURL == url.standardizedFileURL {
                activeWorkspaceURL = defaultWorkspaceURL
                await scanFolder(url: defaultWorkspaceURL)
            }
            return
        }
        defer {
            if needsSecurityScope { url.stopAccessingSecurityScopedResource() }
        }
        let scannedItems = await Task.detached(priority: .userInitiated) {
            WorkspaceFolderScanner.scan(url)
        }.value
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
            let accessing = !needsSecurityScope || (accessURL?.startAccessingSecurityScopedResource() ?? true)
            guard accessing else { return "// 文件内容为空或二进制不可读" }
            defer { if needsSecurityScope { accessURL?.stopAccessingSecurityScopedResource() } }
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
        let needsSecurityScope = !isInAppDocuments(root)
        let accessing = !needsSecurityScope || root.startAccessingSecurityScopedResource()
        guard accessing else { throw WorkspaceAccessError.accessDenied }
        defer { if needsSecurityScope { root.stopAccessingSecurityScopedResource() } }
        let url = try validatedWorkspaceURL(path: path)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw WorkspaceAccessError.invalidPath }
        guard Int64(values.fileSize ?? 0) <= WorkspaceFileTypes.maxTextFileBytes else { throw WorkspaceAccessError.fileTooLarge }
        guard let text = Self.decodeText(at: url) else { throw WorkspaceAccessError.unreadableFile }
        return text
    }

    func writeWorkspaceText(path: String, content: String) throws {
        guard Int64(content.utf8.count) <= WorkspaceFileTypes.maxTextFileBytes else { throw WorkspaceAccessError.fileTooLarge }
        guard let root = activeWorkspaceURL else { throw WorkspaceAccessError.noFolder }
        let needsSecurityScope = !isInAppDocuments(root)
        let accessing = !needsSecurityScope || root.startAccessingSecurityScopedResource()
        guard accessing else { throw WorkspaceAccessError.accessDenied }
        defer { if needsSecurityScope { root.stopAccessingSecurityScopedResource() } }
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
            category: WorkspaceFileTypes.category(
                for: url.lastPathComponent,
                extension: url.pathExtension.lowercased(),
                isText: true
            )
        )
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
