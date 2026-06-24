import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                SongListView()
            }
            .tabItem { Label("Songs", systemImage: "music.note.list") }
        }
    }
}
