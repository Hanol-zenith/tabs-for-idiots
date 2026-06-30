import SwiftUI

struct LegendView: View {
    let song: Song

    private struct DGroup: Identifiable {
        let id = UUID()
        let difficulty: ChordDifficulty
        let chords: [ChordDefinition]
        var label: String { difficulty.label }
    }

    private var groups: [DGroup] {
        ChordDifficulty.allCases.compactMap { d in
            let matching = song.chords.filter { $0.difficulty == d }
            return matching.isEmpty ? nil : DGroup(difficulty: d, chords: matching)
        }
    }

    private var uniformStrum: Bool {
        guard song.strummingPatterns.count == 1 else { return false }
        let pid = song.strummingPatterns[0].id
        return song.sections.allSatisfy { $0.measures.allSatisfy { $0.strummingPatternId == pid } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chord tabs — scrolls vertically to show All / Easy / Medium / Hard
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if !song.chords.isEmpty {
                        chordRow(label: "Chords", chords: song.chords)
                    }
                    ForEach(groups) { group in
                        chordRow(label: group.label, chords: group.chords)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 160)

            // Strumming stays pinned — does not scroll with the tabs
            if !song.strummingPatterns.isEmpty {
                Divider()
                strummingSection
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Sub-views

    private func chordRow(label: String, chords: [ChordDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(chords) { chord in
                        ChordDiagramView(chord: chord, stringCount: song.instrument.stringCount)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var strummingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Strumming")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if uniformStrum {
                    Text("(same throughout)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(song.strummingPatterns) { pattern in
                StrummingPatternView(pattern: pattern)
            }
        }
    }
}
