import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Reads SuperGrok / Grok Build credentials from `~/.grok/auth.json` (written by `grok login`).
enum GrokAuthStore {
    /// Real user home, not an App Sandbox container home.
    static func realHomeDirectory() -> URL {
        #if canImport(Darwin)
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            let path = String(cString: dir)
            if !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        #endif

        // Fallbacks
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

    static func grokHome(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = env["GROK_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let override = UserDefaults.standard.string(forKey: "grok.authDirectory"),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return realHomeDirectory().appendingPathComponent(".grok", isDirectory: true)
    }

    static func authFileURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = UserDefaults.standard.string(forKey: "grok.authFilePath"),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return grokHome(env: env).appendingPathComponent("auth.json")
    }

    /// Candidate paths tried in order (first readable wins).
    static func candidateAuthURLs(env: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return }
            seen.insert(path)
            urls.append(url)
        }

        add(authFileURL(env: env))

        if let custom = env["GROK_HOME"], !custom.isEmpty {
            add(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent("auth.json"))
        }

        add(realHomeDirectory().appendingPathComponent(".grok/auth.json"))

        if let username = ProcessInfo.processInfo.environment["USER"] ?? ProcessInfo.processInfo.environment["LOGNAME"] {
            add(URL(fileURLWithPath: "/Users/\(username)/.grok/auth.json"))
        }

        // Last resort: NSHomeDirectory (may be container when sandboxed)
        add(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json"))

        return urls
    }

    static func load(env: [String: String] = ProcessInfo.processInfo.environment) throws -> (token: String, identity: GrokIdentity) {
        let fm = FileManager.default
        let candidates = candidateAuthURLs(env: env)

        var lastReadError: (path: String, message: String)?

        for url in candidates {
            let path = url.path
            guard fm.fileExists(atPath: path) else { continue }

            do {
                let data = try Data(contentsOf: url)
                return try parse(data: data)
            } catch let error as TokenPanelError {
                throw error
            } catch {
                lastReadError = (path, error.localizedDescription)
            }
        }

        if let lastReadError {
            throw TokenPanelError.authFileUnreadable(
                path: lastReadError.path,
                underlying: lastReadError.message
            )
        }

        let tried = candidates.map(\.path).joined(separator: "\n• ")
        throw TokenPanelError.missingCredentialsDetail(
            "No auth.json found. Tried:\n• \(tried)\n\nRun `grok login` in Terminal, then refresh."
        )
    }

    static func parse(data: Data) throws -> (token: String, identity: GrokIdentity) {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let root else { throw TokenPanelError.missingCredentials }

        guard let (entry, _) = preferredEntry(in: root) else {
            throw TokenPanelError.missingCredentials
        }
        guard let key = entry["key"] as? String, !key.isEmpty else {
            throw TokenPanelError.missingCredentials
        }

        let identity = GrokIdentity(
            email: entry["email"] as? String,
            displayName: displayName(from: entry),
            teamID: entry["team_id"] as? String,
            principalType: entry["principal_type"] as? String,
            authMode: entry["auth_mode"] as? String,
            expiresAt: parseDate(entry["expires_at"])
        )

        return (key, identity)
    }

    /// Prefer OIDC SuperGrok scope (`https://auth.x.ai::<client-id>`), then legacy session.
    private static func preferredEntry(in root: [String: Any]) -> ([String: Any], String)? {
        var oidc: ([String: Any], String)?
        var legacy: ([String: Any], String)?
        var any: ([String: Any], String)?

        for (scope, value) in root {
            guard let entry = value as? [String: Any],
                  let key = entry["key"] as? String,
                  !key.isEmpty
            else { continue }

            if any == nil { any = (entry, scope) }

            if scope.hasPrefix("https://auth.x.ai::") {
                oidc = (entry, scope)
            } else if scope == "https://accounts.x.ai/sign-in" || scope.contains("/sign-in") {
                legacy = (entry, scope)
            }
        }
        return oidc ?? legacy ?? any
    }

    private static func displayName(from entry: [String: Any]) -> String? {
        let parts = [entry["first_name"] as? String, entry["last_name"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static func parseDate(_ raw: Any?) -> Date? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
