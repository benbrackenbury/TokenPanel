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

            precondition(FeatureUsage.label(for: "1") == "API")
            precondition(FeatureUsage.label(for: "2") == "Grok Build")
            precondition(FeatureUsage.label(for: "4") == "Chat")
            precondition(FeatureUsage.label(for: "5") == "Imagine")
            precondition(FeatureUsage.label(for: "9") == "Grok Bot")
            precondition(FeatureUsage.label(for: "10") == "Cursor")
            precondition(FeatureUsage.label(for: "11") == "Bugbot")
            precondition(FeatureUsage(id: "9", percent: 12).name == "Grok Bot")

            // Weekly Super Limit sample: Grok Bot 12%, Chat 2%, Imagine 2%, Cursor 13%.
            // Voice at 0% is present on the wire and must be omitted from the breakdown.
            let grokFrame = Data([
                0x00, 0x00, 0x00, 0x00, 0x34, 0x0a, 0x32, 0x0d, 0x00, 0x00, 0xe8, 0x41,
                0x3a, 0x07, 0x08, 0x09, 0x15, 0x00, 0x00, 0x40, 0x41, 0x3a, 0x07, 0x08, 0x04,
                0x15, 0x00, 0x00, 0x00, 0x40, 0x3a, 0x07, 0x08, 0x05, 0x15, 0x00, 0x00, 0x00, 0x40,
                0x3a, 0x07, 0x08, 0x0a, 0x15, 0x00, 0x00, 0x50, 0x41, 0x3a, 0x07, 0x08, 0x06,
                0x15, 0x00, 0x00, 0x00, 0x00
            ])
            let g = try GrokCreditsClient.parseResponse(grokFrame)
            precondition(g.usedPercent == 29)
            precondition(Set(g.features.map(\.id)) == ["10", "9", "4", "5"])
            precondition(!g.features.contains(where: { $0.id == "6" }))
            precondition(g.features.first?.name == "Cursor")
            precondition(g.features.contains(where: { $0.name == "Grok Bot" && $0.percent == 12 }))
            precondition(g.features.contains(where: { $0.name == "Chat" && $0.percent == 2 }))
            precondition(g.features.contains(where: { $0.name == "Imagine" && $0.percent == 2 }))

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
