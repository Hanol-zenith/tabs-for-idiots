import Testing
@testable import TabsForIdiots

struct TabsForIdiotsTests {
    @Test func chordRecognizerIdentifiesC() {
        let r = ChordRecognizer()
        let result = r.identify(pitchClasses: [0, 4, 7])
        #expect(result?.name == "C")
    }

    @Test func chordRecognizerIdentifiesAm() {
        let r = ChordRecognizer()
        let result = r.identify(pitchClasses: [9, 0, 4])
        #expect(result?.name == "Am")
    }
}
