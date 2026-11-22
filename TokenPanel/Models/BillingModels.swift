import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum ProviderID: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case grok
    case cursor
    case claude
    case codex
    case antigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grok: return "Grok"
        case .cursor: return "Cursor"
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        }
    }

    var logoName: String {
        switch self {
        case .grok: return "LogoGrok"
        case .cursor: return "LogoCursor"
        case .claude: return "LogoClaude"
        case .codex: return "LogoCodex"
        case .antigravity: return "LogoAntigravity"
        }
    }

    var loginCommand: String {
        switch self {
        case .grok: return "grok login"
        case .cursor: return "Sign in inside Cursor"
        case .claude: return "claude"
        case .codex: return "codex login"
        case .antigravity: return "agy"
        }
    }

    var usageURL: URL {
        switch self {
        case .grok: return URL(string: "https://grok.com/?_s=usage")!
        case .cursor: return URL(string: "https://cursor.com/dashboard?tab=usage")!
        case .claude: return URL(string: "https://claude.ai/settings/usage")!
        case .codex: return URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .antigravity: return URL(string: "https://antigravity.google")!
        }
    }

    var billingURL: URL {
        switch self {
        case .grok: return URL(string: "https://grok.com/?_s=billing")!
        case .cursor: return URL(string: "https://cursor.com/dashboard?tab=billing")!
        case .claude: return URL(string: "https://claude.ai/settings/billing")!
        case .codex: return URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .antigravity: return URL(string: "https://antigravity.google/g1-upgrade")!
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

    /// Grok numeric IDs are `billing_product.Product` from grok.com
    /// (`prod/billing-pub/proto/product.proto`). Unknown IDs keep the raw id.
    static func label(for id: String) -> String {
        switch id {
        case "0": return "3rd party"
        case "1": return "API"
        case "2": return "Grok Build"
        case "3": return "Grok Plugins"
        case "4": return "Chat"
        case "5": return "Imagine"
        case "6": return "Voice"
        case "7": return "App Builder"
        case "8": return "Automations"
        case "9": return "Grok Bot"
        case "10": return "Cursor"
        case "11": return "Bugbot"
        case "5h", "primary": return "Session (5h)"
        case "week", "secondary": return "Week"
        case "month": return "Month"
        case "week-opus": return "Week (Opus)"
        case "week-sonnet": return "Week (Sonnet)"
        case "gemini-5h": return "Gemini (5h)"
        case "gemini-weekly": return "Gemini weekly"
        case "3p-5h": return "Claude/GPT (5h)"
        case "3p-weekly": return "Claude/GPT weekly"
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
        if let start = periodStart, let end = resetsAt {
            let total = end.timeIntervalSince(start)
            if total > 60 {
                switch Self.periodNoun(total: total) {
                case "session": return "Session"
                case "week": return "Weekly"
                case "month": return "Monthly"
                default: break
                }
            }
        }
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

    /// Quota vs how far the current window has run. Linear rate from period start.
    func pace(now: Date = Date()) -> UsagePace? {
        guard let used = usedPercent, let end = resetsAt else { return nil }
        let start: Date
        if let periodStart, end.timeIntervalSince(periodStart) > 60 {
            start = periodStart
        } else if let inferred = inferredPeriodStart(end: end) {
            start = inferred
        } else {
            return nil
        }
        let total = end.timeIntervalSince(start)
        guard total > 60 else { return nil }
        let elapsed = min(max(now.timeIntervalSince(start), 0), total)
        let elapsedPercent = elapsed / total * 100
        let emptyAt: Date? = {
            guard used > 0.05, elapsed > 0 else { return nil }
            return start.addingTimeInterval(elapsed / (used / 100))
        }()
        return UsagePace(
            usedPercent: used,
            elapsedPercent: elapsedPercent,
            start: start,
            end: end,
            emptyAt: emptyAt,
            noun: Self.periodNoun(total: total)
        )
    }

    private func inferredPeriodStart(end: Date) -> Date? {
        let used = usedPercent ?? -1
        let matched = features.first { abs($0.percent - used) < 0.05 }
        let seconds = Self.windowSeconds(for: matched?.id)
            ?? Self.windowSeconds(fromRemaining: end.timeIntervalSinceNow)
        guard let seconds, seconds > 60 else { return nil }
        return end.addingTimeInterval(-seconds)
    }

    static func windowSeconds(for id: String?) -> TimeInterval? {
        switch id {
        case "5h", "gemini-5h", "3p-5h": return 5 * 3600
        case "week", "week-opus", "week-sonnet", "gemini-weekly", "3p-weekly": return 7 * 86400
        case "month": return 30 * 86400
        default: return nil
        }
    }

    // ponytail: remaining-time buckets misread a month with <8d left as a week; prefer periodStart.
    static func windowSeconds(fromRemaining remaining: TimeInterval) -> TimeInterval? {
        guard remaining > 0 else { return nil }
        if remaining <= 6 * 3600 { return 5 * 3600 }
        if remaining <= 8 * 86400 { return 7 * 86400 }
        if remaining <= 40 * 86400 { return 30 * 86400 }
        return nil
    }

    static func periodNoun(total: TimeInterval) -> String {
        if total <= 12 * 3600 { return "session" }
        if total <= 10 * 86400 { return "week" }
        return "month"
    }
}

struct UsagePace: Equatable, Sendable {
    var usedPercent: Double
    var elapsedPercent: Double
    var start: Date
    var end: Date
    var emptyAt: Date?
    var noun: String

    var isHot: Bool { usedPercent > elapsedPercent + 3 }

    func caption(now: Date = Date()) -> String {
        let through = "\(Int(elapsedPercent.rounded()))% through the \(noun)"
        if usedPercent >= 99.5 {
            return "Empty · \(through)"
        }
        if isHot, let emptyAt, emptyAt < end {
            if emptyAt <= now {
                return "Running out now · \(through)"
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Empty \(formatter.localizedString(for: emptyAt, relativeTo: now)) · \(through)"
        }
        return "On track · \(through)"
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
