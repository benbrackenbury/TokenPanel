import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    @Bindable var viewModel: UsageViewModel
    @Bindable var updater: AppUpdater
    @State private var refreshMinutes: Int = 5
    @State private var showMenuBarPercentage: Bool = true
    @State private var statusMessage: String?
    @State private var grokAuthPath: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    viewModel.showingSettings = false
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            #endif

            Form {
                Section("Menu bar") {
                    Picker("Show usage for", selection: Binding(
                        get: { viewModel.selectedProvider },
                        set: { viewModel.select($0) }
                    )) {
                        ForEach(ProviderID.allCases) { provider in
                            Label {
                                Text(provider.displayName)
                            } icon: {
                                ProviderLogo(provider: provider, size: 14)
                            }
                            .tag(provider)
                        }
                    }

                    Stepper(value: $refreshMinutes, in: 1...60) {
                        Text("Refresh every \(refreshMinutes) min")
                    }

                    Toggle("Show all providers in menu bar", isOn: Binding(
                        get: { viewModel.showAllMenuBarProviders },
                        set: { viewModel.setShowAllMenuBarProviders($0) }
                    ))

                    Toggle("Show percentage in menu bar", isOn: $showMenuBarPercentage)
                        .onChange(of: showMenuBarPercentage) { _, newValue in
                            viewModel.setShowMenuBarPercentage(newValue)
                        }
                }

                Section("Widgets") {
                    Text("Desktop widgets are in the macOS widget gallery under TokenPanel. Each widget has a toggle for Grok, Cursor, Claude, and Codex, so one tile can show a single provider or several. Keep TokenPanel running so the numbers stay current.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Updates") {
                    LabeledContent("This version", value: updater.currentVersion)
                    if updater.isEnabled {
                        Button("Check for Updates") {
                            updater.check()
                        }
                    } else {
                        Text(updater.disabledReason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(ProviderID.allCases) { provider in
                    Section {
                        LabeledContent("Status", value: status(for: provider))
                        LabeledContent("Session") {
                            Text(viewModel.authPath(for: provider))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(3)
                                .frame(maxWidth: 260, alignment: .trailing)
                        }

                        if provider == .grok {
                            #if os(macOS)
                            Button("Choose auth.json…") {
                                pickAuthFile()
                            }
                            if UserDefaults.standard.string(forKey: "grok.authFilePath") != nil {
                                Button("Clear custom path", role: .destructive) {
                                    UserDefaults.standard.removeObject(forKey: "grok.authFilePath")
                                    grokAuthPath = GrokAuthStore.authFileURL().path
                                    statusMessage = "Using default ~/.grok/auth.json"
                                }
                            }
                            #endif
                        }

                        if let snap = viewModel.snapshots[provider] {
                            if let email = snap.identity?.email {
                                LabeledContent("Account", value: email)
                            }
                            if let plan = snap.identity?.loginLabel {
                                LabeledContent("Plan", value: plan)
                            }
                        }

                        Text(footer(for: provider))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Label {
                            Text(provider.displayName)
                        } icon: {
                            ProviderLogo(provider: provider, size: 14)
                        }
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Button("Save & Refresh") {
                        Preferences.refreshMinutes = refreshMinutes
                        viewModel.setShowMenuBarPercentage(showMenuBarPercentage)
                        Task {
                            statusMessage = "Refreshing…"
                            await viewModel.refresh()
                            viewModel.start()
                            statusMessage = viewModel.lastError.map { "Refresh issue: \($0)" } ?? "Usage updated."
                            grokAuthPath = GrokAuthStore.authFileURL().path
                        }
                    }

                    #if os(macOS)
                    Button("Copy login for \(viewModel.selectedProvider.displayName)") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            viewModel.selectedProvider.loginCommand,
                            forType: .string
                        )
                        statusMessage = "Copied. Run it if needed, then refresh."
                    }
                    #endif
                }
            }
            .formStyle(.grouped)
        }
        #if os(iOS)
        .navigationTitle("Settings")
        #endif
        .onAppear {
            refreshMinutes = Preferences.refreshMinutes
            showMenuBarPercentage = Preferences.showMenuBarPercentage
            grokAuthPath = GrokAuthStore.authFileURL().path
        }
    }

    private func status(for provider: ProviderID) -> String {
        if viewModel.snapshots[provider]?.usedPercent != nil { return "Connected" }
        if let error = viewModel.errors[provider] { return error }
        if viewModel.configured.contains(provider) { return "Session found" }
        return "Not signed in"
    }

    private func footer(for provider: ProviderID) -> String {
        switch provider {
        case .grok:
            return "Sign in with `grok login`. SuperGrok credits, not xAI API prepaid dollars."
        case .cursor:
            return "Sign in inside Cursor. TokenPanel reads the local session and Cursor’s usage endpoint."
        case .claude:
            return "Log in with Claude Code (`claude`). Subscription plan windows only, not API-key billing."
        case .codex:
            return "Sign in with `codex login`. ChatGPT Codex rate-limit windows from the local session."
        }
    }

    #if os(macOS)
    private func pickAuthFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = GrokAuthStore.grokHome()
        panel.message = "Select your Grok auth.json (usually ~/.grok/auth.json)"
        panel.prompt = "Use this file"
        panel.allowedContentTypes = [.json, .data]
        panel.showsHiddenFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: "grok.authFilePath")
        grokAuthPath = url.path
        statusMessage = "Using \(url.path). Refreshing…"
        Task {
            await viewModel.refresh()
            viewModel.start()
            statusMessage = viewModel.lastError.map { "Refresh issue: \($0)" } ?? "Usage updated from selected file."
        }
    }
    #endif
}

#Preview {
    SettingsView(viewModel: UsageViewModel(), updater: AppUpdater())
}
