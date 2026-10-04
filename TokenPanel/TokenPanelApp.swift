import SwiftUI

@main
struct TokenPanelApp: App {
    @State private var viewModel = UsageViewModel()
    @State private var updater = AppUpdater()

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra {
            MenuPanelView(viewModel: viewModel, updater: updater)
                .task { viewModel.start() }
        } label: {
            Image(nsImage: MenuBarCluster.image(
                providers: viewModel.menuBarProviders,
                titles: viewModel.menuBarProviders.map {
                    viewModel.showMenuBarPercentage ? viewModel.menuBarTitle(for: $0) : ""
                }
            ))
            .id(viewModel.menuBarSignature)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(viewModel: viewModel, updater: updater)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        #else
        WindowGroup {
            MenuPanelView(viewModel: viewModel, updater: updater)
                .task { viewModel.start() }
        }
        #endif
    }
}
