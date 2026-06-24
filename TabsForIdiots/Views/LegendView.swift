import SwiftUI

struct LegendView: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chords").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(song.chords) { chord in
                        ChordDiagramView(chord: chord, stringCount: song.instrument.stringCount)
                    }
                }
            }

            if !song.strummingPatterns.isEmpty {
                Text("Strumming").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(song.strummingPatterns) { pattern in
                        StrummingPatternView(pattern: pattern)
                    }
                }
            }
        }
    }
}
