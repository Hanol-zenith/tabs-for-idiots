import SwiftUI
import SwiftData

enum CatalogSortOrder: String, CaseIterable {
    case aToZ      = "A–Z"
    case zToA      = "Z–A"
    case byArtist  = "By Artist"
}

struct FindSongsView: View {
    @Query private var allSongs: [Song]
    @State private var searchText = ""
    @AppStorage("catalogSortOrder") private var sortOrder: String = CatalogSortOrder.aToZ.rawValue
    @AppStorage("catalogShowUnownedOnly") private var showUnownedOnly = false

    private var currentSort: CatalogSortOrder {
        CatalogSortOrder(rawValue: sortOrder) ?? .aToZ
    }

    private var filtered: [Song] {
        var base = allSongs
        if showUnownedOnly {
            base = base.filter { !$0.isInLibrary }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            base = base.filter {
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
                    emptyTitle,
                    systemImage: searchText.isEmpty ? "music.note.list" : "magnifyingglass",
                    description: Text(emptyDescription)
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filtered) { song in
                    NavigationLink(destination: SongDetailView(song: song, readOnly: true)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).font(.headline)
                                Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Label(song.instrument.rawValue.capitalized, systemImage: "music.note")
                                    Text(song.key)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(song.isInLibrary ? 0.45 : 1)

                            if song.isInLibrary {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.secondary.opacity(0.4))
                            } else {
                                Button {
                                    song.isInLibrary = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(Color.accentColor)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .scrollIndicators(.visible)
        .navigationTitle("Find Songs")
        .searchable(text: $searchText, prompt: "Search songs or artists")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section("Sort") {
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
                    }
                    Section("Filter") {
                        Button {
                            showUnownedOnly.toggle()
                        } label: {
                            if showUnownedOnly {
                                Label("Unowned Only", systemImage: "checkmark")
                            } else {
                                Text("Unowned Only")
                            }
                        }
                    }
                } label: {
                    Image(systemName: showUnownedOnly
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return "No Results" }
        return showUnownedOnly ? "All Songs Added" : "No Songs Yet"
    }

    private var emptyDescription: String {
        if !searchText.isEmpty { return "Try a different search term." }
        return showUnownedOnly
            ? "You've added all available songs to My Songs."
            : "Songs will appear here as they're added to the catalog."
    }
}
