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
            // MenuBarExtra often drops Label titles — build the control explicitly.
            HStack(spacing: 4) {
                Image(systemName: viewModel.menuBarSystemImage)
                if viewModel.showMenuBarPercentage {
                    Text(viewModel.menuBarTitle)
                        .monospacedDigit()
                }
            }
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
