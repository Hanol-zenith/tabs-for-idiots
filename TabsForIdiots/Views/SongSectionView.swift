import SwiftUI

struct SongSectionView: View {
    let section: SongSection
    let song: Song
    let displayMode: DisplayMode
    let currentMeasureId: UUID?
    let matchState: ChordMatchState
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
                matchState: matchState,
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
    let matchState: ChordMatchState
    let onJumpTo: ((UUID) -> Void)?

    var body: some View {
        let lines = stride(from: 0, to: measures.count, by: 4).map {
            Array(measures[$0..<min($0 + 4, measures.count)])
        }
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                MeasureLineView(
                    measures: line,
                    song: song,
                    displayMode: displayMode,
                    currentMeasureId: currentMeasureId,
                    matchState: matchState,
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
    let matchState: ChordMatchState
    let onJumpTo: ((UUID) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(measures) { measure in
                MeasureCell(
                    measure: measure,
                    song: song,
                    displayMode: displayMode,
                    isCurrent: measure.id == currentMeasureId,
                    matchState: matchState,
                    onJumpTo: onJumpTo
                )
            }
        }
    }
}

struct MeasureCell: View {
    let measure: SongMeasure
    let song: Song
    let displayMode: DisplayMode
    let isCurrent: Bool
    let matchState: ChordMatchState
    let onJumpTo: ((UUID) -> Void)?

    @State private var isLongPressing = false

    private var chordName: String {
        guard let id = measure.chordId else { return "" }
        return song.chords.first(where: { $0.id == id })?.name ?? ""
    }

    private var strummingPattern: StrummingPattern? {
        guard displayMode != .chordsOnly,
              let id = measure.strummingPatternId else { return nil }
        return song.strummingPatterns.first(where: { $0.id == id })
    }

    private var highlightColor: Color {
        guard isCurrent else { return .clear }
        switch matchState {
        case .correct:          return .green.opacity(0.18)
        case .wrong:            return .red.opacity(0.15)
        case .waiting, .none:   return .blue.opacity(0.08)
        }
    }

    private var borderColor: Color {
        if isLongPressing { return .orange }
        guard isCurrent else { return .clear }
        switch matchState {
        case .correct:          return .green
        case .wrong:            return .red
        case .waiting:          return .blue.opacity(0.5)
        case .none:             return .clear
        }
    }

    private var chordColor: Color {
        guard isCurrent else { return .blue }
        switch matchState {
        case .correct:          return .green
        case .wrong:            return .red
        case .waiting, .none:   return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Chord name
            Text(chordName.isEmpty ? " " : chordName)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(chordColor)
                .frame(minWidth: 72, alignment: .leading)

            // Lyric
            Text(measure.lyric.isEmpty ? " " : measure.lyric)
                .font(.system(size: 15))
                .frame(minWidth: 72, alignment: .leading)

            // Strumming / picking arrows (only when mode is active)
            if let pattern = strummingPattern {
                HStack(spacing: 1) {
                    ForEach(Array(pattern.strokes.enumerated()), id: \.offset) { _, stroke in
                        Text(stroke.symbol)
                            .font(.system(size: 10))
                            .foregroundStyle(stroke.isDown ? Color.primary.opacity(0.7) : Color.blue.opacity(0.8))
                    }
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(highlightColor))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(borderColor, lineWidth: isCurrent || isLongPressing ? 1.5 : 0))
        .scaleEffect(isLongPressing ? 0.95 : 1.0)
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
