import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                SongListView()
            }
            .tabItem { Label("My Songs", systemImage: "music.note.list") }

            NavigationStack {
                FindSongsView()
            }
            .tabItem { Label("Find Songs", systemImage: "magnifyingglass") }
        }
    }
}
