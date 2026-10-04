import Foundation

enum CodexAuthStore {
    static func authFileURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = env["CODEX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent("auth.json")
        }
        return LocalHome.realHomeDirectory().appendingPathComponent(".codex/auth.json")
    }

    static var isConfigured: Bool {
        FileManager.default.fileExists(atPath: authFileURL().path)
    }

    static func load() throws -> (token: String, accountID: String?, identity: AccountIdentity) {
        let url = authFileURL()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) {
                throw TokenPanelError.notSignedIn(.codex)
            }
            throw TokenPanelError.authFileUnreadable(path: url.path, underlying: error.localizedDescription)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TokenPanelError.notSignedIn(.codex)
        }
        let tokens = JSONMap.dict(root["tokens"]) ?? root
        guard let token = JSONMap.string(tokens["access_token"]) ?? JSONMap.string(root["access_token"]) else {
            throw TokenPanelError.notSignedIn(.codex)
        }
        let accountID = JSONMap.string(tokens["account_id"]) ?? JSONMap.string(root["account_id"])
        let identity = AccountIdentity(
            email: JSONMap.string(root["email"]) ?? jwtEmail(token),
            planLabel: JSONMap.string(root["plan_type"])
        )
        return (token, accountID, identity)
    }

    private static func jwtEmail(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let profile = JSONMap.dict(json["https://api.openai.com/profile"])
        return JSONMap.string(profile?["email"]) ?? JSONMap.string(json["email"])
    }
}

final class CodexUsageClient: UsageFetching, Sendable {
    let provider: ProviderID = .codex
    var isConfigured: Bool { CodexAuthStore.isConfigured }

    static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch() async throws -> UsageSnapshot {
        let (token, accountID, identity) = try CodexAuthStore.load()
        let parsed = try await fetchUsage(token: token, accountID: accountID)
        var merged = parsed.identity
        if merged.email == nil { merged.email = identity.email }
        if merged.planLabel == nil { merged.planLabel = identity.planLabel }
        return UsageSnapshot(
            provider: .codex,
            usedPercent: parsed.usedPercent,
            periodStart: parsed.periodStart,
            resetsAt: parsed.resetsAt,
            features: parsed.features,
            identity: merged,
            source: "chatgpt.com usage",
            fetchedAt: Date()
        )
    }

    private func fetchUsage(token: String, accountID: String?) async throws -> Parsed {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        request.setValue("TokenPanel", forHTTPHeaderField: "User-Agent")
        if let accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

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

        let limits = JSONMap.dict(object["rate_limit"]) ?? object
        let primary = JSONMap.dict(limits["primary_window"])
            ?? JSONMap.dict(limits["primary"])
        let secondary = JSONMap.dict(limits["secondary_window"])
            ?? JSONMap.dict(limits["secondary"])

        func windowFeature(fallbackID: String, node: [String: Any]?) -> (FeatureUsage, Date?)? {
            guard let node,
                  let percent = JSONMap.double(node["used_percent"])
                    ?? JSONMap.double(node["usedPercent"])
                    ?? JSONMap.double(node["utilization"])
            else { return nil }
            let seconds = JSONMap.double(node["limit_window_seconds"])
                ?? JSONMap.double(node["window_minutes"]).map { $0 * 60 }
            let id: String
            let name: String
            if let seconds, seconds <= 6 * 3600 {
                id = "5h"; name = "Session (5h)"
            } else if let seconds, seconds <= 8 * 24 * 3600 {
                id = "week"; name = "Week"
            } else if let seconds, seconds <= 40 * 24 * 3600 {
                id = "month"; name = "Month"
            } else {
                id = fallbackID
                name = FeatureUsage.label(for: fallbackID)
            }
            let reset = JSONMap.date(node["reset_at"])
                ?? JSONMap.date(node["resets_at"])
                ?? JSONMap.date(node["resetsAt"])
            return (FeatureUsage(id: id, percent: percent, name: name), reset)
        }

        var features: [FeatureUsage] = []
        var resets: Date?
        if let (feature, date) = windowFeature(fallbackID: "primary", node: primary) {
            features.append(feature)
            resets = date
        }
        if let (feature, date) = windowFeature(fallbackID: "secondary", node: secondary) {
            features.append(feature)
            if resets == nil { resets = date }
        }

        let used = features.map(\.percent).max()
        guard used != nil || !features.isEmpty else { throw TokenPanelError.parseFailed }

        let plan = JSONMap.string(object["plan_type"]) ?? JSONMap.string(object["planType"])
        let email = JSONMap.string(object["email"])

        return Parsed(
            usedPercent: used,
            periodStart: nil,
            resetsAt: resets,
            features: features,
            identity: AccountIdentity(email: email, planLabel: plan)
        )
    }
}
