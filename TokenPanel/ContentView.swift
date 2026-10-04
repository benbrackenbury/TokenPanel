import SwiftUI

/// Shared root content used by previews and non-menu-bar hosts.
struct ContentView: View {
    @State private var viewModel = UsageViewModel()
    @State private var updater = AppUpdater()

    var body: some View {
        MenuPanelView(viewModel: viewModel, updater: updater)
            .onAppear { viewModel.start() }
    }
}

#Preview {
    ContentView()
}
