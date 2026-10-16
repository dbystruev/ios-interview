import SwiftUI

struct ContentView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ListeningView()
                .tabItem { Label("Listen", systemImage: "mic.fill") }
                .accessibilityIdentifier("tab-listen")
                .tag(0)
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .accessibilityIdentifier("tab-library")
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .accessibilityIdentifier("tab-settings")
                .tag(2)
        }
        .onAppear {
            // Device-diagnostics hook pairs with ListeningView's --auto-listen:
            // land on the Listen tab so its autostart runs at launch.
            if CommandLine.arguments.contains("--auto-listen") {
                selection = 0
            }
        }
    }
}
