import Foundation
import SwiftData

@Model
final class Song {
    var title: String
    var artist: String
    var instrumentRaw: String
    var tempo: Int
    var key: String
    var chordsJSON: Data
    var strummingPatternsJSON: Data
    var sectionsJSON: Data

    var instrument: Instrument {
        get { Instrument(rawValue: instrumentRaw) ?? .ukulele }
        set { instrumentRaw = newValue.rawValue }
    }

    var chords: [ChordDefinition] {
        get { (try? JSONDecoder().decode([ChordDefinition].self, from: chordsJSON)) ?? [] }
        set { chordsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var strummingPatterns: [StrummingPattern] {
        get { (try? JSONDecoder().decode([StrummingPattern].self, from: strummingPatternsJSON)) ?? [] }
        set { strummingPatternsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var sections: [SongSection] {
        get { (try? JSONDecoder().decode([SongSection].self, from: sectionsJSON)) ?? [] }
        set { sectionsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    // Will be true once fingerpicking notation is stored for this song.
    var hasPickingData: Bool { false }

    init(
        title: String,
        artist: String,
        instrument: Instrument = .ukulele,
        tempo: Int = 120,
        key: String = "C",
        chords: [ChordDefinition] = [],
        strummingPatterns: [StrummingPattern] = [],
        sections: [SongSection] = []
    ) {
        self.title = title
        self.artist = artist
        self.instrumentRaw = instrument.rawValue
        self.tempo = tempo
        self.key = key
        self.chordsJSON = (try? JSONEncoder().encode(chords)) ?? Data()
        self.strummingPatternsJSON = (try? JSONEncoder().encode(strummingPatterns)) ?? Data()
        self.sectionsJSON = (try? JSONEncoder().encode(sections)) ?? Data()
    }
}

enum Instrument: String, Codable, CaseIterable {
    case ukulele, guitar

    var stringCount: Int { self == .ukulele ? 4 : 6 }
    var openNotes: [String] {
        self == .ukulele ? ["G", "C", "E", "A"] : ["E", "A", "D", "G", "B", "E"]
    }
}
