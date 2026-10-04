import Foundation

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
