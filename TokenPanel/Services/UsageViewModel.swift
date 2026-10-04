import Foundation
import Observation

@Observable
@MainActor
final class UsageViewModel {
    var snapshots: [ProviderID: UsageSnapshot] = [:]
    var errors: [ProviderID: String] = [:]
    var configured: [ProviderID] = []
    var selectedProvider: ProviderID = Preferences.selectedProvider
    var isLoading = false
    var lastError: String?
    var isConfigured = false
    var showingSettings = false
    var showMenuBarPercentage: Bool = Preferences.showMenuBarPercentage
    var showAllMenuBarProviders: Bool = Preferences.showAllMenuBarProviders

    private let fetchers: [any UsageFetching] = [
        GrokCreditsClient(),
        CursorUsageClient(),
        ClaudeUsageClient(),
        CodexUsageClient()
    ]
    private var refreshTask: Task<Void, Never>?

    var snapshot: UsageSnapshot {
        snapshots[selectedProvider] ?? .empty(selectedProvider)
    }

    func start() {
        #if DEBUG
        UsageParseCheck.run()
        #endif
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshLoop()
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func select(_ provider: ProviderID) {
        selectedProvider = provider
        Preferences.selectedProvider = provider
        lastError = errors[provider]
        isConfigured = configured.contains(provider) || snapshots[provider] != nil
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        configured = ProviderID.allCases.filter { id in
            fetchers.contains { $0.provider == id && $0.isConfigured }
        }

        for fetcher in fetchers where fetcher.isConfigured {
            do {
                snapshots[fetcher.provider] = try await fetcher.fetch()
                errors[fetcher.provider] = nil
            } catch {
                errors[fetcher.provider] = error.localizedDescription
            }
        }

        isConfigured = configured.contains(selectedProvider) || snapshots[selectedProvider]?.usedPercent != nil
        if let selectedError = errors[selectedProvider] {
            lastError = selectedError
        } else if !isConfigured {
            lastError = TokenPanelError.notSignedIn(selectedProvider).localizedDescription
        } else {
            lastError = nil
        }
    }

    var menuBarProviders: [ProviderID] {
        if showAllMenuBarProviders {
            if !configured.isEmpty { return configured }
            let known = ProviderID.allCases.filter { snapshots[$0] != nil }
            if !known.isEmpty { return known }
        }
        return [selectedProvider]
    }

    var menuBarSignature: String {
        menuBarProviders.map { "\($0.rawValue):\(menuBarTitle(for: $0))" }.joined(separator: "|")
            + "|\(showMenuBarPercentage)|\(showAllMenuBarProviders)"
    }

    var menuBarTitle: String {
        menuBarTitle(for: selectedProvider)
    }

    func menuBarTitle(for provider: ProviderID) -> String {
        if let used = snapshots[provider]?.usedPercent {
            return "\(Int(used.rounded()))%"
        }
        if isLoading { return "…" }
        if errors[provider] != nil { return "!" }
        return ""
    }

    func setShowMenuBarPercentage(_ value: Bool) {
        Preferences.showMenuBarPercentage = value
        showMenuBarPercentage = value
    }

    func setShowAllMenuBarProviders(_ value: Bool) {
        Preferences.showAllMenuBarProviders = value
        showAllMenuBarProviders = value
    }

    func formatPercent(_ value: Double) -> String {
        if value < 1, value > 0 {
            return String(format: "%.1f%%", value)
        }
        return String(format: "%.0f%%", value)
    }

    func authPath(for provider: ProviderID) -> String {
        switch provider {
        case .grok: return GrokAuthStore.authFileURL().path
        case .cursor: return CursorAuthStore.stateDBURL().path
        case .claude: return ClaudeAuthStore.credentialsFileURL().path
        case .codex: return CodexAuthStore.authFileURL().path
        }
    }

    private func refreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            let seconds = UInt64(max(1, Preferences.refreshMinutes) * 60)
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { break }
            await refresh()
        }
    }
}
