import SwiftUI
import AVFoundation

enum ChordMatchState {
    case none       // not listening
    case waiting    // listening, nothing detected yet
    case correct    // detected == expected
    case wrong      // detected something but it's wrong
}

struct SongDetailView: View {
    let song: Song
    @StateObject private var listeningEngine = ListeningEngine()
    @State private var listeningEnabled = false
    @State private var currentMeasureIndex = 0
    @State private var micPermissionDenied = false
    @State private var showListeningToast = false
    @State private var lastAdvancedForChord: String? = nil

    // Flat array of all measures across all sections with their section index
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
        guard let detected = listeningEngine.rawChord else { return .waiting }
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
                                    matchState: currentSectionIndex == sIndex ? matchState : .none
                                )
                                .id(section.id)
                            }
                        }
                        .padding()
                        .onChange(of: currentMeasureIndex) { _, _ in
                            lastAdvancedForChord = nil
                            let sections = song.sections
                            if currentSectionIndex < sections.count {
                                withAnimation {
                                    proxy.scrollTo(sections[currentSectionIndex].id, anchor: .top)
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
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                }
            }

            // Toast banner
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
            guard let chord else { return }
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

    private var detectedChord: ChordDefinition? {
        guard let name = engine.rawChord else { return nil }
        return song.chords.first(where: { $0.name == name })
    }

    private var isCorrect: Bool {
        guard let detected = engine.rawChord, let expected = expectedChordName else { return false }
        return detected == expected
    }

    private var statusColor: Color {
        guard engine.rawChord != nil else { return .secondary }
        return isCorrect ? .green : .red
    }

    var body: some View {
        HStack(spacing: 16) {
            // Detected chord + mini diagram
            VStack(alignment: .center, spacing: 4) {
                Text("Hearing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let name = engine.rawChord {
                    Text(name)
                        .font(.title2.bold())
                        .foregroundStyle(statusColor)
                } else {
                    Text("—")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56)

            if let chord = detectedChord {
                ChordDiagramView(chord: chord, stringCount: song.instrument.stringCount)
                    .scaleEffect(0.75, anchor: .top)
                    .frame(height: 80)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 48, height: 72)
                    .overlay(
                        Text(engine.rawChord != nil ? engine.rawChord! : "?")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    )
            }

            Divider().frame(height: 60)

            // Expected chord
            VStack(alignment: .center, spacing: 4) {
                Text("Playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(expectedChordName ?? "—")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
            }
            .frame(width: 56)

            Spacer()

            // Match icon + confidence
            VStack(spacing: 6) {
                if let _ = engine.rawChord {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(statusColor)
                } else {
                    Image(systemName: "ellipsis.circle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                Text(engine.rawConfidence > 0 ? "\(Int(engine.rawConfidence * 100))%" : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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
