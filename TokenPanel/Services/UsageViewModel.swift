import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

@Observable
@MainActor
final class UsageViewModel {
    var snapshots: [ProviderID: UsageSnapshot] = [:]
    var errors: [ProviderID: String] = [:]
    var configured: [ProviderID] = []
    var enabledProviders: [ProviderID] = Preferences.enabledOrdered
    var selectedProvider: ProviderID = Preferences.selectedProvider
    var isLoading = false
    var lastError: String?
    var isConfigured = false
    var showingSettings = false
    var showMenuBarPercentage: Bool = Preferences.showMenuBarPercentage
    var showAllMenuBarProviders: Bool = Preferences.showAllMenuBarProviders

    init() {
        if !enabledProviders.contains(selectedProvider), let first = enabledProviders.first {
            selectedProvider = first
            Preferences.selectedProvider = first
        }
    }

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

        let enabled = Set(enabledProviders)
        configured = ProviderID.allCases.filter { id in
            enabled.contains(id) && fetchers.contains { $0.provider == id && $0.isConfigured }
        }

        for id in ProviderID.allCases where !enabled.contains(id) {
            snapshots.removeValue(forKey: id)
            errors.removeValue(forKey: id)
        }

        for fetcher in fetchers where enabled.contains(fetcher.provider) {
            guard fetcher.isConfigured else {
                snapshots.removeValue(forKey: fetcher.provider)
                errors[fetcher.provider] = nil
                continue
            }
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

        WidgetCache.save(snapshots)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    var menuBarProviders: [ProviderID] {
        if showAllMenuBarProviders {
            if !configured.isEmpty { return configured }
            let known = enabledProviders.filter { snapshots[$0] != nil }
            if !known.isEmpty { return known }
            if !enabledProviders.isEmpty { return enabledProviders }
        }
        return [selectedProvider]
    }

    var menuBarSignature: String {
        menuBarProviders.map { "\($0.rawValue):\(menuBarTitle(for: $0))" }.joined(separator: "|")
            + "|\(showMenuBarPercentage)|\(showAllMenuBarProviders)|\(enabledProviders.map(\.rawValue).joined(separator: ","))"
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

    /// nil means every connected provider in the menu bar.
    var menuBarFocus: ProviderID? {
        showAllMenuBarProviders ? nil : selectedProvider
    }

    func setMenuBarFocus(_ provider: ProviderID?) {
        if let provider {
            setShowAllMenuBarProviders(false)
            select(provider)
        } else {
            setShowAllMenuBarProviders(true)
        }
    }

    func isEnabled(_ provider: ProviderID) -> Bool {
        enabledProviders.contains(provider)
    }

    func setEnabled(_ provider: ProviderID, _ enabled: Bool) {
        var next = Set(enabledProviders)
        if enabled {
            next.insert(provider)
        } else if next.count > 1 {
            next.remove(provider)
        } else {
            return
        }
        Preferences.enabledProviders = next
        enabledProviders = ProviderID.allCases.filter { next.contains($0) }
        if !next.contains(selectedProvider), let first = enabledProviders.first {
            select(first)
        }
        Task { await refresh() }
    }

    func formatPercent(_ value: Double) -> String {
        snapshot.formatPercent(value)
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
