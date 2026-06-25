import SwiftUI

struct SongSectionView: View {
    let section: SongSection
    let song: Song
    let displayMode: DisplayMode
    let currentMeasureId: UUID?
    let onJumpTo: ((UUID) -> Void)?

    private var isCurrent: Bool { currentMeasureId != nil }

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
                song: song,
                displayMode: displayMode,
                currentMeasureId: currentMeasureId,
                onJumpTo: onJumpTo
            )
        }
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
    let song: Song
    let displayMode: DisplayMode
    let currentMeasureId: UUID?
    let onJumpTo: ((UUID) -> Void)?

    var body: some View {
        let lines = stride(from: 0, to: measures.count, by: 4).map {
            Array(measures[$0..<min($0 + 4, measures.count)])
        }
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                MeasureLineView(
                    measures: line,
                    song: song,
                    displayMode: displayMode,
                    currentMeasureId: currentMeasureId,
                    onJumpTo: onJumpTo
                )
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

    @State private var isLongPressing = false

    // ── Derived strings ──────────────────────────────────────────────────

    private var chordName: String {
        guard let id = measure.chordId else { return "" }
        return song.chords.first(where: { $0.id == id })?.name ?? ""
    }

    // `·` characters extracted from lyric → displayed inline with chord name.
    private var beatDots: String {
        let count = measure.lyric.filter { $0 == "·" }.count
        guard count > 0 else { return "" }
        return Array(repeating: "·", count: count).joined(separator: " ")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // ── Row 1: chord name + beat dots (same visual row) ─────────
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(chordName.isEmpty ? " " : chordName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.blue)

                if !beatDots.isEmpty {
                    Text(beatDots)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)

            // ── Row 2: lyric words / dashes only ────────────────────────
            Text(lyricWords.isEmpty ? " " : lyricWords)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            // Strumming is shown in the legend at the top, not repeated per cell.
            // (Songs with variable strum per measure can add it back here.)
        }
        .padding(.leading, 6)
        .padding(.vertical, 4)
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
