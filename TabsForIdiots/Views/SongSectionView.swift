import SwiftUI

struct SongSectionView: View {
    let section: SongSection
    let song: Song
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

            MeasureFlowView(
                measures: section.measures,
                song: song,
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
    let currentMeasureId: UUID?
    let matchState: ChordMatchState
    let onJumpTo: ((UUID) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(measures) { measure in
                MeasureCell(
                    measure: measure,
                    song: song,
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
    let isCurrent: Bool
    let matchState: ChordMatchState
    let onJumpTo: ((UUID) -> Void)?

    @State private var isLongPressing = false

    private var chordName: String {
        guard let id = measure.chordId else { return "" }
        return song.chords.first(where: { $0.id == id })?.name ?? ""
    }

    private var highlightColor: Color {
        guard isCurrent else { return .clear }
        switch matchState {
        case .correct:  return .green.opacity(0.18)
        case .wrong:    return .red.opacity(0.15)
        case .waiting:  return .blue.opacity(0.08)
        case .none:     return .clear
        }
    }

    private var borderColor: Color {
        if isLongPressing { return .orange }
        guard isCurrent else { return .clear }
        switch matchState {
        case .correct:  return .green
        case .wrong:    return .red
        case .waiting:  return .blue.opacity(0.5)
        case .none:     return .clear
        }
    }

    private var chordColor: Color {
        guard isCurrent else { return .blue }
        switch matchState {
        case .correct:  return .green
        case .wrong:    return .red
        case .waiting, .none: return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chordName.isEmpty ? " " : chordName)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(chordColor)
                .frame(minWidth: 72, alignment: .leading)

            Text(measure.lyric.isEmpty ? " " : measure.lyric)
                .font(.system(size: 15))
                .frame(minWidth: 72, alignment: .leading)
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
