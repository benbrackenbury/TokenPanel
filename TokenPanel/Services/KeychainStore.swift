import Foundation

/// Lightweight preferences (no Management API key needed for SuperGrok usage).
enum Preferences {
    private static let refreshMinutesKey = "grok.refreshMinutes"
    private static let showMenuBarPercentageKey = "grok.showMenuBarPercentage"

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

    static var isConfigured: Bool {
        (try? GrokAuthStore.load()) != nil
    }
}
