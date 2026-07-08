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
    // One or more chords played within this single measure (bracket-grouped
    // in the source, e.g. "[(A)says this (E)takes]" = A and E in one strum).
    var chordIds: [UUID]
    var strummingPatternId: UUID?
    var lyric: String

    // Primary chord — used by single-chord displays and chord-matching/listening.
    var chordId: UUID? { chordIds.first }

    init(id: UUID = UUID(), chordId: UUID? = nil, strummingPatternId: UUID? = nil, lyric: String = "") {
        self.id = id
        self.chordIds = chordId.map { [$0] } ?? []
        self.strummingPatternId = strummingPatternId
        self.lyric = lyric
    }

    init(id: UUID = UUID(), chordIds: [UUID], strummingPatternId: UUID? = nil, lyric: String = "") {
        self.id = id
        self.chordIds = chordIds
        self.strummingPatternId = strummingPatternId
        self.lyric = lyric
    }

    // Custom decode so old JSON (singular "chordId") still loads.
    enum CodingKeys: String, CodingKey { case id, chordIds, chordId, strummingPatternId, lyric }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        if let ids = try c.decodeIfPresent([UUID].self, forKey: .chordIds) {
            chordIds = ids
        } else if let single = try c.decodeIfPresent(UUID.self, forKey: .chordId) {
            chordIds = [single]
        } else {
            chordIds = []
        }
        strummingPatternId = try c.decodeIfPresent(UUID.self, forKey: .strummingPatternId)
        lyric = try c.decode(String.self, forKey: .lyric)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(chordIds, forKey: .chordIds)
        try c.encode(strummingPatternId, forKey: .strummingPatternId)
        try c.encode(lyric, forKey: .lyric)
    }
}
