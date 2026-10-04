import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum ProviderID: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
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

struct AccountIdentity: Equatable, Codable, Sendable {
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

struct FeatureUsage: Identifiable, Equatable, Codable, Sendable {
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

struct UsageSnapshot: Equatable, Codable, Sendable {
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

    func formatPercent(_ value: Double) -> String {
        if value < 1, value > 0 {
            return String(format: "%.1f%%", value)
        }
        return String(format: "%.0f%%", value)
    }

    var usedLabel: String {
        guard let usedPercent else { return "—" }
        return formatPercent(usedPercent)
    }
}

typealias GrokUsageSnapshot = UsageSnapshot

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
