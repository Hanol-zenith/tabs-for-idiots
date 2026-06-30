import SwiftUI
import SwiftData

enum MySongsSortOrder: String, CaseIterable {
    case recentlyAdded    = "Recently Added"
    case recentlyPlayed   = "Recently Played"
    case aToZ             = "A–Z"
    case zToA             = "Z–A"
    case mostPracticed    = "Most Practiced"
    case leastPracticed   = "Least Practiced"
}

struct SongListView: View {
    @Query private var allSongs: [Song]
    @AppStorage("mySongsSortOrder") private var sortOrder: String = MySongsSortOrder.recentlyAdded.rawValue

    private var currentSort: MySongsSortOrder {
        MySongsSortOrder(rawValue: sortOrder) ?? .recentlyAdded
    }

    private var songs: [Song] {
        switch currentSort {
        case .recentlyAdded:
            return allSongs.sorted { $0.createdAt > $1.createdAt }
        case .recentlyPlayed:
            return allSongs.sorted {
                switch ($0.lastPlayedAt, $1.lastPlayedAt) {
                case (let a?, let b?): return a > b
                case (.some, .none):   return true
                case (.none, .some):   return false
                case (.none, .none):   return $0.title < $1.title
                }
            }
        case .aToZ:
            return allSongs.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .zToA:
            return allSongs.sorted { $0.title.localizedCompare($1.title) == .orderedDescending }
        case .mostPracticed:
            return allSongs.sorted { $0.totalPracticeSeconds > $1.totalPracticeSeconds }
        case .leastPracticed:
            return allSongs.sorted { $0.totalPracticeSeconds < $1.totalPracticeSeconds }
        }
    }

    private func formatPracticeTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes)) min"
    }

    var body: some View {
        List {
            ForEach(songs) { song in
                NavigationLink(destination: SongDetailView(song: song)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.headline)
                        Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Label(song.instrument.rawValue.capitalized, systemImage: "music.note")
                            Text("♩= \(song.tempo)")
                            Text(song.key)
                            if song.totalPracticeSeconds > 0 {
                                Text("· \(formatPracticeTime(song.totalPracticeSeconds))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollIndicators(.visible)
        .navigationTitle("My Songs")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(MySongsSortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order.rawValue
                        } label: {
                            if currentSort == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}
