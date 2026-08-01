import Foundation

// MARK: - SuperGrok / Grok consumer usage

struct GrokIdentity: Equatable, Sendable {
    var email: String?
    var displayName: String?
    var teamID: String?
    var principalType: String?
    var authMode: String?
    var expiresAt: Date?

    var loginLabel: String {
        switch authMode?.lowercased() {
        case "oidc": return "SuperGrok"
        case "session": return "Session"
        case .some(let mode): return mode
        case nil: return "Grok"
        }
    }
}

struct FeatureUsage: Identifiable, Equatable, Sendable {
    var id: UInt64
    var percent: Double

    var name: String {
        Self.label(for: id)
    }

    /// Best-effort labels for product buckets returned by GetGrokCreditsConfig.
    /// Unknown IDs fall back to "Feature N" so the UI still works if xAI renumbers.
    static func label(for id: UInt64) -> String {
        switch id {
        case 1: return "Chat"
        case 2: return "Voice"
        case 3: return "Imagine"
        case 4: return "Video"
        case 5: return "DeepSearch"
        case 6: return "Build"
        default: return "Feature \(id)"
        }
    }
}

struct GrokUsageSnapshot: Equatable, Sendable {
    var usedPercent: Double?
    var periodStart: Date?
    var resetsAt: Date?
    var features: [FeatureUsage]
    var identity: GrokIdentity?
    var source: String
    var fetchedAt: Date

    static let empty = GrokUsageSnapshot(
        usedPercent: nil,
        periodStart: nil,
        resetsAt: nil,
        features: [],
        identity: nil,
        source: "",
        fetchedAt: .distantPast
    )

    var remainingPercent: Double? {
        guard let used = usedPercent else { return nil }
        return max(0, 100 - used)
    }

    var cycleLabel: String {
        guard let resetsAt else { return "Credits" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: resetsAt).day ?? 0
        if days >= 25 && days <= 35 { return "Monthly" }
        if days >= 5 && days <= 10 { return "Weekly" }
        return "Credits"
    }
}

enum TokenPanelError: LocalizedError {
    case missingCredentials
    case missingCredentialsDetail(String)
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
            return "No Grok session at \(GrokAuthStore.authFileURL().path). Run `grok login` in Terminal, then refresh."
        case .missingCredentialsDetail(let detail):
            return detail
        case .expiredCredentials:
            return "Grok login expired. Run `grok login` to refresh, then try again."
        case .authFileUnreadable(let path, let underlying):
            return "Can’t read \(path) (\(underlying)). App Sandbox may be blocking ~/.grok — rebuild after disabling it, or pick the file in Settings."
        case .invalidURL:
            return "Could not build the request URL."
        case .http(let status, let body):
            let snippet = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let short = snippet.count > 160 ? String(snippet.prefix(160)) + "…" : snippet
            if status == 401 || status == 403 {
                return "Auth rejected (\(status)). Run `grok login` or sign in at grok.com."
            }
            return "HTTP \(status)\(short.isEmpty ? "" : ": \(short)")"
        case .grpc(let status, let message):
            if status == 16 {
                return "Unauthenticated. Run `grok login` to refresh."
            }
            return "gRPC \(status): \(message.isEmpty ? "request failed" : message)"
        case .emptyResponse:
            return "Empty billing response from grok.com."
        case .parseFailed:
            return "Could not parse Grok usage payload."
        case .transport(let error):
            return error.localizedDescription
        }
    }
}
