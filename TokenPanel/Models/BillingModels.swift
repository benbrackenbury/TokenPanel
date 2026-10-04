import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum ProviderID: String, CaseIterable, Identifiable, Codable, Sendable {
    case grok
    case cursor
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grok: return "Grok"
        case .cursor: return "Cursor"
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    var logoName: String {
        switch self {
        case .grok: return "LogoGrok"
        case .cursor: return "LogoCursor"
        case .claude: return "LogoClaude"
        case .codex: return "LogoCodex"
        }
    }

    var loginCommand: String {
        switch self {
        case .grok: return "grok login"
        case .cursor: return "Sign in inside Cursor"
        case .claude: return "claude"
        case .codex: return "codex login"
        }
    }

    var usageURL: URL {
        switch self {
        case .grok: return URL(string: "https://grok.com/?_s=usage")!
        case .cursor: return URL(string: "https://cursor.com/dashboard?tab=usage")!
        case .claude: return URL(string: "https://claude.ai/settings/usage")!
        case .codex: return URL(string: "https://chatgpt.com/codex/settings/usage")!
        }
    }

    var billingURL: URL {
        switch self {
        case .grok: return URL(string: "https://grok.com/?_s=billing")!
        case .cursor: return URL(string: "https://cursor.com/dashboard?tab=billing")!
        case .claude: return URL(string: "https://claude.ai/settings/billing")!
        case .codex: return URL(string: "https://chatgpt.com/codex/settings/usage")!
        }
    }
}

protocol UsageFetching: Sendable {
    var provider: ProviderID { get }
    var isConfigured: Bool { get }
    func fetch() async throws -> UsageSnapshot
}

struct AccountIdentity: Equatable, Sendable {
    var email: String? = nil
    var displayName: String? = nil
    var teamID: String? = nil
    var principalType: String? = nil
    var authMode: String? = nil
    var expiresAt: Date? = nil
    var planLabel: String? = nil

    var loginLabel: String {
        if let planLabel, !planLabel.isEmpty { return planLabel }
        switch authMode?.lowercased() {
        case "oidc": return "SuperGrok"
        case "session": return "Session"
        case .some(let mode): return mode
        case nil: return "Account"
        }
    }
}

typealias GrokIdentity = AccountIdentity

struct FeatureUsage: Identifiable, Equatable, Sendable {
    var id: String
    var percent: Double
    var name: String

    init(id: String, percent: Double, name: String? = nil) {
        self.id = id
        self.percent = percent
        self.name = name ?? Self.label(for: id)
    }

    static func label(for id: String) -> String {
        switch id {
        case "1": return "Chat"
        case "2": return "Voice"
        case "3": return "Imagine"
        case "4": return "Video"
        case "5": return "DeepSearch"
        case "6": return "Build"
        case "5h", "primary": return "Session (5h)"
        case "week", "secondary": return "Week"
        case "month": return "Month"
        case "week-opus": return "Week (Opus)"
        case "week-sonnet": return "Week (Sonnet)"
        case "auto": return "Auto"
        case "api": return "API"
        default: return id
        }
    }
}

struct UsageSnapshot: Equatable, Sendable {
    var provider: ProviderID
    var usedPercent: Double?
    var periodStart: Date?
    var resetsAt: Date?
    var features: [FeatureUsage]
    var identity: AccountIdentity?
    var source: String
    var fetchedAt: Date

    static func empty(_ provider: ProviderID = .grok) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            usedPercent: nil,
            periodStart: nil,
            resetsAt: nil,
            features: [],
            identity: nil,
            source: "",
            fetchedAt: .distantPast
        )
    }

    var remainingPercent: Double? {
        guard let used = usedPercent else { return nil }
        return max(0, 100 - used)
    }

    var cycleLabel: String {
        guard let resetsAt else { return "Credits" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: resetsAt).day ?? 0
        if days >= 25 && days <= 35 { return "Monthly" }
        if days >= 5 && days <= 10 { return "Weekly" }
        if days == 0 { return "Resets today" }
        return "Credits"
    }
}

typealias GrokUsageSnapshot = UsageSnapshot

enum TokenPanelError: LocalizedError {
    case missingCredentials
    case missingCredentialsDetail(String)
    case notSignedIn(ProviderID)
    case expiredCredentials
    case authFileUnreadable(path: String, underlying: String)
    case invalidURL
    case http(status: Int, body: String)
    case grpc(status: Int, message: String)
    case emptyResponse
    case parseFailed
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return TokenPanelError.notSignedIn(.grok).errorDescription
        case .missingCredentialsDetail(let detail):
            return detail
        case .notSignedIn(let provider):
            switch provider {
            case .grok:
                return "No Grok session at \(GrokAuthStore.authFileURL().path). Run `grok login` in Terminal, then refresh."
            case .cursor:
                return "No Cursor session. Sign in inside Cursor, then refresh."
            case .claude:
                return "No Claude Code session. Run `claude` once to log in, then refresh."
            case .codex:
                return "No Codex session at \(CodexAuthStore.authFileURL().path). Run `codex login`, then refresh."
            }
        case .expiredCredentials:
            return "Login expired. Sign in again in that product, then refresh."
        case .authFileUnreadable(let path, let underlying):
            return "Can’t read \(path) (\(underlying))."
        case .invalidURL:
            return "Could not build the request URL."
        case .http(let status, let body):
            let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let short = snippet.count > 160 ? String(snippet.prefix(160)) + "…" : snippet
            if status == 401 || status == 403 {
                return "Auth rejected (\(status)). Sign in again, then refresh."
            }
            return "HTTP \(status)\(short.isEmpty ? "" : ": \(short)")"
        case .grpc(let status, let message):
            if status == 16 {
                return "Unauthenticated. Run `grok login` to refresh."
            }
            return "gRPC \(status): \(message.isEmpty ? "request failed" : message)"
        case .emptyResponse:
            return "Empty usage response."
        case .parseFailed:
            return "Could not parse usage payload."
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

enum JSONMap {
    static func dict(_ any: Any?) -> [String: Any]? { any as? [String: Any] }

    static func double(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        if let value = any as? String { return Double(value) }
        return nil
    }

    static func string(_ any: Any?) -> String? {
        if let value = any as? String, !value.isEmpty { return value }
        return nil
    }

    static func date(_ any: Any?) -> Date? {
        if let seconds = double(any), seconds > 1_000_000_000 {
            let value = seconds > 10_000_000_000 ? seconds / 1000 : seconds
            return Date(timeIntervalSince1970: value)
        }
        guard let raw = string(any) else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) { return date }
        return try? Date(raw, strategy: .iso8601)
    }
}

enum LocalHome {
    static func realHomeDirectory() -> URL {
        #if canImport(Darwin)
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            let path = String(cString: dir)
            if !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        #endif

        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty,
           !home.contains("/Library/Containers/") {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        if let username = ProcessInfo.processInfo.environment["USER"] ?? ProcessInfo.processInfo.environment["LOGNAME"],
           !username.isEmpty {
            let url = URL(fileURLWithPath: "/Users/\(username)", isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
