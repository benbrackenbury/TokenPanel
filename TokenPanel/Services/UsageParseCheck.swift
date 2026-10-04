import Foundation

enum UsageParseCheck {
    static func run() {
        let cursor = Data(#"{"billingCycleEnd":"2026-11-01T00:00:00Z","planUsage":{"totalPercentUsed":12.5,"autoPercentUsed":4,"apiPercentUsed":8,"membershipType":"pro"}}"#.utf8)
        let claude = Data(#"{"five_hour":{"utilization":22.0,"resets_at":"2026-10-04T18:00:00Z"},"seven_day":{"utilization":41.0,"resets_at":"2026-10-10T12:00:00Z"}}"#.utf8)
        let codex = Data(#"{"plan_type":"plus","email":"a@b.c","rate_limit":{"primary_window":{"used_percent":6,"limit_window_seconds":2592000,"reset_at":1792918655},"secondary_window":null}}"#.utf8)

        do {
            let c = try CursorUsageClient.parse(cursor)
            precondition(c.usedPercent == 12.5 && c.features.count == 2)
            let a = try ClaudeUsageClient.parse(claude)
            precondition(a.usedPercent == 22 && a.features.contains(where: { $0.id == "week" }))
            let x = try CodexUsageClient.parse(codex)
            precondition(x.usedPercent == 6 && x.features.first?.id == "month" && x.identity.email == "a@b.c")

            let snapshot = UsageSnapshot(
                provider: .cursor,
                usedPercent: c.usedPercent,
                periodStart: c.periodStart,
                resetsAt: c.resetsAt,
                features: c.features,
                identity: c.identity,
                source: "check",
                fetchedAt: Date()
            )
            let roundtrip = try JSONDecoder().decode(
                UsageSnapshot.self,
                from: try JSONEncoder().encode(snapshot)
            )
            precondition(roundtrip.usedPercent == 12.5 && roundtrip.provider == .cursor)
        } catch {
            assertionFailure("usage parse check failed: \(error)")
        }
    }
}
