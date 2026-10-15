import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ListeningView()
                .tabItem { Label("Listen", systemImage: "mic.fill") }
                .accessibilityIdentifier("tab-listen")
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .accessibilityIdentifier("tab-library")
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .accessibilityIdentifier("tab-settings")
        }
    }
}
