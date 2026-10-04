import Foundation

enum WidgetCache {
    static let appGroupID = "group.devplaceholder.P74EYVEP.TokenPanel"
    private static let key = "tokenpanel.widget.snapshots"

    struct Payload: Codable, Equatable {
        var updatedAt: Date
        var snapshots: [String: UsageSnapshot]

        var byProvider: [ProviderID: UsageSnapshot] {
            var result: [ProviderID: UsageSnapshot] = [:]
            for (raw, snapshot) in snapshots {
                if let id = ProviderID(rawValue: raw) {
                    result[id] = snapshot
                }
            }
            return result
        }
    }

    static func save(_ snapshots: [ProviderID: UsageSnapshot]) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        var encoded: [String: UsageSnapshot] = [:]
        for (id, snapshot) in snapshots {
            encoded[id.rawValue] = snapshot
        }
        let payload = Payload(updatedAt: Date(), snapshots: encoded)
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: key)
        }
    }

    static func load() -> Payload {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return Payload(updatedAt: .distantPast, snapshots: [:])
        }
        return payload
    }
}
