import Foundation

/// Lightweight preferences (no Management API key needed for SuperGrok usage).
enum Preferences {
    private static let refreshMinutesKey = "grok.refreshMinutes"
    private static let showMenuBarPercentageKey = "grok.showMenuBarPercentage"
    private static let selectedProviderKey = "tokenpanel.selectedProvider"
    private static let showAllMenuBarProvidersKey = "tokenpanel.showAllMenuBarProviders"

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

    static var isConfigured: Bool {
        GrokAuthStore.isConfigured
            || CursorAuthStore.isConfigured
            || ClaudeAuthStore.isConfigured
            || CodexAuthStore.isConfigured
    }
}
