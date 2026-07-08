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
        var sawPatternInBlock = false

        for (i, line) in rawLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("strumming pattern") && t.hasSuffix(":") {
                inStrumBlock = true
                sawPatternInBlock = false
                strumLineIndices.insert(i)
                continue
            }
            if inStrumBlock {
                // Tolerate a blank line before the first entry (a stylistic gap
                // after the header); a blank line after at least one entry ends the block.
                if t.isEmpty {
                    if sawPatternInBlock { inStrumBlock = false }
                    continue
                }
                if let colon = t.firstIndex(of: ":") {
                    let name = String(t[..<colon]).trimmingCharacters(in: .whitespaces)
                    let strokes = String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    patternNames.insert(name)
                    strumDirectives.append("{strum: \(name) | \(strokes)}")
                    strumLineIndices.insert(i)
                    sawPatternInBlock = true
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

        lines = expandRepeatedChords(lines)

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
                    for ch in inline { current!.chords.append([ch]); current!.lyrics.append("") }
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
                    for (chs, lyr) in pairs {
                        current!.chords.append(chs)
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
        // One entry per measure; usually one chord, but bracket-grouped chords
        // (e.g. "[(A)...(E)...]") share a single measure and appear together here.
        var chords: [[String]] = []
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
    //
    // Also supports bar notation, where column spacing carries rhythm:
    // {strum: Everyman | |D    D U    U D U |}
    // The number of characters between one stroke and the next becomes that
    // stroke's relative duration (a wide gap = a longer hold), and a gap
    // before the first stroke becomes a leading pause. Plain space-separated
    // lists (no leading "|") keep the old equal-spacing behavior.
    private static func parseStrum(_ val: String, index: Int) -> StrummingPattern? {
        let parts = val.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let name = parts.count == 2 ? parts[0] : "Pattern \(index + 1)"
        var strokeStr = parts.count == 2 ? parts[1] : parts[0]

        guard strokeStr.hasPrefix("|") else {
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

        // Bar notation: drop the enclosing "|" characters but keep every
        // interior space, since their exact column positions are the rhythm.
        strokeStr.removeFirst()
        if strokeStr.hasSuffix("|") { strokeStr.removeLast() }
        let chars = Array(strokeStr)
        guard chars.contains(where: { "DUdu".contains($0) }) else { return nil }

        var strokes: [StrummingPattern.Stroke] = []
        var positions: [Int] = []
        if let firstStrokeIdx = chars.firstIndex(where: { "DUdu".contains($0) }), firstStrokeIdx > 0 {
            strokes.append(.pause)
            positions.append(0)
        }
        for (i, ch) in chars.enumerated() {
            switch String(ch).uppercased() {
            case "D": strokes.append(.down); positions.append(i)
            case "U": strokes.append(.up); positions.append(i)
            default: break
            }
        }

        // Each stroke's raw duration is its column distance to the next stroke
        // (or to the end of the bar). Rather than using that literal distance
        // directly (which can produce an arbitrarily extreme ratio depending
        // on incidental padding, e.g. trailing spaces before a closing "|"),
        // bucket it into two tiers at a fixed 1:2 ratio — strokes written
        // close together ("grouped") all get the same short duration, strokes
        // written far apart ("spaced out") all get the same long duration —
        // then normalize to one 4/4 measure.
        let rawDurations: [Double] = positions.enumerated().map { idx, pos in
            let end = idx + 1 < positions.count ? positions[idx + 1] : chars.count
            return Double(end - pos)
        }
        let minDur = rawDurations.min() ?? 0
        let maxDur = rawDurations.max() ?? 0
        let bucketed: [Double]
        if minDur == maxDur {
            bucketed = rawDurations
        } else {
            let mid = (minDur + maxDur) / 2
            bucketed = rawDurations.map { $0 <= mid ? 1.0 : 2.0 }
        }
        let total = bucketed.reduce(0, +)
        let intervals = total > 0 ? bucketed.map { $0 / total * 4.0 } : []

        return StrummingPattern(name: name, strokes: strokes, intervals: intervals)
    }

    // MARK: - Repeated-chord ("Ex2") expansion
    //
    // "(Chordx2)" (or x3, x4, ...) means that chord is played N times in a row.
    // The first play stays where it is (the "xN" is simply dropped); each
    // remaining play is pushed onto the start of the next body line — unless
    // that line already opens with its own chord, in which case the extra play
    // is appended after the end of the current line's lyric instead.
    private static func expandRepeatedChords(_ lines: [String]) -> [String] {
        var result = lines

        func isBodyLine(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return false }
            if t.hasPrefix("{") && t.hasSuffix("}") { return false }
            if sectionHeader(t) != nil { return false }
            return true
        }

        // First body line at or after `start`; nil if a blank line or section
        // header (i.e. the end of this block) is reached first.
        func nextBodyLineIndex(from start: Int) -> Int? {
            var j = start
            while j < result.count {
                let t = result[j].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || sectionHeader(t) != nil { return nil }
                if t.hasPrefix("{") && t.hasSuffix("}") { j += 1; continue }
                return j
            }
            return nil
        }

        func startsWithChord(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("("), let closeIdx = t.dropFirst().firstIndex(of: ")") else { return false }
            let inner = String(t[t.index(after: t.startIndex)..<closeIdx]).trimmingCharacters(in: .whitespaces)
            return isChordToken(inner) || splitRepeatSuffix(inner) != nil
        }

        for i in result.indices {
            guard isBodyLine(result[i]) else { continue }
            var line = result[i]
            var extras: [String] = []
            while let token = firstRepeatToken(in: line) {
                line.replaceSubrange(token.range, with: "(\(token.chord))")
                extras.append(contentsOf: Array(repeating: token.chord, count: token.count - 1))
            }
            result[i] = line
            guard !extras.isEmpty else { continue }

            var cursor = i + 1
            for chord in extras {
                if let j = nextBodyLineIndex(from: cursor), !startsWithChord(result[j]) {
                    result[j] = "(\(chord))" + result[j]
                    cursor = j + 1
                } else {
                    result[i] += "(\(chord))"
                }
            }
        }
        return result
    }

    // Finds the first "(Chordx2)"-style token in a line: a chord name immediately
    // followed by x<N>, meaning it should be played N times in a row.
    private static func firstRepeatToken(in line: String) -> (range: Range<String.Index>, chord: String, count: Int)? {
        var i = line.startIndex
        while i < line.endIndex {
            if line[i] == "(" {
                let afterOpen = line.index(after: i)
                if let closeIdx = line[afterOpen...].firstIndex(of: ")") {
                    let inner = String(line[afterOpen..<closeIdx]).trimmingCharacters(in: .whitespaces)
                    if let (chord, count) = splitRepeatSuffix(inner) {
                        return (i..<line.index(after: closeIdx), chord, count)
                    }
                    i = line.index(after: closeIdx)
                    continue
                } else { break }
            }
            i = line.index(after: i)
        }
        return nil
    }

    // "Ex2" -> ("E", 2). The part before the x must itself be a valid chord token.
    private static func splitRepeatSuffix(_ s: String) -> (chord: String, count: Int)? {
        guard let xIdx = s.lastIndex(where: { $0 == "x" || $0 == "X" }) else { return nil }
        let chordPart = String(s[s.startIndex..<xIdx])
        let countPart = String(s[s.index(after: xIdx)...])
        guard !chordPart.isEmpty, let count = Int(countPart), count > 1, isChordToken(chordPart) else { return nil }
        return (chordPart, count)
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

    // [ ... ] marks chords that are played within the same measure/strum rather
    // than each getting its own beat, e.g. "[(A)says this as she (E)takes]".
    // Returns the bracket ranges (brackets themselves included) found in the line.
    private static func bracketSpans(in line: String) -> [ClosedRange<String.Index>] {
        var spans: [ClosedRange<String.Index>] = []
        var i = line.startIndex
        while i < line.endIndex {
            if line[i] == "[" {
                let afterOpen = line.index(after: i)
                if let closeIdx = line[afterOpen...].firstIndex(of: "]") {
                    spans.append(i...closeIdx)
                    i = line.index(after: closeIdx)
                    continue
                }
            }
            i = line.index(after: i)
        }
        return spans
    }

    // Extract (chords, lyric) groups from an inline paren-format line.
    // Each chord's lyric runs from after its ) to the opening ( of the next chord.
    // Chords bracket-grouped with [ ] share one measure: their chords are combined
    // and their lyric fragments joined into a single aligned block.
    private static func extractParenPairs(line: String) -> [(chords: [String], lyric: String)]? {
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

        let spans = bracketSpans(in: line)
        func spanIndex(for idx: String.Index) -> Int? {
            spans.firstIndex { $0.contains(idx) }
        }

        // Text following a chord up to the next chord (or line end), with any
        // stray bracket characters stripped since they're structural, not lyrics.
        func fragment(after pos: (chord: String, openIdx: String.Index, endIdx: String.Index), upTo nextOpenIdx: String.Index?) -> String {
            let start = pos.endIdx
            let end = nextOpenIdx ?? line.endIndex
            guard start < end else { return "" }
            return String(line[start..<end])
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespaces)
        }

        var result: [(chords: [String], lyric: String)] = []
        var idx = 0
        while idx < positions.count {
            let span = spanIndex(for: positions[idx].openIdx)
            var groupEnd = idx
            if span != nil {
                while groupEnd + 1 < positions.count, spanIndex(for: positions[groupEnd + 1].openIdx) == span {
                    groupEnd += 1
                }
            }
            let group = Array(positions[idx...groupEnd])
            let fragments = group.enumerated().map { offset, pos -> String in
                let globalIdx = idx + offset
                let nextOpenIdx = globalIdx + 1 < positions.count ? positions[globalIdx + 1].openIdx : nil
                return fragment(after: pos, upTo: nextOpenIdx)
            }
            let lyric = fragments.filter { !$0.isEmpty }.joined(separator: " ")
            result.append((chords: group.map { $0.chord }, lyric: lyric))
            idx = groupEnd + 1
        }
        return result
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
            section!.chords.append([ch])
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
            for chGroup in s.chords {
                for ch in chGroup where !seen.contains(ch) {
                    orderedNames.append(ch); seen.insert(ch)
                }
            }
        }

        // Build ChordDefinition map
        var defs: [String: ChordDefinition] = [:]
        for name in orderedNames { defs[name] = UkuleleChords.definition(for: name) }

        // Build sections
        let songSections: [SongSection] = sections.map { ps in
            let measures = zip(ps.chords, ps.lyrics).enumerated().map { idx, pair in
                let (chGroup, lyr) = pair
                let patternName = idx < ps.patternAssignments.count ? ps.patternAssignments[idx] : nil
                let patternId = patternName.flatMap { name in
                    meta.strummingPatterns.first { $0.name == name }?.id
                }
                let ids = chGroup.compactMap { defs[$0]?.id }
                return SongMeasure(chordIds: ids, strummingPatternId: patternId, lyric: lyr)
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
