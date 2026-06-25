import Foundation
import SwiftData

struct SampleSongs {
    // Bumped to V5 — full SOTR rewrite from SJUC/SUP PDF (seacoastukuleleplayers.com).
    // Chords: C, Em, F, E7, Am, G. Strum: DD uu D (5 strokes). Intro: C|Em|F|C|F|E7|Am|F.
    static func seedIfNeeded(in context: ModelContext) {
        let key = "tabsForIdiotsSeededV5"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        try? context.delete(model: Song.self)
        context.insert(makeSomewhereOverTheRainbow())
        context.insert(makeRiptide())
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Somewhere Over the Rainbow
    // Source: SJUC (San Jose Ukulele Club) / SUP arrangement
    // Key: C | 4/4 | ♩=70 | Strum: 1-2-3&4 (DD uu D)
    //
    // Song structure: Intro → Verse → Chorus → Bridge → Bluebirds → Bridge → Bluebirds → Outro
    //
    // Lyric convention:
    //   - Lyric row: words and dashes only (e.g. "Some -")
    //   - Chord row: chord name + beat markers (· · ·) for fully held measures
    //   - "· · · ·" in lyric field = all beats are instrumental (no text on lyric row)

    private static func makeSomewhereOverTheRainbow() -> Song {
        let cChord  = ChordDefinition(name: "C",  frets: [0,0,0,3], fingers: [0,0,0,3])
        let emChord = ChordDefinition(name: "Em", frets: [0,4,3,2], fingers: [0,4,3,1])
        let fChord  = ChordDefinition(name: "F",  frets: [2,0,1,0], fingers: [2,0,1,0])
        let e7Chord = ChordDefinition(name: "E7", frets: [1,2,0,2], fingers: [1,2,0,3])
        let amChord = ChordDefinition(name: "Am", frets: [2,0,0,0], fingers: [2,0,0,0])
        let gChord  = ChordDefinition(name: "G",  frets: [0,2,3,2], fingers: [0,1,3,2])

        // Strum: 1-2-3&4 = DD uu D (5 strokes)
        let pattern = StrummingPattern(
            name: "1-2-3&4 Strum",
            strokes: [.down, .down, .up, .up, .down]
        )

        func m(_ chord: ChordDefinition, _ lyric: String) -> SongMeasure {
            SongMeasure(chordId: chord.id, strummingPatternId: pattern.id, lyric: lyric)
        }
        let REST = "· · · ·"   // instrumental / held — renders as beat dots in chord row

        // ── INTRO (8 bars = 2 lines) ─────────────────────────────────────
        // C | Em | F | C | F | E7 | Am | F
        // Vocal: "Ooo" humming throughout
        let intro = SongSection(name: "Intro", measures: [
            // Line 1
            m(cChord,  "Ooo -"),
            m(emChord, "Ooo -"),
            m(fChord,  "Oo-o-o"),
            m(cChord,  "Oooo -"),
            // Line 2
            m(fChord,  "O-o-Ooo"),
            m(e7Chord, "Oooo -"),
            m(amChord, "Oo-o"),
            m(fChord,  "Oo-o"),
        ])

        // ── VERSE (8 bars = 2 lines) ─────────────────────────────────────
        // "Somewhere over the rainbow, way up high…"
        // Line 1: C | Em | F | C
        // Line 2: F | C  | G | Am
        let verse = SongSection(name: "Verse", measures: [
            // Line 1
            m(cChord,  "Some -"),
            m(emChord, "where -"),
            m(fChord,  "o-ver rain-bow"),
            m(cChord,  "way up high"),
            // Line 2
            m(fChord,  "There's a"),
            m(cChord,  "land that I"),
            m(gChord,  "heard of, once"),
            m(amChord, "in a lull-a-by"),
        ])

        // ── CHORUS (8 bars = 2 lines) ────────────────────────────────────
        // "Somewhere over the rainbow, skies are blue…"
        // Same chord progression as Verse, different lyrics
        let chorus = SongSection(name: "Chorus", measures: [
            // Line 1
            m(cChord,  "Some -"),
            m(emChord, "where -"),
            m(fChord,  "o-ver rain-bow"),
            m(cChord,  "skies are blue"),
            // Line 2
            m(fChord,  "And the dreams"),
            m(cChord,  "that you dare"),
            m(gChord,  "to dream real-ly"),
            m(amChord, "do come true"),
        ])

        // Bridge and Bluebirds each appear twice in the arrangement.
        // Build them as separate instances so each gets its own UUID (required for ForEach).
        func makeBridge() -> SongSection {
            SongSection(name: "Bridge", measures: [
                // Line 1: C | G | Am | F
                m(cChord,  "Some-day I'll"),
                m(gChord,  "wish up-on a"),
                m(amChord, "star, wake up"),
                m(fChord,  "where clouds are"),
                // Line 2: C | G | Am | F
                m(cChord,  "far be-hind me"),
                m(gChord,  "trou-bles melt"),
                m(amChord, "like lem-on drops"),
                m(fChord,  "that's where"),
            ])
        }

        func makeBluebirds() -> SongSection {
            SongSection(name: "Bluebirds", measures: [
                // Line 1: C | Em | F | C
                m(cChord,  "Oh, Some -"),
                m(emChord, "where -"),
                m(fChord,  "o-ver rain-bow"),
                m(cChord,  "blue-birds fly"),
                // Line 2: F | C | G | Am
                m(fChord,  "Birds fly o-"),
                m(cChord,  "ver the rain-bow"),
                m(gChord,  "why then, oh why"),
                m(amChord, "can't I -?"),
            ])
        }

        // ── OUTRO (8 bars = 2 lines) ─────────────────────────────────────
        // Same chord sequence as Intro (C | Em | F | C | F | E7 | Am | F)
        let outro = SongSection(name: "Outro", measures: [
            // Line 1
            m(cChord,  "Ooo -"),
            m(emChord, "Ooo -"),
            m(fChord,  "Oo-o-o"),
            m(cChord,  "Oooo -"),
            // Line 2
            m(fChord,  "O-o-Ooo"),
            m(e7Chord, "Oooo -"),
            m(amChord, "Oo-o"),
            m(fChord,  "Oo-o"),
        ])

        return Song(
            title: "Somewhere Over the Rainbow",
            artist: "Israel Kamakawiwoʻole",
            instrument: .ukulele,
            tempo: 70,
            key: "C",
            chords: [cChord, emChord, fChord, e7Chord, amChord, gChord],
            strummingPatterns: [pattern],
            sections: [
                intro,
                verse,
                chorus,
                makeBridge(),
                makeBluebirds(),
                makeBridge(),
                makeBluebirds(),
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

        let intro = SongSection(name: "Intro", measures: [
            m(amChord, REST),
            m(gChord,  REST),
            m(cChord,  REST),
            m(cChord,  REST),
        ])

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
        ])

        let preChorus = SongSection(name: "Pre-Chorus", measures: [
            m(amChord, "And they come"),
            m(gChord,  "un-sta-ble"),
            m(cChord,  REST),
            m(cChord,  REST),
        ])

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
        ])

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
