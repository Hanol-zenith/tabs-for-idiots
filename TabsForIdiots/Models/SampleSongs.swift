import Foundation
import SwiftData
import CryptoKit

struct SampleSongs {
    static func seedIfNeeded(in context: ModelContext) {
        // ── V16: re-seed all songs with isInLibrary = false for correct first-run UX ──
        let v16Key = "tabsForIdiotsSeededV16"
        if !UserDefaults.standard.bool(forKey: v16Key) {
            try? context.delete(model: Song.self)
            UserDefaults.standard.removeObject(forKey: "proFileHashes")
            let sotr = makeSomewhereOverTheRainbow()
            sotr.isInLibrary = false
            context.insert(sotr)
            let riptide = makeRiptide()
            riptide.isInLibrary = false
            context.insert(riptide)
            UserDefaults.standard.set(true, forKey: v16Key)
        }

        // ── File-based songs: hash-tracked so edits to .pro files re-seed ───
        let hashKey = "proFileHashes"
        var hashes = (UserDefaults.standard.dictionary(forKey: hashKey) as? [String: String]) ?? [:]
        let urls = Bundle.main.urls(forResourcesWithExtension: "pro", subdirectory: "Songs") ?? []

        let fetchDesc = FetchDescriptor<Song>()
        let allSongs = (try? context.fetch(fetchDesc)) ?? []

        for url in urls {
            let filename = url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else { continue }
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

            if hashes[filename] == hash { continue }

            // Remove stale record (by proSourceFile, or by title for migration)
            if let old = allSongs.first(where: { $0.proSourceFile == filename })
                ?? allSongs.first(where: { $0.proSourceFile == "" && ChordProParser.title(of: url) == $0.title }) {
                context.delete(old)
            }

            if let song = ChordProParser.parse(url: url) {
                song.isInLibrary = false
                song.proSourceFile = filename
                context.insert(song)
                hashes[filename] = hash
            }
        }
        UserDefaults.standard.set(hashes, forKey: hashKey)
    }

    // MARK: - Somewhere Over the Rainbow
    // Source: user-authored ChordPro
    // Key: C | 4/4 | ♩=75 | Strum: Island Strum (D D U U D U)
    // Structure: Intro → V1 → V2 → Bridge1 → V3 → Bridge2 → V4 → Outro

    private static func makeSomewhereOverTheRainbow() -> Song {
        let cChord  = ChordDefinition(name: "C",  frets: [0,0,0,3], fingers: [0,0,0,3])
        let emChord = ChordDefinition(name: "Em", frets: [0,4,3,2], fingers: [0,4,3,1])
        let fChord  = ChordDefinition(name: "F",  frets: [2,0,1,0], fingers: [2,0,1,0])
        let e7Chord = ChordDefinition(name: "E7", frets: [1,2,0,2], fingers: [1,2,0,3])
        let amChord = ChordDefinition(name: "Am", frets: [2,0,0,0], fingers: [2,0,0,0])
        let gChord  = ChordDefinition(name: "G",  frets: [0,2,3,2], fingers: [0,1,3,2])

        let pattern = StrummingPattern(
            name: "Island Strum",
            strokes: [.down, .down, .up, .up, .down, .up],
            intervals: [1.0, 0.5, 0.5, 0.5, 0.5, 1.0]
        )

        func m(_ chord: ChordDefinition, _ lyric: String) -> SongMeasure {
            SongMeasure(chordId: chord.id, strummingPatternId: pattern.id, lyric: lyric)
        }

        // ── INTRO / OUTRO (8 bars: C Em F C / F E7 Am F) ─────────────────
        // lineGroupSizes [4,4]: two .pro lines of 4 chords → 4-per-row each
        let intro = SongSection(name: "Intro", measures: [
            m(cChord,  "Oooo,"),
            m(emChord, "oooo,"),
            m(fChord,  "oooo,"),
            m(cChord,  "oooo..."),
            m(fChord,  "Oooo,"),
            m(e7Chord, "oooo,"),
            m(amChord, "oooo,"),
            m(fChord,  "oooo..."),
        ], lineGroupSizes: [4, 4])

        // ── VERSE (9 bars: C Em F C / F C G Am F) ─────────────────────────
        // lineGroupSizes [4,5]: .pro line 1 = C Em F C, .pro line 2 = F C G Am F

        let verse1 = SongSection(name: "Verse 1", measures: [
            m(cChord,  "Somewhere"),
            m(emChord, "over the rainbow,"),
            m(fChord,  "— way up"),           // F plays 2 silent beats before "way"
            m(cChord,  "high"),
            m(fChord,  "and the"),
            m(cChord,  "dreams that you dream of"),
            m(gChord,  "once in a lull-a-"),  // Am chord falls on "b" of "lullaby"
            m(amChord, "-by."),
            m(fChord,  "Ohhhh."),
        ], lineGroupSizes: [4, 5])

        let verse2 = SongSection(name: "Verse 2", measures: [
            m(cChord,  "Somewhere"),
            m(emChord, "over the rainbow"),
            m(fChord,  "bluebirds"),
            m(cChord,  "fly"),
            m(fChord,  "and the"),
            m(cChord,  "dreams that you dream of,"),
            m(gChord,  "dreams really do come"),
            m(amChord, "true."),
            m(fChord,  "Ohhhh."),
        ], lineGroupSizes: [4, 5])

        let verse3 = SongSection(name: "Verse 3", measures: [
            m(cChord,  "Somewhere"),
            m(emChord, "over the rainbow,"),
            m(fChord,  "— bluebirds"),              // F plays 2 silent beats before "bluebirds"
            m(cChord,  "fly"),
            m(fChord,  "and the"),
            m(cChord,  "dreams that you dare to, oh,"),  // C covers through "oh,"
            m(gChord,  "why, oh why can't"),
            m(amChord, "I?"),
            m(fChord,  "I-I-I, oh"),
        ], lineGroupSizes: [4, 5])

        let verse4 = SongSection(name: "Verse 4", measures: [
            m(cChord,  "Somewhere"),
            m(emChord, "over the rainbow,"),
            m(fChord,  "— way up"),
            m(cChord,  "high"),
            m(fChord,  "and the"),
            m(cChord,  "dreams that you dare to,"),
            m(gChord,  "why, oh why can't"),
            m(amChord, "I?"),
            m(fChord,  "I-I-I"),
        ], lineGroupSizes: [4, 5])

        // ── BRIDGE (8 bars: C / Em Am F / C / Em / Am F) ──────────────────
        // lineGroupSizes [1,3,1,1,2]: each .pro line as a separate group.
        // Bridge uses Em on chord 2 (not G). Two variants differ only in "behind me."
        func makeBridge(name: String, behindMe: String) -> SongSection {
            SongSection(name: name, measures: [
                m(cChord,  "(Some-)day I'll wish upon a star,"),
                m(emChord, "wake up where the clouds are far be-"),
                m(amChord, "-hind"),
                m(fChord,  behindMe),
                m(cChord,  "(Where) troubles melt like lemon drops,"), // "Where" pickup before C
                m(emChord, "high above the chimney tops, that's"),     // Em extends into "that's"
                m(amChord, "where you'll"),                            // Am starts on "where"
                m(fChord,  "find me, oh"),
            ], lineGroupSizes: [1, 3, 1, 1, 2])
        }

        let outro = SongSection(name: "Outro", measures: [
            m(cChord,  "Oooo,"),
            m(emChord, "oooo,"),
            m(fChord,  "oooo,"),
            m(cChord,  "oooo..."),
            m(fChord,  "Oooo,"),
            m(e7Chord, "oooo,"),
            m(amChord, "oooo,"),
            m(fChord,  "oooo..."),
        ], lineGroupSizes: [4, 4])

        return Song(
            title: "Somewhere Over the Rainbow",
            artist: "Israel Kamakawiwoʻole",
            instrument: .ukulele,
            tempo: 75,
            key: "C",
            chords: [cChord, emChord, fChord, e7Chord, amChord, gChord],
            strummingPatterns: [pattern],
            sections: [
                intro,
                verse1,
                verse2,
                makeBridge(name: "Bridge 1", behindMe: "me."),
                verse3,
                makeBridge(name: "Bridge 2", behindMe: "me-e-e."),
                verse4,
                outro,
            ]
        )
    }

    // MARK: - Riptide

    private static func makeRiptide() -> Song {
        let amChord = ChordDefinition(name: "Am", frets: [2,0,0,0], fingers: [2,0,0,0])
        let gChord  = ChordDefinition(name: "G",  frets: [0,2,3,2], fingers: [0,1,3,2])
        let cChord  = ChordDefinition(name: "C",  frets: [0,0,0,3], fingers: [0,0,0,3])

        let pattern = StrummingPattern(name: "Pop Strum", strokes: [.down, .up, .down, .up])
        let REST = "· · · ·"

        func m(_ chord: ChordDefinition, _ lyric: String) -> SongMeasure {
            SongMeasure(chordId: chord.id, strummingPatternId: pattern.id, lyric: lyric)
        }

        // 4 chords per .pro line → [4] lets them collapse to one 4-per-row app row
        let intro = SongSection(name: "Intro", measures: [
            m(amChord, REST),
            m(gChord,  REST),
            m(cChord,  REST),
            m(cChord,  REST),
        ], lineGroupSizes: [4])

        // Each verse .pro line is Am G C C (4 chords)
        let verse1 = SongSection(name: "Verse 1", measures: [
            m(amChord, "I was scared of"),
            m(gChord,  "dentists and"),
            m(cChord,  "the dark."),
            m(cChord,  REST),
            m(amChord, "I was scared of"),
            m(gChord,  "pretty girls and"),
            m(cChord,  "start-ing con-"),
            m(cChord,  "ver-sa-tions."),
            m(amChord, "Oh, all my"),
            m(gChord,  "friends are turn-"),
            m(cChord,  "ing green."),
            m(cChord,  REST),
            m(amChord, "You're the ma-"),
            m(gChord,  "gi-cian's as-sis-"),
            m(cChord,  "tant in their dreams."),
            m(cChord,  REST),
        ], lineGroupSizes: [4, 4, 4, 4])

        let preChorus = SongSection(name: "Pre-Chorus", measures: [
            m(amChord, "And they come"),
            m(gChord,  "un-sta-ble"),
            m(cChord,  REST),
            m(cChord,  REST),
        ], lineGroupSizes: [2, 2])

        let chorus = SongSection(name: "Chorus", measures: [
            m(amChord, "I love you when"),
            m(gChord,  "you're sing-ing"),
            m(cChord,  "that song, and"),
            m(cChord,  REST),
            m(amChord, "I got a lump in"),
            m(gChord,  "my throat 'cause"),
            m(cChord,  "you're gon-na"),
            m(cChord,  "sing the words wrong."),
            m(amChord, REST),
            m(gChord,  REST),
            m(cChord,  REST),
            m(cChord,  REST),
        ], lineGroupSizes: [4, 4, 4])

        return Song(
            title: "Riptide",
            artist: "Vance Joy",
            instrument: .ukulele,
            tempo: 96,
            key: "Am",
            chords: [amChord, gChord, cChord],
            strummingPatterns: [pattern],
            sections: [intro, verse1, preChorus, chorus]
        )
    }
}
