import Foundation

/// Configuration for the GitHub repository DayFlow commits time-logs into.
/// Persisted in UserDefaults except the token, which lives in `KeychainStore`.
/// Ported from VoiceDrop.
struct GitHubConfig: Codable, Equatable {
    var owner: String
    var repo: String
    var branch: String

    static let defaultConfig = GitHubConfig(owner: "", repo: "", branch: "main")

    /// Owner segment only; tolerates a pasted "owner/repo" or URL.
    var cleanOwner: String {
        let t = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains("/") { return t.split(separator: "/").first.map(String.init) ?? t }
        return t
    }

    /// Repo name only; tolerates a pasted "owner/repo".
    var cleanRepo: String {
        let t = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains("/") { return t.split(separator: "/").last.map(String.init) ?? t }
        return t
    }

    var cleanBranch: String {
        let t = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "main" : t
    }

    var isComplete: Bool { !cleanOwner.isEmpty && !cleanRepo.isEmpty }
}

enum GitHubError: LocalizedError {
    case notConfigured
    case missingToken
    case http(status: Int, message: String)
    case decoding
    case conflictRetriesExhausted

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "GitHubリポジトリが設定されていません"
        case .missingToken: return "GitHubトークンが設定されていません（設定 > Obsidian同期）"
        case .http(let status, let message): return "GitHubエラー (\(status)): \(message)"
        case .decoding: return "GitHubの応答を解釈できませんでした"
        case .conflictRetriesExhausted: return "他の書き込みと競合しました。少し待って再試行してください"
        }
    }
}

/// Commits files to a GitHub repository via the Contents API — GET-current-blob →
/// replace-content → PUT-with-sha, one commit per write. DayFlow only ever replaces a
/// whole day's time-log file, so `putStandalone` (via `mutateFile`) is all it needs.
struct GitHubClient {
    let config: GitHubConfig
    /// Resolved lazily so a token entered mid-session is picked up without reinit.
    let tokenProvider: () -> String?

    static let tokenAccount = "githubToken"

    private func makeRequest(path: String, method: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard config.isComplete else { throw GitHubError.notConfigured }
        guard let token = tokenProvider(), !token.isEmpty else { throw GitHubError.missingToken }
        guard var comps = URLComponents(
            string: "https://api.github.com/repos/\(config.cleanOwner)/\(config.cleanRepo)/contents"
        ) else { throw GitHubError.notConfigured }
        comps.path += "/" + path      // URLComponents percent-encodes exactly once (Japanese-safe)
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw GitHubError.notConfigured }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return req
    }

    struct FileState { let content: String; let sha: String }

    /// Current decoded content + blob SHA, or nil if the file doesn't exist (404).
    func fetchFile(path: String) async throws -> FileState? {
        let req = try makeRequest(path: path, method: "GET",
                                  query: [URLQueryItem(name: "ref", value: config.cleanBranch)])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.decoding }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else {
            throw GitHubError.http(status: http.statusCode, message: Self.messageFrom(data))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = obj["sha"] as? String,
              let b64 = obj["content"] as? String
        else { throw GitHubError.decoding }
        let cleaned = b64.replacingOccurrences(of: "\n", with: "")
        guard let raw = Data(base64Encoded: cleaned),
              let text = String(data: raw, encoding: .utf8)
        else { throw GitHubError.decoding }
        return FileState(content: text, sha: sha)
    }

    /// Creates or replaces a file. Pass `sha` when replacing. Returns the new blob SHA.
    @discardableResult
    func putFile(path: String, content: String, message: String, sha: String?) async throws -> String {
        var req = try makeRequest(path: path, method: "PUT")
        var body: [String: Any] = [
            "message": message,
            "content": Data(content.utf8).base64EncodedString(),
            "branch": config.cleanBranch,
        ]
        if let sha { body["sha"] = sha }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.decoding }
        guard (200...201).contains(http.statusCode) else {
            throw GitHubError.http(status: http.statusCode, message: Self.messageFrom(data))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentObj = obj["content"] as? [String: Any],
              let newSha = contentObj["sha"] as? String
        else { throw GitHubError.decoding }
        return newSha
    }

    /// Read-modify-write with conflict retry. `transform` gets current content (nil if
    /// the file is new) and returns the full replacement. Retries on HTTP 409.
    func mutateFile(path: String, message: String, maxRetries: Int = 3,
                    transform: (String?) -> String) async throws {
        var attempt = 0
        while true {
            let current = try await fetchFile(path: path)
            let newContent = transform(current?.content)
            do {
                try await putFile(path: path, content: newContent, message: message, sha: current?.sha)
                return
            } catch let GitHubError.http(status, _) where status == 409 && attempt < maxRetries {
                attempt += 1
                try? await Task.sleep(nanoseconds: 300_000_000)
                continue
            } catch let GitHubError.http(status, _) where status == 409 {
                throw GitHubError.conflictRetriesExhausted
            }
        }
    }

    private static func messageFrom(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = obj["message"] as? String { return message }
        return String(data: data, encoding: .utf8) ?? "unknown error"
    }
}
