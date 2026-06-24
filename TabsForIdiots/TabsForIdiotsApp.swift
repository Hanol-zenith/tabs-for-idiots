import SwiftUI
import SwiftData

@main
struct TabsForIdiotsApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Song.self])
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .task { await bootstrap() }
        }
    }

    @MainActor
    private func bootstrap() async {
        let context = container.mainContext
        SampleSongs.seedIfNeeded { context.insert($0) }
    }
}
