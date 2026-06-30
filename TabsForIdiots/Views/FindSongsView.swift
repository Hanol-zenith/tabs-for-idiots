import SwiftUI

enum CatalogSortOrder: String, CaseIterable {
    case aToZ      = "A–Z"
    case zToA      = "Z–A"
    case byArtist  = "By Artist"
}

// Placeholder for songs that will be added to the catalog later.
struct CatalogSong: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let instrument: String
    let key: String
}

struct FindSongsView: View {
    @State private var searchText = ""
    @AppStorage("catalogSortOrder") private var sortOrder: String = CatalogSortOrder.aToZ.rawValue

    private var currentSort: CatalogSortOrder {
        CatalogSortOrder(rawValue: sortOrder) ?? .aToZ
    }

    // Catalog populated later via SampleSongs or a future server fetch.
    private let catalog: [CatalogSong] = []

    private var filtered: [CatalogSong] {
        let base: [CatalogSong]
        if searchText.isEmpty {
            base = catalog
        } else {
            let q = searchText.lowercased()
            base = catalog.filter {
                $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
            }
        }
        switch currentSort {
        case .aToZ:     return base.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .zToA:     return base.sorted { $0.title.localizedCompare($1.title) == .orderedDescending }
        case .byArtist: return base.sorted { $0.artist.localizedCompare($1.artist) == .orderedAscending }
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Songs Yet" : "No Results",
                    systemImage: searchText.isEmpty ? "music.note.list" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Songs will appear here as they're added to the catalog."
                        : "Try a different search term.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filtered) { song in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.headline)
                        Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Label(song.instrument.capitalized, systemImage: "music.note")
                            Text(song.key)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollIndicators(.visible)
        .navigationTitle("Find Songs")
        .searchable(text: $searchText, prompt: "Search songs or artists")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(CatalogSortOrder.allCases, id: \.self) { order in
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
