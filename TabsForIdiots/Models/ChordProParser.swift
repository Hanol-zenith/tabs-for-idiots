import Foundation

struct ChordProParser {

    // MARK: - Public API

    static func parse(url: URL) -> Song? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text: text)
    }

    static func parse(text: String) -> Song? {
        var lines = text.components(separatedBy: .newlines)

        // Strip ukutabs.com disclaimer
        if let cut = lines.firstIndex(where: { $0.contains("contributor's own interpretation") }) {
            lines = Array(lines[..<cut])
        }

        var meta = Meta()
        var sections: [ParsedSection] = []
        var current: ParsedSection? = nil
        var pendingChordLine: String? = nil

        func flushChordLine() {
            guard let cl = pendingChordLine else { return }
            addPair(cl, lyric: "", to: &current)
            pendingChordLine = nil
        }

        func closeSection() {
            flushChordLine()
            if let s = current, !s.chords.isEmpty { sections.append(s) }
            current = nil
        }

        for raw in lines {
            let line = raw  // keep original spacing for column maths
            let t = raw.trimmingCharacters(in: .whitespaces)

            // Metadata: {key: value}
            if t.hasPrefix("{"), t.hasSuffix("}") {
                parseMeta(t, into: &meta)
                continue
            }

            // Section header
            if let (name, inline) = sectionHeader(t) {
                closeSection()
                current = ParsedSection(name: name)
                if !inline.isEmpty {
                    for ch in inline { current!.chords.append(ch); current!.lyrics.append("") }
                    current!.lineGroupSizes.append(inline.count)
                }
                continue
            }

            // Empty line — flush any pending chord line
            if t.isEmpty { flushChordLine(); continue }

            // Chord line vs lyric line
            if isChordLine(t) {
                flushChordLine()
                pendingChordLine = line
            } else {
                if let cl = pendingChordLine {
                    addPair(cl, lyric: line, to: &current)
                    pendingChordLine = nil
                }
                // floating lyric with no chord: skip
            }
        }

        closeSection()
        guard !sections.isEmpty else { return nil }
        return buildSong(meta: meta, sections: sections)
    }

    // MARK: - Internal types

    private struct Meta {
        var title: String?
        var artist: String?
        var key: String?
        var tempo: Int?
    }

    private struct ParsedSection {
        var name: String
        var chords: [String] = []
        var lyrics: [String] = []
        var lineGroupSizes: [Int] = []
    }

    // MARK: - Metadata parsing

    private static func parseMeta(_ t: String, into meta: inout Meta) {
        // {title: Half The World Away}
        let inner = String(t.dropFirst().dropLast())
        guard let colon = inner.firstIndex(of: ":") else { return }
        let key = inner[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let val = inner[inner.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        switch key {
        case "title":  meta.title  = val
        case "artist": meta.artist = val
        case "key":    meta.key    = val
        case "tempo":  meta.tempo  = Int(val)
        default: break
        }
    }

    // MARK: - Section header detection

    // Returns (sectionName, inlineChords) or nil if not a section header.
    // Handles "Verse:" and "Intro: C F C F".
    private static func sectionHeader(_ t: String) -> (name: String, chords: [String])? {
        guard let colonIdx = t.firstIndex(of: ":") else { return nil }
        let before = String(t[..<colonIdx]).trimmingCharacters(in: .whitespaces)
        let after  = String(t[t.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

        // Name: 1–5 words, first word starts uppercase
        let nameWords = before.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard (1...5).contains(nameWords.count),
              nameWords[0].first?.isUppercase == true else { return nil }

        // After the colon must be empty or all chord tokens
        let afterTokens = after.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard afterTokens.isEmpty || afterTokens.allSatisfy({ isChordToken($0) }) else { return nil }

        return (before, afterTokens)
    }

    // MARK: - Chord line detection

    private static func isChordLine(_ t: String) -> Bool {
        let tokens = t.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return !tokens.isEmpty && tokens.allSatisfy { isChordToken($0) }
    }

    // A chord token: starts with A–G, followed only by letters/digits/#/b/+/-
    private static func isChordToken(_ s: String) -> Bool {
        guard let first = s.first, "ABCDEFG".contains(first) else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || "#b/+".contains($0) }
    }

    // MARK: - Chord + lyric pairing

    private static func addPair(_ chordLine: String, lyric: String, to section: inout ParsedSection?) {
        guard section != nil else { return }
        let pairs = extractPairs(chordLine: chordLine, lyricLine: lyric)
        guard !pairs.isEmpty else { return }
        for (ch, lyr) in pairs {
            section!.chords.append(ch)
            section!.lyrics.append(lyr)
        }
        section!.lineGroupSizes.append(pairs.count)
    }

    // Extract (chord, lyric-fragment) pairs by aligning chord column positions with the lyric line.
    private static func extractPairs(chordLine: String, lyricLine: String) -> [(chord: String, lyric: String)] {
        // Find each chord token and its start column
        var positions: [(chord: String, col: Int)] = []
        var col = 0
        var idx = chordLine.startIndex
        while idx < chordLine.endIndex {
            if chordLine[idx] == " " {
                idx = chordLine.index(after: idx); col += 1
            } else {
                let startCol = col
                var end = idx
                while end < chordLine.endIndex && chordLine[end] != " " {
                    end = chordLine.index(after: end); col += 1
                }
                let token = String(chordLine[idx..<end])
                if isChordToken(token) { positions.append((token, startCol)) }
                idx = end
            }
        }

        let lyricChars = Array(lyricLine)
        return positions.enumerated().map { i, item in
            let start = min(item.col, lyricChars.count)
            let end   = i + 1 < positions.count ? min(positions[i + 1].col, lyricChars.count) : lyricChars.count
            let fragment = start < end ? String(lyricChars[start..<end]) : ""
            return (item.chord, fragment.trimmingCharacters(in: .whitespaces))
        }
    }

    // MARK: - Song assembly

    private static func buildSong(meta: Meta, sections: [ParsedSection]) -> Song? {
        // Collect unique chord names in order of first appearance
        var seen = Set<String>()
        var orderedNames: [String] = []
        for s in sections {
            for ch in s.chords where !seen.contains(ch) {
                orderedNames.append(ch); seen.insert(ch)
            }
        }

        // Build ChordDefinition map
        var defs: [String: ChordDefinition] = [:]
        for name in orderedNames { defs[name] = UkuleleChords.definition(for: name) }

        // Build sections
        let songSections: [SongSection] = sections.map { ps in
            let measures = zip(ps.chords, ps.lyrics).map { ch, lyr in
                SongMeasure(chordId: defs[ch]?.id, lyric: lyr)
            }
            return SongSection(name: ps.name, measures: Array(measures), lineGroupSizes: ps.lineGroupSizes)
        }

        return Song(
            title:   meta.title  ?? "Unknown Title",
            artist:  meta.artist ?? "Unknown Artist",
            instrument: .ukulele,
            tempo:   meta.tempo  ?? 120,
            key:     meta.key    ?? "C",
            chords:  orderedNames.compactMap { defs[$0] },
            strummingPatterns: [],
            sections: songSections
        )
    }
}
