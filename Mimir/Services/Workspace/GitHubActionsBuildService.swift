import Foundation

struct GitHubBuildResult: Sendable {
    var accountLogin: String
    var repository: String
    var branch: String
    var runURL: URL
    var runID: Int?
    var fileCount: Int
    var totalBytes: Int64
    var isPrivateRepository: Bool
}

struct GitHubBuildStatus: Sendable {
    var status: String
    var conclusion: String?
    var activeStep: String?
}

enum GitHubBuildError: LocalizedError {
    case invalidRepository
    case invalidToken
    case accountChanged(expected: String, actual: String)
    case noWorkspace
    case noProject
    case tooManyFiles
    case tooLarge
    case missingWorkflow
    case missingPermissions
    case api(status: Int, message: String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .invalidRepository: return "GitHub 仓库格式应为 owner/repository。"
        case .invalidToken: return "无法验证这个 GitHub 令牌，请检查令牌是否有效。"
        case .accountChanged(let expected, let actual): return "绑定账号不匹配：当前令牌属于 @\(actual)，已绑定账号是 @\(expected)。请重新绑定。"
        case .noWorkspace: return "请先选择要编译的项目文件夹。"
        case .noProject: return "所选文件夹里没有 Project.yml、.xcodeproj 或 .xcworkspace。"
        case .tooManyFiles: return "项目包含超过 400 个文件，暂不支持上传构建。"
        case .tooLarge: return "项目文件总量超过 40 MB，暂不支持上传构建。"
        case .missingWorkflow: return "目标仓库默认分支缺少 .github/workflows/build-ipa.yml。请先将 Mimir 的构建工作流加入该仓库。"
        case .missingPermissions: return "令牌需要目标仓库 Contents 与 Actions 的读写权限。"
        case .api(let status, let message): return "GitHub API 错误（HTTP \(status)）：\(message)"
        case .malformedResponse: return "GitHub 返回了无法识别的响应。"
        }
    }
}

enum GitHubActionsBuildService {
    private struct UploadTarget: Sendable {
        var path: String
        var url: URL
        var size: Int64
        var executable: Bool
    }

    @MainActor
    static func dispatch(
        workspace: WorkspaceManager,
        repository: String,
        expectedAccountLogin: String,
        token: String
    ) async throws -> GitHubBuildResult {
        let components = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              components.allSatisfy({ $0.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil }) else {
            throw GitHubBuildError.invalidRepository
        }
        let owner = String(components[0])
        let repo = String(components[1])
        let apiRoot = "https://api.github.com/repos/\(owner)/\(repo)"
        let accountLogin = try await authenticatedLogin(token: token)
        guard accountLogin.caseInsensitiveCompare(expectedAccountLogin) == .orderedSame else {
            throw GitHubBuildError.accountChanged(expected: expectedAccountLogin, actual: accountLogin)
        }
        guard let root = workspace.activeWorkspaceURL else { throw GitHubBuildError.noWorkspace }
        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }

        let targets = workspace.allFiles.compactMap { item -> UploadTarget? in
            guard !item.isDirectory,
                  let url = item.url,
                  let path = workspace.relativePath(for: item),
                  !path.split(separator: "/").contains(where: { [".git", "Build", ".build", "DerivedData", "node_modules", "Pods", "Carthage"].contains(String($0)) }) else {
                return nil
            }
            return UploadTarget(path: path, url: url, size: item.size, executable: item.fileExtension == "sh")
        }
        guard !targets.isEmpty else { throw GitHubBuildError.noProject }
        guard targets.count <= 400 else { throw GitHubBuildError.tooManyFiles }
        let totalSize = targets.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize <= 40 * 1_024 * 1_024 else { throw GitHubBuildError.tooLarge }

        let paths = Set(targets.map(\.path))
        let hasProject = paths.contains("Project.yml")
            || paths.contains(where: { $0.hasSuffix(".xcodeproj/project.pbxproj") })
            || paths.contains(where: { $0.hasSuffix(".xcworkspace/contents.xcworkspacedata") })
        guard hasProject else { throw GitHubBuildError.noProject }

        let repoData = try await request(apiRoot, path: "", token: token)
        guard let repoJSON = try JSONSerialization.jsonObject(with: repoData) as? [String: Any],
              let defaultBranch = repoJSON["default_branch"] as? String else { throw GitHubBuildError.malformedResponse }
        let isPrivate = repoJSON["private"] as? Bool ?? false
        let hasPushAccess = (repoJSON["permissions"] as? [String: Bool])?["push"] ?? false
        guard hasPushAccess else { throw GitHubBuildError.missingPermissions }

        do {
            _ = try await request(apiRoot, path: "/actions/workflows/build-ipa.yml", token: token)
        } catch let error as GitHubBuildError {
            if case .api(status: 404, message: _) = error { throw GitHubBuildError.missingWorkflow }
            throw error
        }

        let refPath = "/git/ref/heads/\(encodePath(defaultBranch))"
        let refData: Data
        do {
            refData = try await request(apiRoot, path: refPath, token: token)
        } catch let error as GitHubBuildError {
            if case .api(status: 404, message: _) = error {
                throw GitHubBuildError.api(status: 404, message: "无法读取默认分支 \(defaultBranch)")
            }
            throw error
        }
        guard let refJSON = try JSONSerialization.jsonObject(with: refData) as? [String: Any],
              let object = refJSON["object"] as? [String: Any],
              let baseSHA = object["sha"] as? String else { throw GitHubBuildError.malformedResponse }
        let commitData = try await request(apiRoot, path: "/git/commits/\(baseSHA)", token: token)
        guard let commitJSON = try JSONSerialization.jsonObject(with: commitData) as? [String: Any],
              let tree = commitJSON["tree"] as? [String: Any],
              let baseTreeSHA = tree["sha"] as? String else { throw GitHubBuildError.malformedResponse }

        var blobs: [(String, String, Bool)] = []
        try await withThrowingTaskGroup(of: (String, String, Bool).self) { group in
            var next = 0
            for _ in 0..<min(4, targets.count) {
                let target = targets[next]
                next += 1
                group.addTask {
                    let data = try Data(contentsOf: target.url, options: [.mappedIfSafe])
                    guard data.count <= 40 * 1_024 * 1_024 else { throw GitHubBuildError.tooLarge }
                    let sha = try await createBlob(data, apiRoot: apiRoot, token: token)
                    return (target.path, sha, target.executable)
                }
            }
            while let blob = try await group.next() {
                blobs.append(blob)
                if next < targets.count {
                    let target = targets[next]
                    next += 1
                    group.addTask {
                        let data = try Data(contentsOf: target.url, options: [.mappedIfSafe])
                        guard data.count <= 40 * 1_024 * 1_024 else { throw GitHubBuildError.tooLarge }
                        let sha = try await createBlob(data, apiRoot: apiRoot, token: token)
                        return (target.path, sha, target.executable)
                    }
                }
            }
        }

        let treeEntries: [[String: String]] = blobs.map { path, sha, executable in
            [
                "path": "MobileProject/\(path)",
                "mode": executable ? "100755" : "100644",
                "type": "blob",
                "sha": sha
            ]
        }
        let newTreeData = try await request(
            apiRoot,
            path: "/git/trees",
            method: "POST",
            token: token,
            body: try jsonData(["base_tree": baseTreeSHA, "tree": treeEntries])
        )
        guard let newTreeJSON = try JSONSerialization.jsonObject(with: newTreeData) as? [String: Any],
              let newTreeSHA = newTreeJSON["sha"] as? String else { throw GitHubBuildError.malformedResponse }

        let nonce = String(UUID().uuidString.prefix(8)).lowercased()
        let branch = "mimir-code-build-\(Int(Date().timeIntervalSince1970))-\(nonce)"
        let newCommitData = try await request(
            apiRoot,
            path: "/git/commits",
            method: "POST",
            token: token,
            body: try jsonData(["message": "Build selected iOS project from Mimir", "tree": newTreeSHA, "parents": [baseSHA]])
        )
        guard let newCommitJSON = try JSONSerialization.jsonObject(with: newCommitData) as? [String: Any],
              let newCommitSHA = newCommitJSON["sha"] as? String else { throw GitHubBuildError.malformedResponse }

        _ = try await request(
            apiRoot,
            path: "/git/refs",
            method: "POST",
            token: token,
            body: try jsonData(["ref": "refs/heads/\(branch)", "sha": newCommitSHA])
        )
        do {
            _ = try await request(
                apiRoot,
                path: "/actions/workflows/build-ipa.yml/dispatches",
                method: "POST",
                token: token,
                body: try jsonData(["ref": branch, "inputs": ["project_path": "MobileProject"]])
            )
        } catch let error as GitHubBuildError {
            try? await request(
                apiRoot,
                path: "/git/refs/heads/\(branch)",
                method: "DELETE",
                token: token
            )
            if case .api(status: 404, message: _) = error {
                throw GitHubBuildError.missingWorkflow
            }
            throw error
        }

        let run: (id: Int, url: URL)?
        do {
            run = try await findRun(branch: branch, apiRoot: apiRoot, token: token)
        } catch {
            try? await request(apiRoot, path: "/git/refs/heads/\(branch)", method: "DELETE", token: token)
            throw error
        }
        guard let url = run?.url ?? URL(string: "https://github.com/\(owner)/\(repo)/actions") else {
            throw GitHubBuildError.malformedResponse
        }
        return GitHubBuildResult(
            accountLogin: accountLogin,
            repository: "\(owner)/\(repo)",
            branch: branch,
            runURL: url,
            runID: run?.id,
            fileCount: targets.count,
            totalBytes: totalSize,
            isPrivateRepository: isPrivate
        )
    }

    static func status(
        runID: Int,
        repository: String,
        token: String
    ) async throws -> GitHubBuildStatus {
        let components = repository.split(separator: "/")
        guard components.count == 2 else { throw GitHubBuildError.invalidRepository }
        let apiRoot = "https://api.github.com/repos/\(components[0])/\(components[1])"
        async let runData = request(apiRoot, path: "/actions/runs/\(runID)", token: token)
        async let jobsData = request(apiRoot, path: "/actions/runs/\(runID)/jobs?per_page=100", token: token)
        let (data, jobData) = try await (runData, jobsData)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String,
              let jobsJSON = try JSONSerialization.jsonObject(with: jobData) as? [String: Any] else {
            throw GitHubBuildError.malformedResponse
        }
        let jobs = jobsJSON["jobs"] as? [[String: Any]] ?? []
        let activeStep = jobs
            .flatMap { $0["steps"] as? [[String: Any]] ?? [] }
            .first(where: { $0["status"] as? String == "in_progress" })?["name"] as? String
        return GitHubBuildStatus(status: status, conclusion: json["conclusion"] as? String, activeStep: activeStep)
    }

    static func authenticatedLogin(token: String) async throws -> String {
        let data: Data
        do {
            data = try await request("https://api.github.com", path: "/user", token: token)
        } catch let error as GitHubBuildError {
            if case .api(status: 401, message: _) = error { throw GitHubBuildError.invalidToken }
            throw error
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["login"] as? String,
              !login.isEmpty else { throw GitHubBuildError.malformedResponse }
        return login
    }

    private static func createBlob(_ data: Data, apiRoot: String, token: String) async throws -> String {
        let response = try await request(
            apiRoot,
            path: "/git/blobs",
            method: "POST",
            token: token,
                    body: try jsonData(["content": data.base64EncodedString(), "encoding": "base64"])
        )
        guard let json = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let sha = json["sha"] as? String else { throw GitHubBuildError.malformedResponse }
        return sha
    }

    private static func findRun(branch: String, apiRoot: String, token: String) async throws -> (id: Int, url: URL)? {
        for _ in 0..<8 {
            try await Task.sleep(for: .seconds(1))
            let data = try await request(
                apiRoot,
                path: "/actions/workflows/build-ipa.yml/runs?branch=\(branch)&event=workflow_dispatch&per_page=1",
                token: token
            )
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let runs = json["workflow_runs"] as? [[String: Any]] else { continue }
            if let run = runs.first,
               let id = run["id"] as? Int,
               let html = run["html_url"] as? String,
               let url = URL(string: html) {
                return (id, url)
            }
        }
        return nil
    }

    private static func encodePath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? value
    }

    private static func jsonData(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    private static func request(
        _ apiRoot: String,
        path: String,
        method: String = "GET",
        token: String,
        body: Data? = nil
    ) async throws -> Data {
        let fullURL = apiRoot + path
        guard let url = URL(string: fullURL) else { throw GitHubBuildError.malformedResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubBuildError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                ?? String(data: data.prefix(400), encoding: .utf8)
                ?? "请求失败"
            throw GitHubBuildError.api(status: http.statusCode, message: message)
        }
        return data
    }
}
