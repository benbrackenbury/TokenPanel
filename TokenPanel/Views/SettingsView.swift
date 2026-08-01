import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    @Bindable var viewModel: UsageViewModel
    @State private var refreshMinutes: Int = 5
    @State private var showMenuBarPercentage: Bool = true
    @State private var statusMessage: String?
    @State private var authPath: String = ""
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
                Section {
                    LabeledContent("Auth file") {
                        Text(authPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(4)
                            .frame(maxWidth: 260, alignment: .trailing)
                    }

                    #if os(macOS)
                    Button("Choose auth.json…") {
                        pickAuthFile()
                    }
                    if UserDefaults.standard.string(forKey: "grok.authFilePath") != nil {
                        Button("Clear custom path", role: .destructive) {
                            UserDefaults.standard.removeObject(forKey: "grok.authFilePath")
                            authPath = GrokAuthStore.authFileURL().path
                            statusMessage = "Using default ~/.grok/auth.json"
                        }
                    }
                    #endif

                    if let identity = viewModel.snapshot.identity {
                        if let email = identity.email {
                            LabeledContent("Account", value: email)
                        }
                        if let name = identity.displayName {
                            LabeledContent("Name", value: name)
                        }
                        LabeledContent("Plan", value: identity.loginLabel)
                        if let expires = identity.expiresAt {
                            LabeledContent(
                                "Token expires",
                                value: expires.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                    } else {
                        Text("No Grok session loaded yet.")
                            .foregroundStyle(.secondary)
                    }

                    Stepper(value: $refreshMinutes, in: 1...60) {
                        Text("Refresh every \(refreshMinutes) min")
                    }

                    Toggle("Show percentage in menu bar", isOn: $showMenuBarPercentage)
                        .onChange(of: showMenuBarPercentage) { _, newValue in
                            viewModel.setShowMenuBarPercentage(newValue)
                        }
                } header: {
                    Text("Grok session")
                } footer: {
                    Text(footerText)
                }

                Section("What this shows") {
                    Text("SuperGrok credit usage for Grok products (chat, voice, Build, Imagine, etc.) — not xAI API prepaid dollars.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Open grok.com usage", destination: URL(string: "https://grok.com/?_s=usage")!)
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
                            authPath = GrokAuthStore.authFileURL().path
                        }
                    }

                    #if os(macOS)
                    Button("Copy `grok login`") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("grok login", forType: .string)
                        statusMessage = "Copied. Run it in Terminal, then refresh."
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
            authPath = GrokAuthStore.authFileURL().path
        }
    }

    private var footerText: String {
        """
        Sign in with the Grok Build CLI:
          grok login

        TokenPanel reads ~/.grok/auth.json (or a path you choose) and calls grok.com’s credits endpoint.
        """
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
        authPath = url.path
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
    SettingsView(viewModel: UsageViewModel())
}
