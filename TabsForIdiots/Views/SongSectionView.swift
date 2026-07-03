import SwiftUI

// MARK: - Environment key for per-song lyric font size

private struct LyricFontSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 12
}

extension EnvironmentValues {
    var lyricFontSize: CGFloat {
        get { self[LyricFontSizeKey.self] }
        set { self[LyricFontSizeKey.self] = newValue }
    }
}

// MARK: -

struct SongSectionView: View {
    let section: SongSection
    let song: Song
    let displayMode: DisplayMode
    let currentMeasureId: UUID?
    let onJumpTo: ((UUID) -> Void)?

    private var isCurrent: Bool { currentMeasureId != nil }

    // Largest font size that fits every lyric in its assigned row mode.
    // Long lyrics (>30 chars) go in a solo 2× wide row, so they're normalized down.
    // Short lyrics (≤10 chars) go in a 4-per-row 0.5× cell, so they're normalized up.
    private func lyricFontSize(for song: Song) -> CGFloat {
        let maxEffective = song.sections.flatMap { $0.measures }.map { m -> Int in
            let c = m.lyric.count
            if c > 30 { return c / 2 }   // solo row → 2× cell width available
            if c <= 10 { return c * 2 }  // 4-per-row → 0.5× cell width available
            return c                      // 2-per-row baseline
        }.max() ?? 0
        switch maxEffective {
        case ...14: return 15
        case ...20: return 14
        case ...28: return 13
        default:    return 12
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.name)
                .font(.headline)
                .foregroundStyle(isCurrent ? .blue : .primary)
                .padding(.bottom, 2)

            if displayMode == .chordsAndPicking && song.strummingPatterns.isEmpty {
                Text("No fingerpicking data for this song")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            MeasureFlowView(
                measures: section.measures,
                lineGroupSizes: section.lineGroupSizes,
                song: song,
                displayMode: displayMode,
                currentMeasureId: currentMeasureId,
                onJumpTo: onJumpTo
            )
        }
        .environment(\.lyricFontSize, lyricFontSize(for: song))
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? Color.blue.opacity(0.05) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isCurrent ? Color.blue.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }
}

struct MeasureFlowView: View {
    let measures: [SongMeasure]
    let lineGroupSizes: [Int]
    let song: Song
    let displayMode: DisplayMode
    let currentMeasureId: UUID?
    let onJumpTo: ((UUID) -> Void)?

    // Split flat measures into .pro-line groups using lineGroupSizes.
    // Empty lineGroupSizes → single group containing all measures.
    private func proLines() -> [[SongMeasure]] {
        guard !lineGroupSizes.isEmpty else { return [measures] }
        var result: [[SongMeasure]] = []
        var start = 0
        for size in lineGroupSizes {
            let end = min(start + size, measures.count)
            if start < end { result.append(Array(measures[start..<end])) }
            start = end
        }
        return result
    }

    // Greedy layout within one .pro line → app rows of 1, 2, or 4 measures.
    //   lyric > 30 chars  → always solo (full-width row)
    //   lyric ≤ 10 chars  → prefer 4-per-row; fall back to 2-per-row or solo
    //   otherwise         → 2-per-row or solo
    private func appRows(for proLine: [SongMeasure]) -> [[SongMeasure]] {
        var rows: [[SongMeasure]] = []
        var i = 0
        while i < proLine.count {
            let len = proLine[i].lyric.count
            if len > 30 {
                rows.append([proLine[i]])
                i += 1
            } else if len <= 10 {
                let rem = proLine.count - i
                if rem >= 4 &&
                   proLine[i+1].lyric.count <= 10 &&
                   proLine[i+2].lyric.count <= 10 &&
                   proLine[i+3].lyric.count <= 10 {
                    rows.append(Array(proLine[i..<(i+4)]))
                    i += 4
                } else if i + 1 < proLine.count && proLine[i+1].lyric.count <= 30 {
                    rows.append([proLine[i], proLine[i+1]])
                    i += 2
                } else {
                    rows.append([proLine[i]])
                    i += 1
                }
            } else {
                if i + 1 < proLine.count && proLine[i+1].lyric.count <= 30 {
                    rows.append([proLine[i], proLine[i+1]])
                    i += 2
                } else {
                    rows.append([proLine[i]])
                    i += 1
                }
            }
        }
        return rows
    }

    var body: some View {
        let lines = proLines()
        VStack(alignment: .leading, spacing: 16) {
            ForEach(lines.indices, id: \.self) { lineIdx in
                let rows = appRows(for: lines[lineIdx])
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows.indices, id: \.self) { rowIdx in
                        MeasureLineView(
                            measures: rows[rowIdx],
                            song: song,
                            displayMode: displayMode,
                            currentMeasureId: currentMeasureId,
                            onJumpTo: onJumpTo
                        )
                    }
                }
            }
        }
    }
}

struct MeasureLineView: View {
    let measures: [SongMeasure]
    let song: Song
    let displayMode: DisplayMode
    let currentMeasureId: UUID?
    let onJumpTo: ((UUID) -> Void)?

    var body: some View {
        // Equal-width cells, no horizontal gap. Each cell has its own left padding.
        // This produces proper lead-sheet column alignment: all chord names on one
        // visual row, all lyrics on the row directly below.
        HStack(alignment: .top, spacing: 0) {
            ForEach(measures) { measure in
                MeasureCell(
                    measure: measure,
                    song: song,
                    displayMode: displayMode,
                    isCurrent: measure.id == currentMeasureId,
                    onJumpTo: onJumpTo
                )
                .frame(maxWidth: .infinity)
                .id(measure.id)
            }
        }
    }
}

struct MeasureCell: View {
    let measure: SongMeasure
    let song: Song
    let displayMode: DisplayMode
    let isCurrent: Bool
    let onJumpTo: ((UUID) -> Void)?

    @Environment(\.lyricFontSize) private var lyricFontSize
    @State private var isLongPressing = false

    // ── Derived strings ──────────────────────────────────────────────────

    private var chordName: String {
        guard let id = measure.chordId else { return "" }
        return song.chords.first(where: { $0.id == id })?.name ?? ""
    }

    // Lyric words / dashes, with beat markers removed.
    private var lyricWords: String {
        var s = measure.lyric.filter { $0 != "·" }
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private var strummingPattern: StrummingPattern? {
        guard displayMode != .chordsOnly,
              let id = measure.strummingPatternId else { return nil }
        return song.strummingPatterns.first(where: { $0.id == id })
    }

    // Pattern name shown between chord and lyric when song has multiple distinct patterns per measure
    private var patternName: String? {
        guard song.strummingPatterns.count > 1,
              let id = measure.strummingPatternId
        else { return nil }
        return song.strummingPatterns.first(where: { $0.id == id })?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chordName.isEmpty ? " " : chordName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.blue)
                .lineLimit(1)
            if let name = patternName {
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.orange : Color.orange.opacity(0.55))
                    .lineLimit(1)
            }
            Text(lyricWords.isEmpty ? " " : lyricWords)
                .font(.system(size: lyricFontSize))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear)
                .shadow(color: isCurrent ? .black.opacity(0.28) : .clear, radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isLongPressing ? Color.orange : (isCurrent ? Color.accentColor.opacity(0.80) : Color.clear),
                    lineWidth: (isCurrent || isLongPressing) ? 2.0 : 0
                )
        )
        .scaleEffect(isLongPressing ? 0.95 : (isCurrent ? 1.06 : 1.0))
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isCurrent)
        .animation(.easeInOut(duration: 0.15), value: isLongPressing)
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            guard onJumpTo != nil else { return }
            isLongPressing = pressing
        }, perform: {
            onJumpTo?(measure.id)
            isLongPressing = false
        })
    }
}
