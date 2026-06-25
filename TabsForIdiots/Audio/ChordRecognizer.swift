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

    func identify(pitchClasses: Set<Int>) -> (name: String, confidence: Float)? {
        guard !pitchClasses.isEmpty else { return nil }
        var best: (name: String, confidence: Float)? = nil
        for def in chordDefs {
            let intersection = pitchClasses.intersection(def.classes)
            let union = pitchClasses.union(def.classes)
            let score = Float(intersection.count) / Float(union.count)
            if score > (best?.confidence ?? 0) {
                best = (def.name, score)
            }
        }
        return best
    }
}
