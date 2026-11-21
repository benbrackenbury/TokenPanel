import Foundation

/// Lightweight preferences (no Management API key needed for SuperGrok usage).
enum Preferences {
    private static let refreshMinutesKey = "grok.refreshMinutes"
    private static let showMenuBarPercentageKey = "grok.showMenuBarPercentage"
    private static let selectedProviderKey = "tokenpanel.selectedProvider"
    private static let showAllMenuBarProvidersKey = "tokenpanel.showAllMenuBarProviders"
    private static let enabledProvidersKey = "tokenpanel.enabledProviders"

    static var refreshMinutes: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: refreshMinutesKey)
            return value > 0 ? value : 5
        }
        set { UserDefaults.standard.set(max(1, newValue), forKey: refreshMinutesKey) }
    }

    /// When true, menu bar shows e.g. "75%" next to the icon.
    static var showMenuBarPercentage: Bool {
        get {
            if UserDefaults.standard.object(forKey: showMenuBarPercentageKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showMenuBarPercentageKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showMenuBarPercentageKey) }
    }

    static var showAllMenuBarProviders: Bool {
        get { UserDefaults.standard.bool(forKey: showAllMenuBarProvidersKey) }
        set { UserDefaults.standard.set(newValue, forKey: showAllMenuBarProvidersKey) }
    }

    static var selectedProvider: ProviderID {
        get {
            if let raw = UserDefaults.standard.string(forKey: selectedProviderKey),
               let value = ProviderID(rawValue: raw) {
                return value
            }
            return .grok
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selectedProviderKey) }
    }

    /// Missing key follows local sessions. Empty stored list stays empty.
    static var enabledProviders: Set<ProviderID> {
        get {
            let stored = UserDefaults.standard.array(forKey: enabledProvidersKey) as? [String]
            return resolveEnabledProviders(stored: stored, signedIn: signedInProviders)
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue), forKey: enabledProvidersKey)
        }
    }

    static func resolveEnabledProviders(stored: [String]?, signedIn: Set<ProviderID>) -> Set<ProviderID> {
        guard let stored else {
            return signedIn.isEmpty ? Set(ProviderID.allCases) : signedIn
        }
        return Set(stored.compactMap(ProviderID.init(rawValue:)))
    }

    static var enabledOrdered: [ProviderID] {
        ProviderID.allCases.filter { enabledProviders.contains($0) }
    }

    static var isConfigured: Bool { !signedInProviders.isEmpty }

    private static var signedInProviders: Set<ProviderID> {
        var ids: Set<ProviderID> = []
        if GrokAuthStore.isConfigured { ids.insert(.grok) }
        if CursorAuthStore.isConfigured { ids.insert(.cursor) }
        if ClaudeAuthStore.isConfigured { ids.insert(.claude) }
        if CodexAuthStore.isConfigured { ids.insert(.codex) }
        if AntigravityAuthStore.isConfigured { ids.insert(.antigravity) }
        return ids
    }
}
