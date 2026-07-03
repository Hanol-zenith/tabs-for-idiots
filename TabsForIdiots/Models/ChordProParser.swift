import Foundation

struct ChordProParser {

    // MARK: - Public API

    static func parse(url: URL) -> Song? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text: text)
    }

    static func title(of url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("{"), t.hasSuffix("}") else { continue }
            let inner = String(t.dropFirst().dropLast())
            guard let colon = inner.firstIndex(of: ":") else { continue }
            let key = inner[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let val = inner[inner.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if key == "title" { return val }
        }
        return nil
    }

    // MARK: - OpenClaw format pre-processor
    // Handles two OpenClaw conventions so the main parser can work with them:
    //   • "Strumming Patterns:" block → {strum:} directives
    //   • Pattern-name annotation lines → {pattern:} directives (| separated for multi-word names)
    //   • ∆7 → maj7 normalisation (jazz delta major-7 symbol)
    private static func preprocess(_ text: String) -> String {
        // Normalise ∆7 (U+2206, mathematical delta = major 7 in jazz) → maj7
        let text = text.replacingOccurrences(of: "\u{2206}7", with: "maj7")

        let rawLines = text.components(separatedBy: .newlines)

        // Pass 1: extract named pattern definitions from "Strumming Patterns:" block
        var patternNames = Set<String>()
        var strumDirectives: [String] = []
        var inStrumBlock = false
        var strumLineIndices = Set<Int>()

        for (i, line) in rawLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("strumming pattern") && t.hasSuffix(":") {
                inStrumBlock = true
                strumLineIndices.insert(i)
                continue
            }
            if inStrumBlock {
                if t.isEmpty { inStrumBlock = false; continue }
                if let colon = t.firstIndex(of: ":") {
                    let name = String(t[..<colon]).trimmingCharacters(in: .whitespaces)
                    let strokes = String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    patternNames.insert(name)
                    strumDirectives.append("{strum: \(name) | \(strokes)}")
                    strumLineIndices.insert(i)
                } else {
                    inStrumBlock = false
                }
            }
        }

        guard !patternNames.isEmpty else { return text }

        // Greedy left-to-right match of a string against known (possibly multi-word) pattern names.
        // Returns the matched sequence or nil if the string contains non-pattern tokens.
        let sortedNames = patternNames.sorted { $0.count > $1.count }
        func greedyMatchPatterns(_ s: String) -> [String]? {
            var result: [String] = []
            var rem = s
            while !rem.isEmpty {
                var matched = false
                for name in sortedNames {
                    if rem == name {
                        result.append(name); rem = ""; matched = true; break
                    }
                    if rem.hasPrefix(name + " ") {
                        result.append(name)
                        rem = String(rem.dropFirst(name.count + 1))
                        matched = true; break
                    }
                }
                if !matched { return nil }
            }
            return result.isEmpty ? nil : result
        }

        // Pass 2: rebuild, removing strum-block lines; converting annotation lines to {pattern:}
        // Pattern names are joined with | to preserve multi-word names (e.g. "2 Strum").
        var result: [String] = []
        var lastMetaIdx = -1

        for (i, line) in rawLines.enumerated() {
            if strumLineIndices.contains(i) { continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, let patterns = greedyMatchPatterns(t) {
                result.append("{pattern: \(patterns.joined(separator: "|"))}")
                continue
            }
            result.append(line)
            if t.hasPrefix("{") && t.hasSuffix("}") { lastMetaIdx = result.count - 1 }
        }

        let insertAt = lastMetaIdx >= 0 ? lastMetaIdx + 1 : 0
        result.insert(contentsOf: strumDirectives, at: min(insertAt, result.count))
        return result.joined(separator: "\n")
    }

    static func parse(text: String) -> Song? {
        var lines = preprocess(text).components(separatedBy: .newlines)

        // Strip ukutabs.com disclaimer
        if let cut = lines.firstIndex(where: { $0.contains("contributor's own interpretation") }) {
            lines = Array(lines[..<cut])
        }

        var meta = Meta()
        var sections: [ParsedSection] = []
        var current: ParsedSection? = nil
        var pendingChordLine: String? = nil
        var autoSectionCount = 0

        func nextAutoName() -> String {
            autoSectionCount += 1
            return autoSectionCount == 1 ? "Verse" : "Verse \(autoSectionCount)"
        }

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
                let inner = String(t.dropFirst().dropLast())
                if let colon = inner.firstIndex(of: ":") {
                    let key = inner[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let val = inner[inner.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if key == "pattern" {
                        // Assign named patterns to the last N measures in the current section.
                        // Names are | separated to support multi-word patterns like "2 Strum".
                        flushChordLine()
                        let tokens = val.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        if var sec = current, !tokens.isEmpty {
                            let n = min(tokens.count, sec.chords.count)
                            let base = sec.chords.count - n
                            while sec.patternAssignments.count < sec.chords.count { sec.patternAssignments.append(nil) }
                            for i in 0..<n { sec.patternAssignments[base + i] = tokens[i] }
                            current = sec
                        }
                        continue
                    }
                }
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

            // Empty line — close current section so blank lines between verses split sections
            if t.isEmpty { closeSection(); continue }

            // Chord line vs lyric line
            // Paren format: (Chord)lyric text (Chord2)lyric text — chords and lyrics on same line
            if isParenChordLine(t) {
                flushChordLine()
                if current == nil { current = ParsedSection(name: nextAutoName()) }
                if let pairs = extractParenPairs(line: t), !pairs.isEmpty {
                    for (ch, lyr) in pairs {
                        current!.chords.append(ch)
                        current!.lyrics.append(lyr)
                    }
                    current!.lineGroupSizes.append(pairs.count)
                }
            } else if isChordLine(t) {
                flushChordLine()
                if current == nil { current = ParsedSection(name: nextAutoName()) }
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
        var strummingPatterns: [StrummingPattern] = []
    }

    private struct ParsedSection {
        var name: String
        var chords: [String] = []
        var lyrics: [String] = []
        var lineGroupSizes: [Int] = []
        var patternAssignments: [String?] = []  // parallel to chords/lyrics; nil = no assignment
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
        case "tempo":  meta.tempo  = val.components(separatedBy: .whitespaces).first.flatMap { Int($0) }
        case "strum":
            if let p = parseStrum(val, index: meta.strummingPatterns.count) {
                meta.strummingPatterns.append(p)
            }
        default: break
        }
    }

    // {strum: Island | D D U U D U}
    private static func parseStrum(_ val: String, index: Int) -> StrummingPattern? {
        let parts = val.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let name = parts.count == 2 ? parts[0] : "Pattern \(index + 1)"
        let strokeStr = parts.count == 2 ? parts[1] : parts[0]
        let strokes: [StrummingPattern.Stroke] = strokeStr.split(separator: " ").compactMap { token in
            switch token.uppercased() {
            case "D": return .down
            case "U": return .up
            default: return nil
            }
        }
        guard !strokes.isEmpty else { return nil }
        return StrummingPattern(name: name, strokes: strokes)
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

    // MARK: - Paren chord line detection (inline format: (Chord)lyric text)

    private static func isParenChordLine(_ t: String) -> Bool {
        guard t.contains("(") else { return false }
        var i = t.startIndex
        while i < t.endIndex {
            if t[i] == "(" {
                let afterOpen = t.index(after: i)
                if let closeIdx = t[afterOpen...].firstIndex(of: ")") {
                    let inner = String(t[afterOpen..<closeIdx]).trimmingCharacters(in: .whitespaces)
                    if isChordToken(inner) { return true }
                    i = t.index(after: closeIdx)
                } else { break }
            } else { i = t.index(after: i) }
        }
        return false
    }

    // Extract (chord, lyric) pairs from an inline paren-format line.
    // Each chord's lyric runs from after its ) to the opening ( of the next chord.
    private static func extractParenPairs(line: String) -> [(chord: String, lyric: String)]? {
        var positions: [(chord: String, openIdx: String.Index, endIdx: String.Index)] = []
        var i = line.startIndex
        while i < line.endIndex {
            if line[i] == "(" {
                let afterOpen = line.index(after: i)
                if let closeIdx = line[afterOpen...].firstIndex(of: ")") {
                    let chordStr = String(line[afterOpen..<closeIdx]).trimmingCharacters(in: .whitespaces)
                    if isChordToken(chordStr) {
                        positions.append((chord: chordStr, openIdx: i, endIdx: line.index(after: closeIdx)))
                    }
                    i = line.index(after: closeIdx)
                } else { i = line.index(after: i) }
            } else { i = line.index(after: i) }
        }
        guard !positions.isEmpty else { return nil }
        return positions.enumerated().map { idx, pos in
            let lyricStart = pos.endIdx
            let lyricEnd = idx + 1 < positions.count ? positions[idx + 1].openIdx : line.endIndex
            let lyric = lyricStart < lyricEnd ? String(line[lyricStart..<lyricEnd]).trimmingCharacters(in: .whitespaces) : ""
            return (chord: pos.chord, lyric: lyric)
        }
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
            let start = i == 0 ? 0 : min(item.col, lyricChars.count)
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
            let measures = zip(ps.chords, ps.lyrics).enumerated().map { idx, pair in
                let (ch, lyr) = pair
                let patternName = idx < ps.patternAssignments.count ? ps.patternAssignments[idx] : nil
                let patternId = patternName.flatMap { name in
                    meta.strummingPatterns.first { $0.name == name }?.id
                }
                return SongMeasure(chordId: defs[ch]?.id, strummingPatternId: patternId, lyric: lyr)
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
            strummingPatterns: meta.strummingPatterns,
            sections: songSections
        )
    }
}
