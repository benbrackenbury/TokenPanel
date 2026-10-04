import SwiftUI

@main
struct TokenPanelApp: App {
    @State private var viewModel = UsageViewModel()

    var body: some Scene {
        #if os(macOS)
        // Settings open as a sheet from the menu panel — MenuBarExtra + LSUIElement
        // apps often fail to present the system Settings scene via openSettings().
        MenuBarExtra {
            MenuPanelView(viewModel: viewModel)
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
        #else
        WindowGroup {
            MenuPanelView(viewModel: viewModel)
                .task { viewModel.start() }
        }
        #endif
    }
}
