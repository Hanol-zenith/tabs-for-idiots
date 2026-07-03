import SwiftUI

struct LegendView: View {
    let song: Song
    @Binding var selectedPatternId: UUID?

    private struct DGroup: Identifiable {
        let id = UUID()
        let difficulty: ChordDifficulty
        let chords: [ChordDefinition]
    }

    private var groups: [DGroup] {
        ChordDifficulty.allCases.compactMap { d in
            let sorted = song.chords
                .filter { $0.difficulty == d }
                .sorted { chromaticSortKey($0.name) < chromaticSortKey($1.name) }
            return sorted.isEmpty ? nil : DGroup(difficulty: d, chords: sorted)
        }
    }

    private var allChords: [ChordDefinition] {
        groups.flatMap { $0.chords }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !song.chords.isEmpty {
                ScrollView(.vertical) {
                    ChordFlowLayout(spacing: 14) {
                        ForEach(allChords) { chord in
                            ChordDiagramView(chord: chord, stringCount: song.instrument.stringCount)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
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

    @ViewBuilder
    private var strummingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Strumming")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(song.strummingPatterns) { pattern in
                        StrummingPatternView(pattern: pattern)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: 160)
        }
    }
}

// Wrapping flow layout: items fill each row left-to-right and wrap to the
// next row when the remaining width is insufficient. No group-level line breaks.
private struct ChordFlowLayout: Layout {
    var spacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineH: CGFloat = 0

        for subview in subviews {
            let sz = subview.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxWidth {
                y += lineH + spacing
                x = 0
                lineH = 0
            }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
        return CGSize(width: maxWidth, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineH: CGFloat = 0

        for subview in subviews {
            let sz = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX {
                y += lineH + spacing
                x = bounds.minX
                lineH = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}
