import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct MenuPanelView: View {
    @Bindable var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        #if os(macOS)
        .frame(width: 340)
        // Tall enough for hero + a few feature rows without scrolling on typical setups.
        .frame(minHeight: 520, idealHeight: 580, maxHeight: 720)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .sheet(isPresented: $viewModel.showingSettings) {
            settingsSheet
        }
    }

    @ViewBuilder
    private var settingsSheet: some View {
        #if os(macOS)
        SettingsView(viewModel: viewModel)
            .frame(width: 440, height: 420)
        #else
        NavigationStack {
            SettingsView(viewModel: viewModel)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { viewModel.showingSettings = false }
                    }
                }
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Grok usage")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
        }
        .padding(14)
    }

    private var subtitle: String {
        if let email = viewModel.snapshot.identity?.email {
            return email
        }
        if let name = viewModel.snapshot.identity?.displayName {
            return name
        }
        if viewModel.snapshot.fetchedAt > .distantPast {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Updated \(formatter.localizedString(for: viewModel.snapshot.fetchedAt, relativeTo: Date()))"
        }
        return "Chat · Voice · Build · Imagine"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.lastError, viewModel.snapshot.usedPercent == nil {
            setupOrError(error)
                .padding(14)
        } else if viewModel.snapshot.usedPercent == nil && !viewModel.isConfigured {
            setupOrError(TokenPanelError.missingCredentials.localizedDescription)
                .padding(14)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = viewModel.lastError {
                        errorBanner(error)
                    }
                    usageHero
                    if !viewModel.snapshot.features.isEmpty {
                        featureBreakdown
                    }
                    metaRows
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Allow the panel to grow; only scroll when content exceeds available height.
            .frame(maxHeight: .infinity)
        }
    }

    private var usageHero: some View {
        let used = viewModel.snapshot.usedPercent ?? 0
        let remaining = viewModel.snapshot.remainingPercent ?? max(0, 100 - used)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.formatPercent(used))
                    .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(usageColor(used))
                Text("used")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.snapshot.cycleLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.formatPercent(remaining) + " left")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: min(max(used, 0), 100), total: 100)
                .tint(usageColor(used))

            if let resets = viewModel.snapshot.resetsAt {
                Text("Resets \(resets.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var featureBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By product")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(viewModel.snapshot.features) { feature in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(feature.name, systemImage: icon(for: feature.id))
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                        Spacer()
                        Text(viewModel.formatPercent(feature.percent))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(max(feature.percent, 0), 100), total: 100)
                        .tint(usageColor(feature.percent))
                        .controlSize(.small)
                }
            }

            Text("Feature labels are best-effort mappings of Grok’s product buckets.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var metaRows: some View {
        VStack(spacing: 6) {
            if let plan = viewModel.snapshot.identity?.loginLabel {
                labeledRow("Plan", plan)
            }
            if let start = viewModel.snapshot.periodStart {
                labeledRow("Period start", start.formatted(date: .abbreviated, time: .omitted))
            }
            if !viewModel.snapshot.source.isEmpty {
                labeledRow("Source", viewModel.snapshot.source)
            }
        }
    }

    private func setupOrError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Grok")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Uses `\(GrokAuthStore.authFileURL().path)` from `grok login`, then loads usage from grok.com.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            #if os(macOS)
            Button("Copy login command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("grok login", forType: .string)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            #endif

            HStack {
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Settings…") {
                    viewModel.showingSettings = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Settings…") {
                viewModel.showingSettings = true
            }
            .buttonStyle(.borderless)

            Spacer()

            Link("Usage", destination: URL(string: "https://grok.com/?_s=usage")!)
                .font(.caption)

            Link("Billing", destination: URL(string: "https://grok.com/?_s=billing")!)
                .font(.caption)

            #if os(macOS)
            Divider()
                .frame(height: 12)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            #endif
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func labeledRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func usageColor(_ percent: Double) -> Color {
        if percent >= 95 { return .red }
        if percent >= 80 { return .orange }
        if percent >= 50 { return .yellow }
        return .green
    }

    private func icon(for featureID: UInt64) -> String {
        switch featureID {
        case 1: return "bubble.left.and.bubble.right"
        case 2: return "waveform"
        case 3: return "photo"
        case 4: return "video"
        case 5: return "magnifyingglass"
        case 6: return "hammer"
        default: return "circle.grid.2x2"
        }
    }
}

#Preview {
    MenuPanelView(viewModel: UsageViewModel())
}
