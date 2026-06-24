import Foundation

struct SongSection: Codable, Identifiable {
    var id: UUID
    var name: String
    var measures: [SongMeasure]

    init(id: UUID = UUID(), name: String, measures: [SongMeasure] = []) {
        self.id = id
        self.name = name
        self.measures = measures
    }
}

struct SongMeasure: Codable, Identifiable {
    var id: UUID
    var chordId: UUID?
    var strummingPatternId: UUID?
    var lyric: String

    init(id: UUID = UUID(), chordId: UUID? = nil, strummingPatternId: UUID? = nil, lyric: String = "") {
        self.id = id
        self.chordId = chordId
        self.strummingPatternId = strummingPatternId
        self.lyric = lyric
    }
}
