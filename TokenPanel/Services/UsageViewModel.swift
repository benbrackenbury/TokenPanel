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
    private var refreshGeneration = 0

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
        refreshGeneration += 1
        let generation = refreshGeneration
        isLoading = true
        defer {
            if generation == refreshGeneration {
                isLoading = false
            }
        }

        syncEnabledProviders()
        dropDisabledSnapshots()
        updateConfigured()

        for fetcher in fetchers {
            guard generation == refreshGeneration else { return }
            guard enabledProviders.contains(fetcher.provider) else { continue }
            guard fetcher.isConfigured else {
                snapshots.removeValue(forKey: fetcher.provider)
                errors[fetcher.provider] = nil
                continue
            }
            do {
                let snapshot = try await fetcher.fetch()
                guard generation == refreshGeneration else { return }
                guard ProviderRefresh.shouldApplyResult(
                    generation: generation,
                    currentGeneration: refreshGeneration,
                    provider: fetcher.provider,
                    enabled: Set(enabledProviders)
                ) else { continue }
                snapshots[fetcher.provider] = snapshot
                errors[fetcher.provider] = nil
            } catch {
                guard generation == refreshGeneration else { return }
                guard ProviderRefresh.shouldApplyResult(
                    generation: generation,
                    currentGeneration: refreshGeneration,
                    provider: fetcher.provider,
                    enabled: Set(enabledProviders)
                ) else { continue }
                errors[fetcher.provider] = error.localizedDescription
            }
        }

        guard generation == refreshGeneration else { return }

        dropDisabledSnapshots()
        updateConfigured()
        isConfigured = configured.contains(selectedProvider) || snapshots[selectedProvider]?.usedPercent != nil
        if let selectedError = errors[selectedProvider] {
            lastError = selectedError
        } else if !isConfigured {
            lastError = TokenPanelError.notSignedIn(selectedProvider).localizedDescription
        } else {
            lastError = nil
        }

        persistSnapshots()
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
        refreshGeneration += 1
        dropDisabledSnapshots()
        if !next.contains(selectedProvider), let first = enabledProviders.first {
            select(first)
        }
        Task { await refresh() }
    }

    private func syncEnabledProviders() {
        enabledProviders = Preferences.enabledOrdered
        if !enabledProviders.contains(selectedProvider), let first = enabledProviders.first {
            select(first)
        }
    }

    private func dropDisabledSnapshots() {
        var removed = false
        for id in ProviderID.allCases where !enabledProviders.contains(id) {
            if snapshots.removeValue(forKey: id) != nil { removed = true }
            errors.removeValue(forKey: id)
        }
        if removed { persistSnapshots() }
    }

    private func persistSnapshots() {
        WidgetCache.save(snapshots)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func updateConfigured() {
        configured = ProviderID.allCases.filter { id in
            enabledProviders.contains(id) && fetchers.contains { $0.provider == id && $0.isConfigured }
        }
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

enum ProviderRefresh {
    /// Keep a fetch only if this refresh is still current and the provider is still checked.
    static func shouldApplyResult(
        generation: Int,
        currentGeneration: Int,
        provider: ProviderID,
        enabled: Set<ProviderID>
    ) -> Bool {
        generation == currentGeneration && enabled.contains(provider)
    }
}
