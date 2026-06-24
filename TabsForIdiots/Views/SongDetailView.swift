import SwiftUI
import AVFoundation

enum ChordMatchState {
    case none
    case waiting
    case correct
    case wrong
}

struct SongDetailView: View {
    let song: Song
    @StateObject private var listeningEngine = ListeningEngine()
    @State private var listeningEnabled = false
    @State private var currentMeasureIndex = 0
    @State private var micPermissionDenied = false
    @State private var showListeningToast = false
    // Prevents the lingering sound of a chord from auto-advancing to the next measure.
    // Only resets when stableChord goes nil (silence), not when the measure index changes.
    @State private var lastAdvancedForChord: String? = nil

    private var allMeasures: [(sectionIndex: Int, measure: SongMeasure)] {
        song.sections.enumerated().flatMap { si, section in
            section.measures.map { (si, $0) }
        }
    }

    private var currentMeasure: SongMeasure? {
        guard currentMeasureIndex < allMeasures.count else { return nil }
        return allMeasures[currentMeasureIndex].measure
    }

    private var currentSectionIndex: Int {
        guard currentMeasureIndex < allMeasures.count else { return 0 }
        return allMeasures[currentMeasureIndex].sectionIndex
    }

    private var expectedChordName: String? {
        guard let measure = currentMeasure, let id = measure.chordId else { return nil }
        return song.chords.first(where: { $0.id == id })?.name
    }

    private var matchState: ChordMatchState {
        guard listeningEnabled else { return .none }
        guard let detected = listeningEngine.stableChord else { return .waiting }
        return detected == expectedChordName ? .correct : .wrong
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                LegendView(song: song)
                    .padding()
                    .background(.ultraThinMaterial)

                Divider()

                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(Array(song.sections.enumerated()), id: \.element.id) { sIndex, section in
                                SongSectionView(
                                    section: section,
                                    song: song,
                                    currentMeasureId: currentSectionIndex == sIndex ? currentMeasure?.id : nil,
                                    matchState: currentSectionIndex == sIndex ? matchState : .none,
                                    onJumpTo: listeningEnabled ? jumpToMeasure : nil
                                )
                                .id(section.id)
                            }
                        }
                        .padding()
                        .onChange(of: currentSectionIndex) { _, newSectionIndex in
                            let sections = song.sections
                            if newSectionIndex < sections.count {
                                withAnimation {
                                    proxy.scrollTo(sections[newSectionIndex].id, anchor: .top)
                                }
                            }
                        }
                    }
                }

                if listeningEnabled {
                    Divider()
                    ListeningFeedbackView(
                        engine: listeningEngine,
                        expectedChordName: expectedChordName,
                        song: song
                    )
                    .background(.ultraThinMaterial)
                }
            }

            if showListeningToast {
                ToastView(message: "Chord Detection On")
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: toggleListening) {
                    Image(systemName: listeningEnabled ? "waveform.circle.fill" : "waveform.circle")
                        .font(.title3)
                        .foregroundStyle(listeningEnabled ? .red : .primary)
                }
            }
        }
        .alert("Microphone Access Denied", isPresented: $micPermissionDenied) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable microphone access in Settings to use chord detection.")
        }
        .onReceive(listeningEngine.$stableChord) { chord in
            guard listeningEnabled else { return }
            // Silence clears the restrum guard so the same chord can advance again
            guard let chord else {
                lastAdvancedForChord = nil
                return
            }
            // Require a silence gap before the same chord can advance again
            guard chord != lastAdvancedForChord else { return }
            guard chord == expectedChordName else { return }
            lastAdvancedForChord = chord
            let next = currentMeasureIndex + 1
            if next < allMeasures.count {
                currentMeasureIndex = next
            }
        }
        .onDisappear {
            listeningEngine.stop()
        }
    }

    private func jumpToMeasure(id: UUID) {
        guard let idx = allMeasures.firstIndex(where: { $0.measure.id == id }) else { return }
        currentMeasureIndex = idx
        lastAdvancedForChord = nil
    }

    private func toggleListening() {
        if listeningEnabled {
            listeningEngine.stop()
            listeningEnabled = false
        } else {
            Task {
                let granted = await requestMicPermission()
                await MainActor.run {
                    if granted {
                        listeningEngine.start()
                        listeningEnabled = true
                        currentMeasureIndex = 0
                        lastAdvancedForChord = nil
                        showToast()
                    } else {
                        micPermissionDenied = true
                    }
                }
            }
        }
    }

    private func showToast() {
        withAnimation { showListeningToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showListeningToast = false }
        }
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }
}

// MARK: - Feedback panel

struct ListeningFeedbackView: View {
    @ObservedObject var engine: ListeningEngine
    let expectedChordName: String?
    let song: Song

    private var isCorrect: Bool {
        guard let h = engine.stableChord, let e = expectedChordName else { return false }
        return h == e
    }

    var body: some View {
        HStack(spacing: 0) {
            ChordPanel(
                label: "Hearing",
                chordName: engine.stableChord ?? "—",
                chordDef: song.chords.first(where: { $0.name == engine.stableChord }),
                stringCount: song.instrument.stringCount,
                nameColor: engine.stableChord == nil ? .secondary : (isCorrect ? .green : .red),
                borderColor: engine.stableChord == nil ? .clear : (isCorrect ? .green : .red)
            )

            Divider()

            ChordPanel(
                label: "Playing",
                chordName: expectedChordName ?? "—",
                chordDef: song.chords.first(where: { $0.name == expectedChordName }),
                stringCount: song.instrument.stringCount,
                nameColor: isCorrect ? .green : .primary,
                borderColor: isCorrect ? .green : .clear
            )
        }
        .frame(height: 140)
    }
}

struct ChordPanel: View {
    let label: String
    let chordName: String
    let chordDef: ChordDefinition?
    let stringCount: Int
    let nameColor: Color
    let borderColor: Color

    // Canvas height: 4 frets * 14 + 30 = 86; no name shown inside (showName: false)
    private let diagramH: CGFloat = 86
    private let diagramW: CGFloat = 62  // (4-1)*14+20 for ukulele

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack {
                if let chord = chordDef {
                    ChordDiagramView(chord: chord, stringCount: stringCount, showName: false)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(.separator), lineWidth: 0.5)
                        .frame(width: diagramW, height: diagramH)
                }
            }
            .frame(width: diagramW, height: diagramH)

            Text(chordName)
                .font(.title3.bold())
                .foregroundStyle(nameColor)
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: 2)
                .padding(4)
        )
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(.ultraThinMaterial))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
