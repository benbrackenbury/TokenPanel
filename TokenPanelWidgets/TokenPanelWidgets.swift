import AppIntents
import SwiftUI
import WidgetKit

struct UsageWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Usage"
    static var description: IntentDescription = "Show plan usage for one provider or several."

    @Parameter(title: "Grok", default: true)
    var showGrok: Bool

    @Parameter(title: "Cursor", default: true)
    var showCursor: Bool

    @Parameter(title: "Claude", default: true)
    var showClaude: Bool

    @Parameter(title: "Codex", default: true)
    var showCodex: Bool

    var enabledProviders: [ProviderID] {
        var ids: [ProviderID] = []
        if showGrok { ids.append(.grok) }
        if showCursor { ids.append(.cursor) }
        if showClaude { ids.append(.claude) }
        if showCodex { ids.append(.codex) }
        return ids
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let providers: [ProviderID]
    let snapshots: [ProviderID: UsageSnapshot]
    let updatedAt: Date
}

struct UsageTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        sampleEntry(providers: ProviderID.allCases.map { $0 })
    }

    func snapshot(for configuration: UsageWidgetIntent, in context: Context) async -> UsageEntry {
        if context.isPreview {
            return sampleEntry(providers: configuration.enabledProviders)
        }
        return load(configuration)
    }

    func timeline(for configuration: UsageWidgetIntent, in context: Context) async -> Timeline<UsageEntry> {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        return Timeline(entries: [load(configuration)], policy: .after(next))
    }

    private func load(_ configuration: UsageWidgetIntent) -> UsageEntry {
        let payload = WidgetCache.load()
        return UsageEntry(
            date: .now,
            providers: configuration.enabledProviders,
            snapshots: payload.byProvider,
            updatedAt: payload.updatedAt
        )
    }

    func sampleEntry(providers: [ProviderID]) -> UsageEntry {
        let ids = providers.isEmpty ? ProviderID.allCases.map { $0 } : providers
        var snapshots: [ProviderID: UsageSnapshot] = [:]
        let percents: [ProviderID: Double] = [.grok: 42, .cursor: 18, .claude: 27, .codex: 9]
        for id in ids {
            snapshots[id] = UsageSnapshot(
                provider: id,
                usedPercent: percents[id] ?? 20,
                periodStart: nil,
                resetsAt: Calendar.current.date(byAdding: .day, value: 12, to: .now),
                features: [
                    FeatureUsage(id: "sample-a", percent: percents[id] ?? 20, name: "Plan"),
                    FeatureUsage(id: "sample-b", percent: 8, name: "Extra")
                ],
                identity: AccountIdentity(planLabel: "Preview"),
                source: "preview",
                fetchedAt: .now
            )
        }
        return UsageEntry(date: .now, providers: ids, snapshots: snapshots, updatedAt: .now)
    }
}

struct UsageBar: View {
    var percent: Double
    var color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.black.opacity(0.12))
            Capsule()
                .fill(color)
                .scaleEffect(x: min(max(percent, 0), 100) / 100, y: 1, anchor: .leading)
        }
        .frame(height: 6)
    }
}

struct UsageWidgetView: View {
    var entry: UsageEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    private var previewing: Bool { familyOverride != nil }

    var body: some View {
        let tile = content
            .padding(previewing ? 14 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if previewing {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.93, green: 0.93, blue: 0.95))
                }
            }

        Group {
            if previewing {
                tile
            } else {
                tile.containerBackground(.fill.tertiary, for: .widget)
            }
        }
        .widgetURL(URL(string: "tokenpanel://usage"))
    }

    @ViewBuilder
    private var content: some View {
        if visible.isEmpty {
            emptyState
        } else if visible.count == 1, let provider = visible.first {
            single(provider)
        } else {
            multiple
        }
    }

    private var visible: [ProviderID] { entry.providers }
    private var compact: Bool { family == .systemSmall }
    private var roomy: Bool { family == .systemLarge || family == .systemExtraLarge }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TokenPanel")
                .font(.headline)
            Text("Turn on a provider in Edit Widget.")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.55))
        }
    }

    @ViewBuilder
    private func single(_ provider: ProviderID) -> some View {
        let snap = entry.snapshots[provider]
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            header(provider)
            Text(snap?.usedLabel ?? "—")
                .font(.system(size: compact ? 32 : 42, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(usageColor(snap?.usedPercent))
                .minimumScaleFactor(0.5)
            if let used = snap?.usedPercent {
                UsageBar(percent: used, color: usageColor(used))
            }
            if !compact {
                HStack {
                    Text(snap.map { "\($0.formatPercent($0.remainingPercent ?? 0)) left" } ?? "Open TokenPanel")
                    Spacer()
                    if let resets = snap?.resetsAt {
                        Text(resets.formatted(.dateTime.month(.abbreviated).day()))
                    }
                }
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.55))
            }
            if roomy, let features = snap?.features, !features.isEmpty {
                ForEach(features.prefix(family == .systemExtraLarge ? 8 : 5)) { feature in
                    HStack {
                        Text(feature.name)
                        Spacer()
                        Text(snap?.formatPercent(feature.percent) ?? "")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    UsageBar(percent: feature.percent, color: usageColor(feature.percent))
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var multiple: some View {
        let items = Array(visible.prefix(compact ? 4 : 8))
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text("TokenPanel")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.55))
            if compact || family == .systemExtraLarge {
                grid(items, detailed: family == .systemExtraLarge)
            } else {
                ForEach(items, id: \.self) { provider in
                    providerRow(provider)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func grid(_ items: [ProviderID], detailed: Bool) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                HStack(spacing: 12) {
                    providerCell(items[start], detailed: detailed)
                    if start + 1 < items.count {
                        providerCell(items[start + 1], detailed: detailed)
                    } else {
                        Spacer()
                    }
                }
            }
        }
    }

    private func header(_ provider: ProviderID) -> some View {
        HStack(spacing: 6) {
            ProviderLogo(provider: provider, size: compact ? 14 : 16)
            Text(provider.displayName)
                .font(.caption.weight(.semibold))
            Spacer()
            if let cycle = entry.snapshots[provider]?.cycleLabel, !compact {
                Text(cycle)
                    .font(.caption2)
                    .foregroundStyle(.primary.opacity(0.55))
            }
        }
    }

    private func providerRow(_ provider: ProviderID) -> some View {
        let snap = entry.snapshots[provider]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                ProviderLogo(provider: provider, size: 14)
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(snap?.usedLabel ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(usageColor(snap?.usedPercent))
            }
            UsageBar(percent: snap?.usedPercent ?? 0, color: usageColor(snap?.usedPercent))
        }
    }

    private func providerCell(_ provider: ProviderID, detailed: Bool) -> some View {
        let snap = entry.snapshots[provider]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ProviderLogo(provider: provider, size: 12)
                Text(provider.displayName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            Text(snap?.usedLabel ?? "—")
                .font(.headline.monospacedDigit())
                .foregroundStyle(usageColor(snap?.usedPercent))
            if detailed, let used = snap?.usedPercent {
                UsageBar(percent: used, color: usageColor(used))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func usageColor(_ percent: Double?) -> Color {
        guard let percent else { return .gray }
        if percent >= 95 { return Color(red: 0.84, green: 0.22, blue: 0.22) }
        if percent >= 80 { return Color(red: 0.90, green: 0.52, blue: 0.12) }
        if percent >= 50 { return Color(red: 0.82, green: 0.66, blue: 0.08) }
        return Color(red: 0.20, green: 0.62, blue: 0.32)
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TokenPanelUsage", intent: UsageWidgetIntent.self, provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Usage")
        .description("Plan usage for Grok, Cursor, Claude, and Codex. Toggle providers per widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

#if !WIDGET_PREVIEW_RENDER
@main
struct TokenPanelWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}
#endif
