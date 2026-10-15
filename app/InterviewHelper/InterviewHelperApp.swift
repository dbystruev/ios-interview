import SwiftData
import SwiftUI

@main
struct InterviewHelperApp: App {
    @State private var settings = AppSettings()
    private let container: ModelContainer?

    init() {
        if let persistent = try? ModelContainer(
            for: Topic.self, QAEntry.self,
            configurations: ModelConfiguration("InterviewHelper", isStoredInMemoryOnly: false)
        ) {
            container = persistent
        } else {
            container = try? ModelContainer(
                for: Topic.self, QAEntry.self,
                configurations: ModelConfiguration("InterviewHelper", isStoredInMemoryOnly: true)
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    ContentView()
                        .modelContainer(container)
                        .environment(settings)
                        .task {
                            await SeedImporter.seedIfEmpty(context: container.mainContext)
                        }
                } else {
                    Text("Storage unavailable. Please reinstall the app.")
                }
            }
        }
    }
}
