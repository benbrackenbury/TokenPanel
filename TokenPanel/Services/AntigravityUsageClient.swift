import Foundation

enum AntigravityAuthStore {
    static func credentialsFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["ANTIGRAVITY_OAUTH_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return LocalHome.realHomeDirectory().appendingPathComponent(".gemini/oauth_creds.json")
    }

    /// File from `agy` / Gemini, or the `agy` binary (it owns the Keychain item).
    /// Do not `SecItemCopyMatching` service "gemini" — TokenPanel is a different
    /// binary, so macOS prompts for the login password on every read.
    static var isConfigured: Bool {
        FileManager.default.fileExists(atPath: credentialsFileURL().path)
            || AntigravityUsageClient.agyExecutable() != nil
    }

    struct Credentials {
        var accessToken: String
        var expiry: Date?
        var identity: AccountIdentity

        var hasUsableAccessToken: Bool {
            guard !accessToken.isEmpty else { return false }
            guard let expiry else { return true }
            return expiry.timeIntervalSinceNow > 60
        }
    }

    static func load() throws -> Credentials {
        let url = credentialsFileURL()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) {
                throw TokenPanelError.notSignedIn(.antigravity)
            }
            throw TokenPanelError.authFileUnreadable(path: url.path, underlying: error.localizedDescription)
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> Credentials {
        let decoded = decodeKeyring(data) ?? data
        guard let root = try JSONSerialization.jsonObject(with: decoded) as? [String: Any] else {
            throw TokenPanelError.notSignedIn(.antigravity)
        }
        let token = JSONMap.dict(root["token"]) ?? root
        guard let access = JSONMap.string(token["access_token"]) ?? JSONMap.string(root["access_token"]),
              !access.isEmpty
        else {
            throw TokenPanelError.notSignedIn(.antigravity)
        }
        return Credentials(
            accessToken: access,
            expiry: JSONMap.date(token["expiry"]) ?? JSONMap.date(root["expiry"]),
            identity: AccountIdentity(
                email: JSONMap.string(root["id_token_email"])
                    ?? JSONMap.string(root["email"])
                    ?? JSONMap.string(token["email"]),
                planLabel: JSONMap.string(root["auth_method"])
            )
        )
    }

    private static func decodeKeyring(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("go-keyring-base64:") else { return nil }
        return Data(base64Encoded: String(trimmed.dropFirst("go-keyring-base64:".count)))
    }
}

final class AntigravityUsageClient: UsageFetching, Sendable {
    let provider: ProviderID = .antigravity
    var isConfigured: Bool { AntigravityAuthStore.isConfigured }

    static let hosts = [
        "https://daily-cloudcode-pa.googleapis.com",
        "https://cloudcode-pa.googleapis.com"
    ]

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch() async throws -> UsageSnapshot {
        let creds = try? AntigravityAuthStore.load()
        if let creds, creds.hasUsableAccessToken {
            do {
                return try await snapshot(from: try await fetchUsage(token: creds.accessToken), creds: creds, source: "antigravity quota")
            } catch {
                // Expired or rejected token: ask `agy` to refresh via /usage.
            }
        }
        return try await snapshotFromCLI(creds: creds)
    }

    private func snapshot(from parsed: Parsed, creds: AntigravityAuthStore.Credentials?, source: String) -> UsageSnapshot {
        var merged = parsed.identity
        if merged.email == nil { merged.email = creds?.identity.email }
        if merged.planLabel == nil || merged.planLabel == "consumer" {
            merged.planLabel = parsed.identity.planLabel ?? creds?.identity.planLabel
        }
        return UsageSnapshot(
            provider: .antigravity,
            usedPercent: parsed.usedPercent,
            periodStart: parsed.periodStart,
            resetsAt: parsed.resetsAt,
            features: parsed.features,
            identity: merged,
            source: source,
            fetchedAt: Date()
        )
    }

    private func snapshotFromCLI(creds: AntigravityAuthStore.Credentials?) async throws -> UsageSnapshot {
        guard let agy = Self.agyExecutable() else {
            throw creds == nil ? TokenPanelError.notSignedIn(.antigravity) : TokenPanelError.expiredCredentials
        }
        let data = try await runAgyUsage(agy)
        return snapshot(from: try Self.parse(data), creds: creds, source: "agy /usage")
    }

    private func fetchUsage(token: String) async throws -> Parsed {
        var lastError: Error = TokenPanelError.parseFailed
        for host in Self.hosts {
            do {
                let assist = try await post(
                    host: host,
                    path: "/v1internal:loadCodeAssist",
                    body: ["metadata": ["ideType": "ANTIGRAVITY"]],
                    token: token
                )
                let project = JSONMap.string(assist["cloudaicompanionProject"])
                var summaryBody: [String: Any] = [:]
                if let project { summaryBody["project"] = project }
                let summary = try await post(
                    host: host,
                    path: "/v1internal:retrieveUserQuotaSummary",
                    body: summaryBody,
                    token: token
                )
                var parsed = try Self.parse(try JSONSerialization.data(withJSONObject: summary))
                if parsed.identity.planLabel == nil {
                    let paid = JSONMap.dict(assist["paidTier"])
                    parsed.identity.planLabel = JSONMap.string(paid?["name"])
                        ?? JSONMap.string(JSONMap.dict(assist["currentTier"])?["name"])
                }
                return parsed
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func post(host: String, path: String, body: [String: Any], token: String) async throws -> [String: Any] {
        guard let url = URL(string: host + path) else { throw TokenPanelError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

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
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TokenPanelError.parseFailed
        }
        return object
    }

    private static var userAgent: String {
        #if arch(arm64)
        return "antigravity/hub/2.9.1 darwin/arm64"
        #else
        return "antigravity/hub/2.9.1 darwin/amd64"
        #endif
    }

    static func agyExecutable() -> URL? {
        if let override = ProcessInfo.processInfo.environment["ANTIGRAVITY_CLI_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        let home = LocalHome.realHomeDirectory()
        let candidates = [
            home.appendingPathComponent(".local/bin/agy"),
            URL(fileURLWithPath: "/opt/homebrew/bin/agy"),
            URL(fileURLWithPath: "/usr/local/bin/agy")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func runAgyUsage(_ agy: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = agy
                process.arguments = ["-p", "/usage", "--output-format", "json", "--print-timeout", "60s"]
                var env = ProcessInfo.processInfo.environment
                env["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
                env["BROWSER"] = "/usr/bin/false"
                process.environment = env
                process.currentDirectoryURL = FileManager.default.temporaryDirectory
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: TokenPanelError.transport(error))
                    return
                }
                let outBox = DataBox()
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    outBox.data = stdout.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                process.waitUntilExit()
                group.wait()
                if process.terminationStatus != 0 {
                    let err = String(data: errBox.data.prefix(200), encoding: .utf8) ?? ""
                    continuation.resume(throwing: TokenPanelError.http(status: Int(process.terminationStatus), body: err))
                    return
                }
                continuation.resume(returning: outBox.data)
            }
        }
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
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
        let envelope = JSONMap.dict(JSONMap.dict(object["command"])?["data"])
            ?? JSONMap.dict(object["response"])
            ?? object
        let groups = envelope["groups"] as? [[String: Any]] ?? []

        var features: [FeatureUsage] = []
        var resetsByID: [String: Date] = [:]
        for group in groups {
            let buckets = group["buckets"] as? [[String: Any]] ?? []
            for bucket in buckets {
                let remaining = JSONMap.double(bucket["remainingFraction"])
                    ?? JSONMap.double(bucket["remaining_fraction"])
                guard let remaining else { continue }
                let fraction = remaining > 1 ? remaining / 100 : remaining
                let used = max(0, min(100, (1 - fraction) * 100))
                let id = JSONMap.string(bucket["bucketId"])
                    ?? JSONMap.string(bucket["id"])
                    ?? JSONMap.string(bucket["window"])
                    ?? "quota"
                features.append(FeatureUsage(id: id, percent: used, name: FeatureUsage.label(for: id)))
                if let reset = JSONMap.date(bucket["resetTime"]) ?? JSONMap.date(bucket["reset_time"]) {
                    resetsByID[id] = reset
                }
            }
        }

        guard !features.isEmpty else { throw TokenPanelError.parseFailed }

        let fiveHour = features.filter { $0.id.hasSuffix("-5h") || $0.id == "5h" }
        let headline = fiveHour.max(by: { $0.percent < $1.percent })
            ?? features.max(by: { $0.percent < $1.percent })
        let used = headline?.percent
        let resets = headline.flatMap { resetsByID[$0.id] } ?? resetsByID.values.min()

        return Parsed(
            usedPercent: used,
            periodStart: nil,
            resetsAt: resets,
            features: features,
            identity: AccountIdentity()
        )
    }
}
