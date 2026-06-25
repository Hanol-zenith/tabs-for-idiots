import SwiftUI

struct LegendView: View {
    let song: Song

    @State private var pageIdx = 0

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chordSection
            strummingSection
        }
    }

    // MARK: - Chord section

    @ViewBuilder
    private var chordSection: some View {
        let g = groups
        let safeIdx = min(pageIdx, max(0, g.count - 1))

        if g.isEmpty {
            EmptyView()
        } else if g.count == 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Chords").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    ForEach(g[0].chords) { chord in
                        ChordDiagramView(chord: chord, stringCount: song.instrument.stringCount)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                // Chord diagrams for current group
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("Chords").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("(\(g[safeIdx].label))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(g[safeIdx].chords) { chord in
                            ChordDiagramView(chord: chord, stringCount: song.instrument.stringCount)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 28)
                            .onEnded { val in
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    if val.translation.height < -28 {
                                        pageIdx = min(pageIdx + 1, g.count - 1)
                                    } else if val.translation.height > 28 {
                                        pageIdx = max(pageIdx - 1, 0)
                                    }
                                }
                            }
                    )
                }

                // Side difficulty labels — current is always centered in clip area.
                // Arrows show when there are groups above or below.
                let canGoUp   = safeIdx > 0
                let canGoDown = safeIdx < g.count - 1
                let labelStep: CGFloat = 40   // vertical distance between label centers
                let clipH: CGFloat = 80       // visible window height

                VStack(spacing: 2) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(canGoUp ? Color.secondary : Color.clear)

                    ZStack {
                        ForEach(Array(g.enumerated()), id: \.offset) { i, group in
                            let isCurrent = i == safeIdx
                            let yOff = CGFloat(i - safeIdx) * labelStep

                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    pageIdx = i
                                }
                            } label: {
                                Text(group.label)
                                    .font(isCurrent ? .caption.weight(.semibold) : .caption2)
                                    .foregroundStyle(isCurrent
                                        ? Color.primary
                                        : Color.secondary.opacity(0.40))
                                    .fixedSize()
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 14, height: 38)
                                    .scaleEffect(isCurrent ? 1.0 : 0.80)
                            }
                            .buttonStyle(.plain)
                            .offset(y: yOff)
                            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: safeIdx)
                        }
                    }
                    .frame(width: 20, height: clipH)
                    .clipped()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(canGoDown ? Color.secondary : Color.clear)
                }
            }
        }
    }

    // MARK: - Strumming section

    // True when every measure in the song uses the same single strumming pattern.
    private var uniformStrum: Bool {
        guard song.strummingPatterns.count == 1 else { return false }
        let pid = song.strummingPatterns[0].id
        return song.sections.allSatisfy { sec in
            sec.measures.allSatisfy { $0.strummingPatternId == pid }
        }
    }

    @ViewBuilder
    private var strummingSection: some View {
        if !song.strummingPatterns.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Strumming").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
}
