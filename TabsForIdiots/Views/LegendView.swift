import SwiftUI

struct LegendView: View {
    let song: Song

    private struct DGroup: Identifiable {
        let id = UUID()
        let difficulty: ChordDifficulty
        let chords: [ChordDefinition]
    }

    // One row per difficulty level, each sorted chromatically.
    private var groups: [DGroup] {
        ChordDifficulty.allCases.compactMap { d in
            let sorted = song.chords
                .filter { $0.difficulty == d }
                .sorted { chromaticSortKey($0.name) < chromaticSortKey($1.name) }
            return sorted.isEmpty ? nil : DGroup(difficulty: d, chords: sorted)
        }
    }

    private func chromaticSortKey(_ name: String) -> (Int, Int) {
        (chromaticRoot(name), qualitySort(name))
    }

    private func chromaticRoot(_ name: String) -> Int {
        let two: [(String, Int)] = [
            ("Bb", 10), ("Db", 1), ("Eb", 3), ("Gb", 6), ("Ab", 8),
            ("C#", 1), ("D#", 3), ("F#", 6), ("G#", 8), ("A#", 10)
        ]
        for (prefix, pc) in two where name.hasPrefix(prefix) { return pc }
        let one: [(String, Int)] = [
            ("C", 0), ("D", 2), ("E", 4), ("F", 5), ("G", 7), ("A", 9), ("B", 11)
        ]
        for (prefix, pc) in one where name.hasPrefix(prefix) { return pc }
        return 0
    }

    private func qualitySort(_ name: String) -> Int {
        if name.hasSuffix("m7") { return 3 }
        if name.hasSuffix("m")  { return 1 }
        if name.hasSuffix("7")  { return 2 }
        return 0
    }

    private var uniformStrum: Bool {
        guard song.strummingPatterns.count == 1 else { return false }
        let pid = song.strummingPatterns[0].id
        return song.sections.allSatisfy { $0.measures.allSatisfy { $0.strummingPatternId == pid } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !song.chords.isEmpty {
                PersistentScrollView(axes: .vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            chordRow(chords: group.chords)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 160)
            }

            if !song.strummingPatterns.isEmpty {
                Divider()
                strummingSection
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }

    private func chordRow(chords: [ChordDefinition]) -> some View {
        PersistentScrollView(axes: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(chords) { chord in
                    ChordDiagramView(chord: chord, stringCount: song.instrument.stringCount)
                }
            }
            .padding(.vertical, 8)
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
