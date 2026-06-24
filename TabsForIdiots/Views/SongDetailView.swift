import SwiftUI
import AVFoundation

enum ChordMatchState {
    case none, waiting, correct, wrong
}

enum DisplayMode: String, CaseIterable {
    case chordsOnly         = "Chords"
    case chordsAndStrumming = "+ Strum"
    case chordsAndPicking   = "+ Picking"
}

struct SongDetailView: View {
    let song: Song

    @StateObject private var listeningEngine: ListeningEngine
    @StateObject private var tempoEngine: TempoEngine

    @State private var listeningEnabled = false
    @State private var displayMode: DisplayMode = .chordsOnly
    @State private var currentMeasureIndex = 0
    @State private var micPermissionDenied = false
    @State private var showListeningToast = false
    @State private var lastChordThatAdvanced: String? = nil
    @State private var advanceCooldownUntil: Date = .distantPast
    @State private var advanceTask: Task<Void, Never>? = nil
    @State private var tempoEnabled = true
    @State private var userTempo: Int

    init(song: Song) {
        self.song = song
        _listeningEngine = StateObject(wrappedValue: ListeningEngine())
        _tempoEngine = StateObject(wrappedValue: TempoEngine())
        _userTempo = State(initialValue: song.tempo)
    }

    // MARK: - Computed helpers

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

    private var currentStrummingPattern: StrummingPattern? {
        guard let measure = currentMeasure,
              let id = measure.strummingPatternId else { return nil }
        return song.strummingPatterns.first(where: { $0.id == id })
    }

    private var showBottomPanel: Bool {
        listeningEnabled || (displayMode != .chordsOnly && tempoEnabled)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                LegendView(song: song)
                    .padding()
                    .background(.ultraThinMaterial)

                Divider()

                ModePicker(selection: $displayMode, pickingAvailable: song.hasPickingData)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))

                Divider()

                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(Array(song.sections.enumerated()), id: \.element.id) { sIndex, section in
                                SongSectionView(
                                    section: section,
                                    song: song,
                                    displayMode: displayMode,
                                    currentMeasureId: currentSectionIndex == sIndex ? currentMeasure?.id : nil,
                                    matchState: currentSectionIndex == sIndex ? matchState : .none,
                                    onJumpTo: listeningEnabled ? jumpToMeasure : nil
                                )
                                .id(section.id)
                            }
                        }
                        .padding()
                        .onChange(of: currentSectionIndex) { _, newIdx in
                            let sections = song.sections
                            if newIdx < sections.count {
                                withAnimation {
                                    proxy.scrollTo(sections[newIdx].id, anchor: .top)
                                }
                            }
                        }
                    }
                }

                if showBottomPanel {
                    Divider()
                    bottomPanel
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
            handleStableChord(chord)
        }
        .onChange(of: displayMode)        { _, _ in syncTempo() }
        .onChange(of: tempoEnabled)       { _, _ in syncTempo() }
        .onChange(of: userTempo)          { _, _ in syncTempo() }
        .onChange(of: currentMeasureIndex){ _, _ in syncTempo() }
        .onChange(of: listeningEnabled)   { _, enabled in
            if !enabled { cancelAdvance() }
        }
        .onDisappear {
            listeningEngine.stop()
            tempoEngine.stop()
            cancelAdvance()
        }
    }

    // MARK: - Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            if listeningEnabled {
                ChordTeleprompterView(
                    song: song,
                    currentMeasureIndex: currentMeasureIndex,
                    allMeasures: allMeasures,
                    matchState: matchState,
                    heardChordName: listeningEngine.stableChord
                )
                .padding(.top, 8)
            }

            if displayMode != .chordsOnly {
                if listeningEnabled { Divider().padding(.top, 4) }

                if let pattern = currentStrummingPattern {
                    StrummingMetronomeView(
                        pattern: pattern,
                        currentStrokeIndex: tempoEnabled ? tempoEngine.currentStrokeIndex : -1
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                } else {
                    Text("No strumming pattern for this section")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }

                Divider()
                TempoControlsView(bpm: $userTempo, enabled: $tempoEnabled)
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Advance logic

    private func handleStableChord(_ chord: String?) {
        cancelAdvance()
        guard listeningEnabled, let chord else { return }
        if chord == lastChordThatAdvanced && Date() < advanceCooldownUntil { return }
        guard chord == expectedChordName else { return }

        // Brief window to show green, then advance immediately into the slide animation
        let captured = chord
        advanceTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
            lastChordThatAdvanced = captured
            advanceCooldownUntil = Date().addingTimeInterval(0.4)
            advanceTask = nil
            let next = currentMeasureIndex + 1
            if next < allMeasures.count { currentMeasureIndex = next }
        }
    }

    private func cancelAdvance() {
        advanceTask?.cancel()
        advanceTask = nil
    }

    private func syncTempo() {
        if displayMode != .chordsOnly && tempoEnabled, let pattern = currentStrummingPattern {
            tempoEngine.start(bpm: Double(userTempo), strokeCount: pattern.strokes.count)
        } else {
            tempoEngine.stop()
        }
    }

    private func jumpToMeasure(id: UUID) {
        cancelAdvance()
        guard let idx = allMeasures.firstIndex(where: { $0.measure.id == id }) else { return }
        currentMeasureIndex = idx
        lastChordThatAdvanced = nil
        advanceCooldownUntil = .distantPast
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
                        lastChordThatAdvanced = nil
                        advanceCooldownUntil = .distantPast
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

// MARK: - Chord teleprompter

struct ChordTeleprompterView: View {
    let song: Song
    let currentMeasureIndex: Int
    let allMeasures: [(sectionIndex: Int, measure: SongMeasure)]
    let matchState: ChordMatchState
    let heardChordName: String?

    private func chordInfo(at idx: Int) -> (name: String, def: ChordDefinition?) {
        guard idx >= 0, idx < allMeasures.count,
              let id = allMeasures[idx].measure.chordId,
              let chord = song.chords.first(where: { $0.id == id })
        else { return ("", nil) }
        return (chord.name, chord)
    }

    var body: some View {
        let lo = max(0, currentMeasureIndex - 1)
        let hi = min(allMeasures.count - 1, currentMeasureIndex + 1)
        let indices = lo <= hi ? Array(lo...hi) : []

        ZStack {
            ForEach(indices, id: \.self) { idx in
                let pos = idx - currentMeasureIndex   // -1, 0, or 1
                let isCurrent = pos == 0
                let (name, def) = chordInfo(at: idx)
                let scale: CGFloat   = isCurrent ? 1.0  : 0.50
                let opacity: Double  = isCurrent ? 1.0  : (pos < 0 ? 0.15 : 0.40)
                let yOff: CGFloat    = CGFloat(pos) * 98

                VStack(spacing: 4) {
                    if let chord = def {
                        ChordDiagramView(chord: chord,
                                         stringCount: song.instrument.stringCount,
                                         showName: false)
                    } else {
                        Color.clear.frame(width: 62, height: 86)
                    }

                    Text(name.isEmpty ? "—" : name)
                        .font(isCurrent ? .title2.bold() : .footnote)
                        .foregroundStyle(
                            isCurrent && matchState == .correct ? Color.green : (isCurrent ? .primary : .secondary)
                        )

                    // Hearing badge — only on current chord, only when different from expected
                    if isCurrent, let heard = heardChordName, heard != name, !name.isEmpty {
                        Text("Hearing: \(heard)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .scaleEffect(scale)
                .opacity(opacity)
                .offset(y: yOff)
            }
        }
        .frame(height: 145)
        .clipped()
        .animation(.spring(duration: 0.28, bounce: 0.0), value: currentMeasureIndex)
    }
}

// MARK: - Strumming metronome

struct StrummingMetronomeView: View {
    let pattern: StrummingPattern
    let currentStrokeIndex: Int  // -1 means tempo off

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(pattern.strokes.enumerated()), id: \.offset) { idx, stroke in
                let active = idx == currentStrokeIndex
                VStack(spacing: 2) {
                    Text(stroke.symbol)
                        .font(.system(size: active ? 26 : 20))
                        .foregroundStyle(active ? Color.orange : (stroke.isDown ? Color.primary : Color.blue))
                    Text(stroke.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(active ? Color.orange : Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(active ? Color.orange.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .animation(.easeInOut(duration: 0.07), value: currentStrokeIndex)
            }
        }
    }
}

// MARK: - Tempo controls

struct TempoControlsView: View {
    @Binding var bpm: Int
    @Binding var enabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "metronome.fill")
                .foregroundStyle(enabled ? Color.accentColor : .secondary)

            if enabled {
                Button { bpm = max(40, bpm - 5) } label: {
                    Image(systemName: "minus.circle.fill").font(.title3)
                }
                Text("\(bpm)")
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .frame(width: 44, alignment: .center)
                Button { bpm = min(240, bpm + 5) } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                Text("BPM").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Tempo off").font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $enabled).labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Mode picker (custom, supports disabled state)

struct ModePicker: View {
    @Binding var selection: DisplayMode
    let pickingAvailable: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(DisplayMode.allCases.enumerated()), id: \.offset) { i, mode in
                let disabled = mode == .chordsAndPicking && !pickingAvailable
                let selected = selection == mode

                Button {
                    if !disabled { selection = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(selected ? Color.accentColor : Color.clear)
                        .foregroundStyle(
                            disabled ? Color.secondary.opacity(0.35) :
                            selected  ? Color.white : Color.primary
                        )
                }
                .disabled(disabled)

                if i < DisplayMode.allCases.count - 1 {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 0.5, height: 28)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separator), lineWidth: 0.5))
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Capsule().fill(.ultraThinMaterial))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
