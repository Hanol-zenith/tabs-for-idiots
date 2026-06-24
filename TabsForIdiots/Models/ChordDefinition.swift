import Foundation

struct ChordDefinition: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var frets: [Int]
    var fingers: [Int]
    var baseFret: Int

    init(id: UUID = UUID(), name: String, frets: [Int], fingers: [Int], baseFret: Int = 1) {
        self.id = id
        self.name = name
        self.frets = frets
        self.fingers = fingers
        self.baseFret = baseFret
    }

    // Pitch classes (0=C…11=B) for ukulele G C E A tuning (open MIDIs: 67 60 64 69)
    var pitchClasses: Set<Int> {
        let openMIDI = [67, 60, 64, 69]
        var classes = Set<Int>()
        for (i, fret) in frets.enumerated() where fret >= 0 && i < openMIDI.count {
            classes.insert((openMIDI[i] + fret) % 12)
        }
        return classes
    }
}
