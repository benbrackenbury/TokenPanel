import SwiftUI

/// Shared root content used by previews and non-menu-bar hosts.
struct ContentView: View {
    @State private var viewModel = UsageViewModel()

    var body: some View {
        MenuPanelView(viewModel: viewModel)
            .onAppear { viewModel.start() }
    }
}

#Preview {
    ContentView()
}
