import Foundation
import SwiftData

struct SampleSongs {
    static func seedIfNeeded(_ insert: (Song) -> Void) {
        guard !UserDefaults.standard.bool(forKey: "tabsForIdiotsSeeded") else { return }
        insert(makeSomewhereOverTheRainbow())
        insert(makeRiptide())
        UserDefaults.standard.set(true, forKey: "tabsForIdiotsSeeded")
    }

    // MARK: - Somewhere Over the Rainbow

    private static func makeSomewhereOverTheRainbow() -> Song {
        let cChord  = ChordDefinition(name: "C",  frets: [0,0,0,3], fingers: [0,0,0,3])
        let emChord = ChordDefinition(name: "Em", frets: [0,4,3,2], fingers: [0,4,3,1])
        let amChord = ChordDefinition(name: "Am", frets: [2,0,0,0], fingers: [2,0,0,0])
        let fChord  = ChordDefinition(name: "F",  frets: [2,0,1,0], fingers: [2,0,1,0])
        let gChord  = ChordDefinition(name: "G",  frets: [0,2,3,2], fingers: [0,1,3,2])
        let g7Chord = ChordDefinition(name: "G7", frets: [0,2,1,2], fingers: [0,2,1,3])

        let pattern = StrummingPattern(name: "Island Strum", strokes: [.down, .down, .up, .up, .down, .up])

        let intro = SongSection(name: "Intro", measures: [
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: g7Chord.id, strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: g7Chord.id, strummingPatternId: pattern.id, lyric: ""),
        ])

        let verse1 = SongSection(name: "Verse 1", measures: [
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "Some-"),
            SongMeasure(chordId: emChord.id, strummingPatternId: pattern.id, lyric: "where o-ver the"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "rain-bow,"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "way up"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "high,"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: emChord.id, strummingPatternId: pattern.id, lyric: "there's a"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "land that I"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "heard of"),
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: "once in a"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "lull-a-"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "by."),
        ])

        let chorus = SongSection(name: "Chorus", measures: [
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "Some-"),
            SongMeasure(chordId: emChord.id, strummingPatternId: pattern.id, lyric: "where o-ver the"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "rain-bow,"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "skies are"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "blue,"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: emChord.id, strummingPatternId: pattern.id, lyric: "and the"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "dreams that you"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "dare to"),
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: "dream real-ly"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "do come"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "true."),
        ])

        let verse2 = SongSection(name: "Verse 2", measures: [
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "Some-"),
            SongMeasure(chordId: emChord.id, strummingPatternId: pattern.id, lyric: "day I'll wish up-on a"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "star,"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "wake up where the"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "clouds are far be-"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "hind"),
            SongMeasure(chordId: gChord.id,  strummingPatternId: pattern.id, lyric: "me,"),
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: "where trou-bles melt like"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "lem-on drops,"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "a-way a-bove the"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "chim-ney tops,"),
            SongMeasure(chordId: g7Chord.id, strummingPatternId: pattern.id, lyric: "that's where"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "you'll find"),
            SongMeasure(chordId: g7Chord.id, strummingPatternId: pattern.id, lyric: "me."),
        ])

        let outro = SongSection(name: "Outro", measures: [
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "If hap-py lit-tle"),
            SongMeasure(chordId: emChord.id, strummingPatternId: pattern.id, lyric: "blue-birds fly be-"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "yond the rain-bow,"),
            SongMeasure(chordId: g7Chord.id, strummingPatternId: pattern.id, lyric: "why, oh why,"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "can't"),
            SongMeasure(chordId: fChord.id,  strummingPatternId: pattern.id, lyric: "I?"),
        ])

        return Song(
            title: "Somewhere Over the Rainbow",
            artist: "Israel Kamakawiwoʻole",
            instrument: .ukulele,
            tempo: 70,
            key: "C",
            chords: [cChord, emChord, amChord, fChord, gChord, g7Chord],
            strummingPatterns: [pattern],
            sections: [intro, verse1, chorus, verse2, outro]
        )
    }

    // MARK: - Riptide

    private static func makeRiptide() -> Song {
        let amChord = ChordDefinition(name: "Am", frets: [2,0,0,0], fingers: [2,0,0,0])
        let gChord  = ChordDefinition(name: "G",  frets: [0,2,3,2], fingers: [0,1,3,2])
        let cChord  = ChordDefinition(name: "C",  frets: [0,0,0,3], fingers: [0,0,0,3])

        let pattern = StrummingPattern(name: "Pop Strum", strokes: [.down, .up, .down, .up])

        let intro = SongSection(name: "Intro", measures: [
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: gChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
        ])

        let verse1 = SongSection(name: "Verse 1", measures: [
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: "I was scared of"),
            SongMeasure(chordId: gChord.id,  strummingPatternId: pattern.id, lyric: "dentists and the"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "dark."),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: "I was scared of"),
            SongMeasure(chordId: gChord.id,  strummingPatternId: pattern.id, lyric: "pretty girls and"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "starting con-"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "ver-sa-tions."),
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: "Oh, all my"),
            SongMeasure(chordId: gChord.id,  strummingPatternId: pattern.id, lyric: "friends are turn-ing"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "green."),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: "You're the mag-i-"),
            SongMeasure(chordId: gChord.id,  strummingPatternId: pattern.id, lyric: "cian's as-sis-tant in"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "their dreams."),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
        ])

        let preChorus = SongSection(name: "Pre-Chorus", measures: [
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: "And they come un-"),
            SongMeasure(chordId: gChord.id,  strummingPatternId: pattern.id, lyric: "sta-ble"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
        ])

        let chorus = SongSection(name: "Chorus", measures: [
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: "I love you when you're"),
            SongMeasure(chordId: gChord.id,  strummingPatternId: pattern.id, lyric: "sing-ing that"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "song, and"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: "I got a lump in my"),
            SongMeasure(chordId: gChord.id,  strummingPatternId: pattern.id, lyric: "throat 'cause"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "you're gonna"),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: "sing the words"),
            SongMeasure(chordId: amChord.id, strummingPatternId: pattern.id, lyric: "wrong."),
            SongMeasure(chordId: gChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
            SongMeasure(chordId: cChord.id,  strummingPatternId: pattern.id, lyric: ""),
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
