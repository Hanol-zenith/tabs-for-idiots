import SwiftUI

struct SongSectionView: View {
    let section: SongSection
    let song: Song
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.name)
                .font(.headline)
                .foregroundStyle(isCurrent ? .blue : .primary)
                .padding(.bottom, 2)

            MeasureFlowView(measures: section.measures, song: song, isCurrent: isCurrent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isCurrent ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
    }
}

struct MeasureFlowView: View {
    let measures: [SongMeasure]
    let song: Song
    let isCurrent: Bool

    var body: some View {
        let lines = stride(from: 0, to: measures.count, by: 4).map {
            Array(measures[$0..<min($0 + 4, measures.count)])
        }

        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                MeasureLineView(measures: line, song: song)
            }
        }
    }
}

struct MeasureLineView: View {
    let measures: [SongMeasure]
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(measures) { measure in
                    MeasureChordLabel(measure: measure, song: song)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(measures) { measure in
                    Text(measure.lyric.isEmpty ? " " : measure.lyric)
                        .font(.system(size: 15))
                        .frame(minWidth: 80, alignment: .leading)
                }
            }
        }
    }
}

struct MeasureChordLabel: View {
    let measure: SongMeasure
    let song: Song

    var chordName: String {
        guard let id = measure.chordId else { return "" }
        return song.chords.first(where: { $0.id == id })?.name ?? ""
    }

    var body: some View {
        Text(chordName.isEmpty ? " " : chordName)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(.blue)
            .frame(minWidth: 80, alignment: .leading)
    }
}
