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
    @State private var lastAdvanceTime: Date = .distantPast
    @State private var chordWentSilentSinceAdvance = true
    @State private var cleanupTask: Task<Void, Never>? = nil
    @State private var tempoEnabled = true
    @State private var userTempo: Int
    // Playing column: keeps the exiting measure green for ~0.8 s after advance.
    @State private var lastCorrectMeasureIndex: Int? = nil
    // Hearing column: same ForEach/offset mechanism as the Playing column.
    // hearingSlot increments on each advance; the SAME card that was at pos=0
    // (full size, live detection) becomes pos=-1 (small, green) after the slide.
    @State private var hearingSlot: Int = 0
    @State private var hearingHistory: [Int: String] = [:]   // slot → chord name
    @State private var lastCorrectHearingSlot: Int? = nil
    // After advancing, suppress live detection display for 0.6 s so the lingering
    // ring from the previous chord doesn't appear in the new center slot as red.
    @State private var heardChordBlocked = false

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
        listeningEnabled || displayMode != .chordsOnly
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
        .onChange(of: displayMode)         { _, _ in syncTempo() }
        .onChange(of: tempoEnabled)        { _, _ in syncTempo() }
        .onChange(of: userTempo)           { _, _ in syncTempo() }
        .onChange(of: currentMeasureIndex) { _, _ in syncTempo() }
        .onChange(of: listeningEnabled) { _, enabled in
            if !enabled { cancelCleanup() }
        }
        .onDisappear {
            listeningEngine.stop()
            tempoEngine.stop()
            cancelCleanup()
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
                    heardChordName: listeningEngine.stableChord,
                    heardChordBlocked: heardChordBlocked,
                    hearingSlot: hearingSlot,
                    hearingHistory: hearingHistory,
                    lastCorrectHearingSlot: lastCorrectHearingSlot,
                    lastCorrectMeasureIndex: lastCorrectMeasureIndex
                )
                .padding(.top, 6)
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
        guard listeningEnabled else { return }

        guard let chord else {
            chordWentSilentSinceAdvance = true
            return
        }

        if chord == lastChordThatAdvanced {
            let elapsed = Date().timeIntervalSince(lastAdvanceTime)
            if !chordWentSilentSinceAdvance && elapsed < 2.0 { return }
        }

        guard chord == expectedChordName else { return }

        cancelCleanup()
        chordWentSilentSinceAdvance = false
        lastChordThatAdvanced = chord
        lastAdvanceTime = Date()
        heardChordBlocked = true

        let next = currentMeasureIndex + 1
        let currentSlot = hearingSlot
        // Record what was heard in this slot BEFORE advancing the slot counter,
        // so the same card view (keyed by currentSlot) has its offset change from
        // pos=0 → pos=-1 inside withAnimation — identical to the Playing column.
        hearingHistory[currentSlot] = chord

        withAnimation(.spring(duration: 0.28, bounce: 0.0)) {
            lastCorrectMeasureIndex = currentMeasureIndex
            lastCorrectHearingSlot = currentSlot
            hearingSlot = currentSlot + 1   // drives the Hearing column slide
            if next < allMeasures.count {
                currentMeasureIndex = next
            }
        }

        cleanupTask = Task { @MainActor in
            // Phase 1 (0.6 s): unblock live hearing — ring should be gone.
            try? await Task.sleep(nanoseconds: 600_000_000)
            heardChordBlocked = false

            // Phase 2 (0.2 s later = 0.8 s total): fade green out of both columns.
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                lastCorrectMeasureIndex = nil
                lastCorrectHearingSlot = nil
                hearingHistory.removeValue(forKey: currentSlot)
            }
        }
    }

    private func cancelCleanup() {
        cleanupTask?.cancel()
        cleanupTask = nil
    }

    private func syncTempo() {
        if displayMode != .chordsOnly && tempoEnabled, let pattern = currentStrummingPattern {
            tempoEngine.start(bpm: Double(userTempo), strokeCount: pattern.strokes.count)
        } else {
            tempoEngine.stop()
        }
    }

    private func jumpToMeasure(id: UUID) {
        cancelCleanup()
        guard let idx = allMeasures.firstIndex(where: { $0.measure.id == id }) else { return }
        currentMeasureIndex = idx
        lastChordThatAdvanced = nil
        lastAdvanceTime = .distantPast
        chordWentSilentSinceAdvance = true
        lastCorrectMeasureIndex = nil
        hearingSlot = 0
        hearingHistory = [:]
        lastCorrectHearingSlot = nil
        heardChordBlocked = false
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
                        lastAdvanceTime = .distantPast
                        chordWentSilentSinceAdvance = true
                        lastCorrectMeasureIndex = nil
                        hearingSlot = 0
                        hearingHistory = [:]
                        lastCorrectHearingSlot = nil
                        heardChordBlocked = false
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

// MARK: - Chord teleprompter (two-column: Hearing | Playing)

struct ChordTeleprompterView: View {
    let song: Song
    let currentMeasureIndex: Int
    let allMeasures: [(sectionIndex: Int, measure: SongMeasure)]
    let matchState: ChordMatchState
    let heardChordName: String?
    let heardChordBlocked: Bool
    // Hearing column uses the same ForEach/offset mechanism as Playing column.
    // hearingSlot is the "current" slot index; hearingHistory maps past slots to
    // chord names.  When hearingSlot increments, the card at pos=0 (full size)
    // automatically animates to pos=-1 (small, green) via .animation on the ZStack.
    let hearingSlot: Int
    let hearingHistory: [Int: String]
    let lastCorrectHearingSlot: Int?
    let lastCorrectMeasureIndex: Int?

    private let cardAreaHeight: CGFloat = 200
    private let slotSpacing: CGFloat = 88

    private var effectiveHeardName: String? {
        heardChordBlocked ? nil : heardChordName
    }

    private var heardDef: ChordDefinition? {
        song.chords.first(where: { $0.name == effectiveHeardName })
    }

    private var hearingIndices: [Int] {
        var result = [hearingSlot]
        let prev = hearingSlot - 1
        if hearingHistory[prev] != nil { result.insert(prev, at: 0) }
        return result
    }

    private var playingIndices: [Int] {
        let lo = max(0, currentMeasureIndex - 1)
        let hi = min(allMeasures.count - 1, currentMeasureIndex + 1)
        guard lo <= hi else { return [] }
        return Array(lo...hi)
    }

    private func expectedInfo(at idx: Int) -> (name: String, def: ChordDefinition?) {
        guard idx >= 0, idx < allMeasures.count,
              let id = allMeasures[idx].measure.chordId,
              let chord = song.chords.first(where: { $0.id == id })
        else { return ("", nil) }
        return (chord.name, chord)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {

            // ── Hearing column ──────────────────────────────────────────
            // The ForEach is keyed on hearingSlot index, so the SAME card
            // view that was showing the live chord at pos=0 (full size) slides
            // to pos=-1 (smaller, green) when hearingSlot increments — exactly
            // mirroring how the Playing column works.
            VStack(spacing: 0) {
                columnLabel("Hearing")

                ZStack {
                    ForEach(hearingIndices, id: \.self) { idx in
                        let pos = idx - hearingSlot       // -1 or 0
                        let isCurrent = pos == 0
                        let isGreen = idx == lastCorrectHearingSlot

                        let scale: CGFloat  = isCurrent ? 1.0 : 0.70
                        let opacity: Double = isCurrent ? 1.0 : (isGreen ? 0.88 : 0.20)
                        let yOff: CGFloat   = CGFloat(pos) * slotSpacing

                        let name: String = isCurrent
                            ? (effectiveHeardName ?? "—")
                            : (hearingHistory[idx] ?? "—")
                        let def: ChordDefinition? = isCurrent
                            ? heardDef
                            : song.chords.first(where: { $0.name == hearingHistory[idx] })
                        let nameColor: Color = {
                            if isGreen   { return .green }
                            if isCurrent {
                                switch matchState {
                                case .correct: return .green
                                case .wrong:   return heardChordBlocked ? .secondary : .red
                                default:       return .primary
                                }
                            }
                            return .secondary
                        }()

                        ChordCard(
                            name: name,
                            def: def,
                            stringCount: song.instrument.stringCount,
                            nameColor: nameColor,
                            showListeningIcon: isCurrent && effectiveHeardName == nil
                        )
                        .scaleEffect(scale)
                        .opacity(opacity)
                        .offset(y: yOff)
                        .zIndex(isCurrent ? 1 : 0)
                    }
                }
                .frame(height: cardAreaHeight)
                .clipped()
                .animation(.spring(duration: 0.28, bounce: 0.0), value: hearingSlot)
                .animation(.easeOut(duration: 0.30),              value: lastCorrectHearingSlot)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 0.5, height: cardAreaHeight + 22)

            // ── Playing column ──────────────────────────────────────────
            VStack(spacing: 0) {
                columnLabel("Playing")

                ZStack {
                    ForEach(playingIndices, id: \.self) { idx in
                        let pos = idx - currentMeasureIndex
                        let isCurrent = pos == 0
                        let isExiting = idx == lastCorrectMeasureIndex && !isCurrent
                        let (name, def) = expectedInfo(at: idx)

                        let scale: CGFloat  = isCurrent ? 1.0 : 0.70
                        let opacity: Double = isCurrent ? 1.0 : (isExiting ? 0.88 : 0.20)
                        let yOff: CGFloat   = CGFloat(pos) * slotSpacing

                        let nameColor: Color = {
                            if isCurrent && matchState == .correct { return .green }
                            if isExiting                           { return .green }
                            if isCurrent                           { return .primary }
                            return .secondary
                        }()

                        ChordCard(
                            name: name.isEmpty ? "—" : name,
                            def: def,
                            stringCount: song.instrument.stringCount,
                            nameColor: nameColor,
                            showListeningIcon: false
                        )
                        .scaleEffect(scale)
                        .opacity(opacity)
                        .offset(y: yOff)
                        .zIndex(isCurrent ? 1 : 0)
                    }
                }
                .frame(height: cardAreaHeight)
                .clipped()
                .animation(.spring(duration: 0.28, bounce: 0.0), value: currentMeasureIndex)
                .animation(.easeOut(duration: 0.30),              value: lastCorrectMeasureIndex)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
    }

    private func columnLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .frame(height: 22)
    }
}

// MARK: - Chord card

struct ChordCard: View {
    let name: String
    let def: ChordDefinition?
    let stringCount: Int
    let nameColor: Color
    let showListeningIcon: Bool

    var body: some View {
        VStack(spacing: 4) {
            if let chord = def {
                ChordDiagramView(chord: chord, stringCount: stringCount, showName: false)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(.separator), lineWidth: 1)
                        .frame(width: 62, height: 86)
                    if showListeningIcon {
                        Image(systemName: "waveform")
                            .foregroundStyle(.secondary.opacity(0.3))
                            .font(.title2)
                    } else {
                        Text("?")
                            .font(.title3)
                            .foregroundStyle(.secondary.opacity(0.45))
                    }
                }
            }
            Text(name)
                .font(.title3.bold())
                .foregroundStyle(nameColor)
        }
    }
}

// MARK: - Strumming metronome

struct StrummingMetronomeView: View {
    let pattern: StrummingPattern
    let currentStrokeIndex: Int  // -1 = tempo off: show pattern without highlighting

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
