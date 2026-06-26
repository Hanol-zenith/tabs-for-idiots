import Foundation

struct SongSection: Codable, Identifiable {
    var id: UUID
    var name: String
    var measures: [SongMeasure]
    // How many consecutive measures belong to each .pro file line.
    // Empty = treat all measures as one group (default fallback).
    var lineGroupSizes: [Int]

    init(id: UUID = UUID(), name: String, measures: [SongMeasure] = [], lineGroupSizes: [Int] = []) {
        self.id = id
        self.name = name
        self.measures = measures
        self.lineGroupSizes = lineGroupSizes
    }

    // Custom decode so old JSON without lineGroupSizes decodes with [] default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,          forKey: .id)
        name           = try c.decode(String.self,        forKey: .name)
        measures       = try c.decode([SongMeasure].self, forKey: .measures)
        lineGroupSizes = try c.decodeIfPresent([Int].self, forKey: .lineGroupSizes) ?? []
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
