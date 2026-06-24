import SwiftUI
import SwiftData

struct SongListView: View {
    @Query(sort: \Song.title) private var songs: [Song]

    var body: some View {
        List(songs) { song in
            NavigationLink(destination: SongDetailView(song: song)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.headline)
                    Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Label(song.instrument.rawValue.capitalized, systemImage: "music.note")
                        Text("♩= \(song.tempo)")
                        Text(song.key)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Tabs for Idiots")
    }
}
