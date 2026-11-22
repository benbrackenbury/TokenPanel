import Foundation

enum UsageParseCheck {
    static func run() {
        let cursor = Data(#"{"billingCycleEnd":"2026-11-01T00:00:00Z","planUsage":{"totalPercentUsed":12.5,"autoPercentUsed":4,"apiPercentUsed":8,"membershipType":"pro"}}"#.utf8)
        let claude = Data(#"{"five_hour":{"utilization":22.0,"resets_at":"2026-10-04T18:00:00Z"},"seven_day":{"utilization":41.0,"resets_at":"2026-10-10T12:00:00Z"}}"#.utf8)
        let codex = Data(#"{"plan_type":"plus","email":"a@b.c","rate_limit":{"primary_window":{"used_percent":6,"limit_window_seconds":2592000,"reset_at":1792918655},"secondary_window":null}}"#.utf8)
        let antigravity = Data(#"{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","remainingFraction":1,"resetTime":"2026-11-28T11:48:09Z"}]},{"displayName":"Claude and GPT models","buckets":[{"bucketId":"3p-weekly","remainingFraction":0.966869,"resetTime":"2026-11-28T11:44:46Z"},{"bucketId":"3p-5h","remainingFraction":0.5,"resetTime":"2026-11-21T16:44:46Z"}]}]}"#.utf8)

        do {
            let c = try CursorUsageClient.parse(cursor)
            precondition(c.usedPercent == 12.5 && c.features.count == 2)
            let a = try ClaudeUsageClient.parse(claude)
            precondition(a.usedPercent == 22 && a.features.contains(where: { $0.id == "week" }))
            let x = try CodexUsageClient.parse(codex)
            precondition(x.usedPercent == 6 && x.features.first?.id == "month" && x.identity.email == "a@b.c")
            let ag = try AntigravityUsageClient.parse(antigravity)
            precondition(abs((ag.usedPercent ?? 0) - 50) < 0.01)
            precondition(ag.features.contains(where: { $0.id == "3p-weekly" && abs($0.percent - 3.3131) < 0.01 }))
            precondition(ag.features.contains(where: { $0.id == "gemini-weekly" && $0.percent == 0 }))
            precondition(FeatureUsage.label(for: "gemini-weekly") == "Gemini weekly")
            precondition(FeatureUsage.label(for: "3p-5h") == "Claude/GPT (5h)")
            let creds = try AntigravityAuthStore.parse(Data(#"{"id_token_email":"a@b.c","token":{"access_token":"ya29.abc","expiry":"2026-11-21T12:43:15.390132Z"}}"#.utf8))
            precondition(creds.accessToken == "ya29.abc" && creds.identity.email == "a@b.c")
            let keyring = try AntigravityAuthStore.parse(Data("go-keyring-base64:eyJhY2Nlc3NfdG9rZW4iOiJhZ3ktdG9rZW4ifQ==".utf8))
            precondition(keyring.accessToken == "agy-token")
            let cli = try AntigravityUsageClient.parse(Data(#"{"command":{"name":"usage","data":{"groups":[{"buckets":[{"id":"gemini-weekly","remaining_fraction":1}]}]}}}"#.utf8))
            precondition(cli.features.first?.id == "gemini-weekly" && cli.usedPercent == 0)
            let split = try AntigravityUsageClient.parse(Data(#"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":0.9},{"bucketId":"3p-5h","remainingFraction":0}]}]}"#.utf8))
            precondition(abs((split.usedPercent ?? 0) - 100) < 0.01)

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

            let weekStart = Date(timeIntervalSince1970: 1_700_000_000)
            let weekEnd = weekStart.addingTimeInterval(7 * 86400)
            let day1 = weekStart.addingTimeInterval(86400)
            let hot = UsageSnapshot(
                provider: .grok,
                usedPercent: 30,
                periodStart: weekStart,
                resetsAt: weekEnd,
                features: [FeatureUsage(id: "4", percent: 30, name: "Chat")],
                identity: nil,
                source: "check",
                fetchedAt: day1
            )
            let hotPace = hot.pace(now: day1)
            precondition(hotPace != nil)
            precondition(abs((hotPace?.elapsedPercent ?? 0) - (100 / 7)) < 0.2)
            precondition(hotPace?.isHot == true)
            precondition((hotPace?.emptyAt ?? weekEnd) < weekEnd)
            precondition(hotPace?.noun == "week")
            let ok = UsageSnapshot(
                provider: .grok,
                usedPercent: 10,
                periodStart: weekStart,
                resetsAt: weekEnd,
                features: [],
                identity: nil,
                source: "check",
                fetchedAt: day1
            )
            precondition(ok.pace(now: day1)?.isHot == false)
            let claudeWeek = UsageSnapshot(
                provider: .claude,
                usedPercent: 22,
                periodStart: nil,
                resetsAt: day1.addingTimeInterval(4 * 3600),
                features: [FeatureUsage(id: "5h", percent: 22)],
                identity: nil,
                source: "check",
                fetchedAt: day1
            )
            precondition(claudeWeek.pace(now: day1)?.noun == "session")

            precondition(Preferences.resolveEnabledProviders(stored: nil, signedIn: [.grok, .cursor]) == Set([.grok, .cursor]))
            precondition(Preferences.resolveEnabledProviders(stored: nil, signedIn: []) == Set(ProviderID.allCases))
            precondition(Preferences.resolveEnabledProviders(stored: ["codex"], signedIn: [.grok]) == Set([.codex]))
            precondition(Preferences.resolveEnabledProviders(stored: [], signedIn: [.grok]).isEmpty)
            // Unset pref follows a session that appears later; an explicit list does not.
            precondition(Preferences.resolveEnabledProviders(stored: nil, signedIn: [.grok]) == Set([.grok]))
            precondition(Preferences.resolveEnabledProviders(stored: nil, signedIn: [.grok, .codex]) == Set([.grok, .codex]))
            precondition(Preferences.resolveEnabledProviders(stored: ["grok"], signedIn: [.grok, .codex]) == Set([.grok]))

            let enabledMidRefresh: Set<ProviderID> = [.grok]
            precondition(ProviderRefresh.shouldApplyResult(
                generation: 1, currentGeneration: 1, provider: .grok, enabled: [.grok, .cursor]
            ))
            precondition(!ProviderRefresh.shouldApplyResult(
                generation: 1, currentGeneration: 2, provider: .cursor, enabled: [.grok, .cursor]
            ))
            precondition(!ProviderRefresh.shouldApplyResult(
                generation: 2, currentGeneration: 2, provider: .cursor, enabled: enabledMidRefresh
            ))
        } catch {
            assertionFailure("usage parse check failed: \(error)")
        }
    }
}
