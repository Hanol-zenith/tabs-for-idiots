import Foundation

struct ChordRecognizer {
    private let chordDefs: [(name: String, classes: Set<Int>)] = [
        ("C",   [0, 4, 7]),
        ("Cm",  [0, 3, 7]),
        ("C7",  [0, 4, 7, 10]),
        ("D",   [2, 6, 9]),
        ("Dm",  [2, 5, 9]),
        ("D7",  [0, 2, 6, 9]),
        ("E",   [4, 8, 11]),
        ("Em",  [4, 7, 11]),
        ("E7",  [2, 4, 8, 11]),
        ("F",   [0, 5, 9]),
        ("Fm",  [0, 5, 8]),
        ("F7",  [0, 3, 5, 9]),
        ("G",   [2, 7, 11]),
        ("Gm",  [2, 7, 10]),
        ("G7",  [2, 5, 7, 11]),
        ("A",   [1, 4, 9]),
        ("Am",  [0, 4, 9]),
        ("A7",  [1, 4, 7, 9]),
        ("B",   [3, 6, 11]),
        ("Bm",  [2, 6, 11]),
        ("B7",  [3, 6, 9, 11]),
        ("Bb",  [3, 6, 10]),
        ("Bbm", [1, 6, 10]),
    ]

    func identify(peaks: [(pitchClass: Int, magnitude: Float)]) -> (name: String, confidence: Float)? {
        guard !peaks.isEmpty else { return nil }

        // Sum signal power per pitch class (harmonics of the same note share a class).
        var pcMag: [Int: Float] = [:]
        for p in peaks { pcMag[p.pitchClass, default: 0] += p.magnitude }
        let pcSet    = Set(pcMag.keys)
        let totalMag = pcMag.values.reduce(0, +)
        guard totalMag > 0 else { return nil }

        struct Candidate { let name: String; let classes: Set<Int>; let score: Float }
        let ranked: [Candidate] = chordDefs.map { def in
            let matchCount = Float(pcSet.intersection(def.classes).count)
            let recall     = matchCount / Float(def.classes.count)
            // Magnitude-weighted precision: fraction of total signal power that belongs
            // to this chord's notes. A quiet stray resonance barely hurts the score.
            let matchMag  = def.classes.compactMap { pcMag[$0] }.reduce(0, +)
            let precision = matchMag / totalMag
            return Candidate(name: def.name, classes: def.classes, score: recall * 0.7 + precision * 0.3)
        }.sorted { $0.score > $1.score }

        guard let best = ranked.first else { return nil }
        guard let runner = ranked.dropFirst().first else { return (best.name, best.score) }

        if best.score - runner.score >= 0.15 {
            return (best.name, best.score)
        }

        // Near-tie: compare signal power of each chord's exclusive notes.
        // C vs Am: whichever of G or A is louder wins. E7 vs E: D being audible wins.
        let bestExMag   = best.classes.subtracting(runner.classes).compactMap { pcMag[$0] }.reduce(0, +)
        let runnerExMag = runner.classes.subtracting(best.classes).compactMap { pcMag[$0] }.reduce(0, +)
        if bestExMag > runnerExMag { return (best.name, best.score) }
        return nil
    }
}
