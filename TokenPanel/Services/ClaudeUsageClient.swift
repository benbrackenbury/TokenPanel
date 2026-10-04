import Foundation
#if canImport(Security)
import Security
#endif

enum ClaudeAuthStore {
    static func credentialsFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CREDENTIALS_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return LocalHome.realHomeDirectory().appendingPathComponent(".claude/.credentials.json")
    }

    static var isConfigured: Bool {
        FileManager.default.fileExists(atPath: credentialsFileURL().path) || keychainToken() != nil
    }

    static func load() throws -> (token: String, identity: AccountIdentity) {
        if let fromFile = try? loadFromFile() {
            return fromFile
        }
        if let token = keychainToken(), !token.isEmpty {
            return (token, AccountIdentity(planLabel: "Claude"))
        }
        throw TokenPanelError.notSignedIn(.claude)
    }

    private static func loadFromFile() throws -> (token: String, identity: AccountIdentity) {
        let url = credentialsFileURL()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TokenPanelError.authFileUnreadable(path: url.path, underlying: error.localizedDescription)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TokenPanelError.notSignedIn(.claude)
        }
        let oauth = JSONMap.dict(root["claudeAiOauth"]) ?? root
        guard let token = JSONMap.string(oauth["accessToken"]) else {
            throw TokenPanelError.notSignedIn(.claude)
        }
        let identity = AccountIdentity(
            email: JSONMap.string(oauth["email"]) ?? JSONMap.string(root["email"]),
            expiresAt: JSONMap.date(oauth["expiresAt"]),
            planLabel: JSONMap.string(oauth["subscriptionType"]) ?? "Claude"
        )
        return (token, identity)
    }

    static func keychainToken() -> String? {
        #if canImport(Security)
        for service in ["Claude Code-credentials", "Claude Code"] {
            if let token = genericPassword(service: service) { return token }
        }
        #endif
        return nil
    }

    #if canImport(Security)
    private static func genericPassword(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let oauth = JSONMap.dict(json["claudeAiOauth"]) ?? json
            if let token = JSONMap.string(oauth["accessToken"]) { return token }
        }
        return String(data: data, encoding: .utf8).flatMap { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
    #endif
}

final class ClaudeUsageClient: UsageFetching, Sendable {
    let provider: ProviderID = .claude
    var isConfigured: Bool { ClaudeAuthStore.isConfigured }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch() async throws -> UsageSnapshot {
        let (token, identity) = try ClaudeAuthStore.load()
        let parsed = try await fetchUsage(token: token)
        var merged = parsed.identity
        if merged.email == nil { merged.email = identity.email }
        if merged.planLabel == nil { merged.planLabel = identity.planLabel }
        return UsageSnapshot(
            provider: .claude,
            usedPercent: parsed.usedPercent,
            periodStart: parsed.periodStart,
            resetsAt: parsed.resetsAt,
            features: parsed.features,
            identity: merged,
            source: "claude oauth usage",
            fetchedAt: Date()
        )
    }

    private func fetchUsage(token: String) async throws -> Parsed {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-cli (external, cli)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TokenPanelError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TokenPanelError.http(status: -1, body: "Non-HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw TokenPanelError.http(status: http.statusCode, body: body)
        }
        return try Self.parse(data)
    }

    struct Parsed {
        var usedPercent: Double?
        var periodStart: Date?
        var resetsAt: Date?
        var features: [FeatureUsage]
        var identity: AccountIdentity
    }

    static func parse(_ data: Data) throws -> Parsed {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let object = JSONMap.dict(root) else { throw TokenPanelError.parseFailed }

        func window(_ key: String, id: String) -> (FeatureUsage, Date?)? {
            guard let node = JSONMap.dict(object[key]),
                  let percent = JSONMap.double(node["utilization"]) ?? JSONMap.double(node["percent"])
            else { return nil }
            return (FeatureUsage(id: id, percent: percent), JSONMap.date(node["resets_at"]))
        }

        var features: [FeatureUsage] = []
        var resets: Date?
        let mapping = [
            ("five_hour", "5h"),
            ("seven_day", "week"),
            ("seven_day_opus", "week-opus"),
            ("seven_day_sonnet", "week-sonnet")
        ]
        for (key, id) in mapping {
            if let (feature, date) = window(key, id: id) {
                features.append(feature)
                if id == "5h" { resets = date }
                if resets == nil { resets = date }
            }
        }

        let used = features.first(where: { $0.id == "5h" })?.percent ?? features.first?.percent
        guard used != nil || !features.isEmpty else { throw TokenPanelError.parseFailed }

        return Parsed(
            usedPercent: used,
            periodStart: nil,
            resetsAt: resets,
            features: features,
            identity: AccountIdentity()
        )
    }
}
