import Foundation
import Observation

@Observable
@MainActor
final class UsageViewModel {
    var snapshot: GrokUsageSnapshot = .empty
    var isLoading = false
    var lastError: String?
    var isConfigured = false
    var showingSettings = false
    /// Mirrored from Preferences so the menu bar label updates live.
    var showMenuBarPercentage: Bool = Preferences.showMenuBarPercentage

    private let client = GrokCreditsClient()
    private var refreshTask: Task<Void, Never>?

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshLoop()
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let (_, identity) = try GrokAuthStore.load()
            isConfigured = true
            var usage = try await client.fetchUsage()
            // Preserve identity even if server payload omits it.
            if usage.identity == nil {
                usage.identity = identity
            }
            if let expires = identity.expiresAt, expires <= Date() {
                lastError = "Session may be expired — if refresh fails, run `grok login`."
            } else {
                lastError = nil
            }
            snapshot = usage
        } catch let error as TokenPanelError {
            switch error {
            case .missingCredentials, .missingCredentialsDetail, .authFileUnreadable:
                isConfigured = false
            default:
                isConfigured = Preferences.isConfigured
            }
            lastError = error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Text shown in the menu bar when percentage display is enabled.
    var menuBarTitle: String {
        if let used = snapshot.usedPercent {
            return "\(Int(used.rounded()))%"
        }
        if isLoading { return "…" }
        if lastError != nil { return "!" }
        return "Grok"
    }

    var menuBarSystemImage: String {
        if !isConfigured { return "person.crop.circle.badge.questionmark" }
        if lastError != nil, snapshot.usedPercent == nil {
            return "exclamationmark.triangle"
        }
        if let used = snapshot.usedPercent {
            if used >= 95 { return "gauge.with.dots.needle.100percent" }
            if used >= 80 { return "gauge.with.dots.needle.67percent" }
            if used >= 40 { return "gauge.with.dots.needle.50percent" }
            return "gauge.with.dots.needle.33percent"
        }
        return "brain.head.profile"
    }

    func setShowMenuBarPercentage(_ value: Bool) {
        Preferences.showMenuBarPercentage = value
        showMenuBarPercentage = value
    }

    func formatPercent(_ value: Double) -> String {
        if value < 1, value > 0 {
            return String(format: "%.1f%%", value)
        }
        return String(format: "%.0f%%", value)
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
