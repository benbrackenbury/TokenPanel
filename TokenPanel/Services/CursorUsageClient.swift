import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

enum CursorAuthStore {
    static func stateDBURL() -> URL {
        LocalHome.realHomeDirectory()
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    static var isConfigured: Bool {
        FileManager.default.fileExists(atPath: stateDBURL().path)
    }

    static func load() throws -> (token: String, email: String?) {
        let url = stateDBURL()
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw TokenPanelError.notSignedIn(.cursor)
        }

        #if canImport(SQLite3)
        var db: OpaquePointer?
        let status = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK, let db else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "sqlite open failed"
            if let db { sqlite3_close(db) }
            throw TokenPanelError.authFileUnreadable(path: path, underlying: message)
        }
        defer { sqlite3_close(db) }

        guard let token = item(key: "cursorAuth/accessToken", db: db), !token.isEmpty else {
            throw TokenPanelError.notSignedIn(.cursor)
        }
        let email = item(key: "cursorAuth/cachedEmail", db: db)
            ?? item(key: "cursorAuth/email", db: db)
        return (token, email)
        #else
        throw TokenPanelError.authFileUnreadable(path: path, underlying: "SQLite is unavailable")
        #endif
    }

    #if canImport(SQLite3)
    private static func item(key: String, db: OpaquePointer) -> String? {
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW, let cString = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: cString)
    }
    #endif
}

final class CursorUsageClient: UsageFetching, Sendable {
    let provider: ProviderID = .cursor
    var isConfigured: Bool { CursorAuthStore.isConfigured }

    static let endpoint = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch() async throws -> UsageSnapshot {
        let (token, email) = try CursorAuthStore.load()
        let parsed = try await fetchUsage(token: token)
        var identity = parsed.identity
        if identity.email == nil {
            identity.email = email
        }
        return UsageSnapshot(
            provider: .cursor,
            usedPercent: parsed.usedPercent,
            periodStart: parsed.periodStart,
            resetsAt: parsed.resetsAt,
            features: parsed.features,
            identity: identity,
            source: "cursor.com usage",
            fetchedAt: Date()
        )
    }

    private func fetchUsage(token: String) async throws -> Parsed {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("TokenPanel", forHTTPHeaderField: "User-Agent")

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

        let plan = JSONMap.dict(object["planUsage"])
            ?? JSONMap.dict(JSONMap.dict(object["individualUsage"])?["plan"])
            ?? object

        let used = JSONMap.double(plan["totalPercentUsed"])
            ?? JSONMap.double(plan["percentUsed"])
        let auto = JSONMap.double(plan["autoPercentUsed"])
        let api = JSONMap.double(plan["apiPercentUsed"])

        var features: [FeatureUsage] = []
        if let auto { features.append(FeatureUsage(id: "auto", percent: auto)) }
        if let api { features.append(FeatureUsage(id: "api", percent: api)) }

        let start = JSONMap.date(object["billingCycleStart"])
            ?? JSONMap.date(plan["startDate"])
        let end = JSONMap.date(object["billingCycleEnd"])
            ?? JSONMap.date(plan["endDate"])

        let membership = JSONMap.string(object["membershipType"])
            ?? JSONMap.string(plan["membershipType"])

        guard used != nil || !features.isEmpty else { throw TokenPanelError.parseFailed }

        return Parsed(
            usedPercent: used,
            periodStart: start,
            resetsAt: end,
            features: features,
            identity: AccountIdentity(planLabel: membership.map { $0.capitalized })
        )
    }
}
