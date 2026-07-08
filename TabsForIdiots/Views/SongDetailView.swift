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
    let readOnly: Bool

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
    @State private var showSettings = false
    @State private var showSongEndAlert = false
    @AppStorage("alwaysResumePosition") private var alwaysResumePosition = false
    @State private var legendExpanded = true
    @State private var tempoEnabled = true
    @State private var userTempo: Int
    @State private var sessionStart: Date? = nil
    // Playing column: keeps the exiting measure green for ~0.8 s after advance.
    @State private var lastCorrectMeasureIndex: Int? = nil
    // Hearing column: same ForEach/offset mechanism as the Playing column.
    // hearingSlot is the *current* slot index; it increments 250 ms after each
    // correct advance so the card has time to sit full-size and green first.
    @State private var hearingSlot: Int = 0
    @State private var hearingHistory: [Int: String] = [:]
    @State private var lastCorrectHearingSlot: Int? = nil
    // Slot whose increment is queued for 250 ms — flushed immediately if the
    // next advance fires before the delay expires.
    @State private var pendingHearingSlot: Int? = nil
    // Suppresses the hearing display after an advance until silence OR a
    // different chord is detected, so the lingering ring of the old chord
    // cannot appear in the new center slot.
    @State private var heardChordBlocked = false
    @State private var selectedPatternId: UUID? = nil

    init(song: Song, readOnly: Bool = false) {
        self.song = song
        self.readOnly = readOnly
        _listeningEngine = StateObject(wrappedValue: ListeningEngine())
        _tempoEngine = StateObject(wrappedValue: TempoEngine())
        let key = song.title
        let savedBPM = UserDefaults.standard.integer(forKey: "bpm-\(key)")
        _userTempo = State(initialValue: savedBPM > 0 ? savedBPM : song.tempo)
        let savedEnabled = UserDefaults.standard.object(forKey: "tempoEnabled-\(key)") as? Bool
        _tempoEnabled = State(initialValue: savedEnabled ?? true)
        _selectedPatternId = State(initialValue: song.strummingPatterns.first?.id)
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
        if let measure = currentMeasure,
           let id = measure.strummingPatternId,
           let p = song.strummingPatterns.first(where: { $0.id == id }) {
            return p
        }
        if let selectedId = selectedPatternId {
            return song.strummingPatterns.first(where: { $0.id == selectedId })
        }
        return nil
    }

    private var showBottomPanel: Bool {
        listeningEnabled || displayMode != .chordsOnly
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var titleRow: some View {
        HStack {
            Text(song.title)
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { legendExpanded.toggle() }
            } label: {
                Image(systemName: legendExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var legendSection: some View {
        if legendExpanded {
            LegendView(song: song, selectedPatternId: $selectedPatternId)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .top).combined(with: .opacity))
            Divider()
                .transition(.opacity)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                titleRow

                Divider()

                legendSection

                ModePicker(selection: $displayMode, pickingAvailable: song.hasPickingData)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))

                Divider()

                PersistentScrollView(axes: .vertical) {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: 24) {
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
                        .onChange(of: currentSectionIndex) { oldSec, newSec in
                            let sections = song.sections
                            guard newSec < sections.count else { return }
                            if newSec >= oldSec {
                                // Forward / jump: top of the new section
                                withAnimation(.easeOut(duration: 0.12)) {
                                    proxy.scrollTo(sections[newSec].id, anchor: .top)
                                }
                            } else {
                                // Backward across section boundary: land near the current
                                // measure inside the previous section, not its very top.
                                guard currentMeasureIndex < allMeasures.count else { return }
                                let secStart = allMeasures.firstIndex(where: { $0.sectionIndex == newSec }) ?? 0
                                let lineOfCurrent = (currentMeasureIndex - secStart) / 2
                                let anchorLine = max(0, lineOfCurrent - 1)
                                let anchorIdx = secStart + anchorLine * 2
                                guard anchorIdx < allMeasures.count else { return }
                                withAnimation(.easeOut(duration: 0.12)) {
                                    proxy.scrollTo(allMeasures[anchorIdx].measure.id, anchor: .top)
                                }
                            }
                        }
                        // On every line crossing (auto-advance or manual buttons):
                        // anchor to the earlier line so both it and the next are visible.
                        // Going forward → old line at top (user finishes singing it).
                        // Going backward → new (current) line at top (user sees context).
                        // Fast animation keeps up when the user mashes the nav buttons.
                        .onChange(of: currentMeasureIndex) { oldIdx, newIdx in
                            guard listeningEnabled else { return }
                            guard newIdx < allMeasures.count, oldIdx >= 0, oldIdx < allMeasures.count else { return }
                            let newSec = allMeasures[newIdx].sectionIndex
                            let oldSec = allMeasures[oldIdx].sectionIndex
                            guard newSec == oldSec else { return }
                            let secStart = allMeasures.firstIndex(where: { $0.sectionIndex == newSec }) ?? 0
                            let lineNew = (newIdx - secStart) / 2
                            let lineOld = (oldIdx - secStart) / 2
                            guard lineNew != lineOld else { return }
                            let anchorLine = newIdx > oldIdx ? lineOld : lineNew
                            let anchorIdx  = secStart + anchorLine * 2
                            guard anchorIdx < allMeasures.count else { return }
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(allMeasures[anchorIdx].measure.id, anchor: .top)
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !readOnly {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.body)
                        }
                        Button(action: toggleListening) {
                            VStack(spacing: 2) {
                                Image(systemName: listeningEnabled ? "waveform.circle.fill" : "waveform.circle")
                                    .font(.title3)
                                Text(listeningEnabled ? "Stop" : "Listen")
                                    .font(.caption2)
                            }
                            .foregroundStyle(listeningEnabled ? .red : .primary)
                        }
                    }
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
        .alert("Song Complete!", isPresented: $showSongEndAlert) {
            Button("Start Over") {
                withAnimation(.easeOut(duration: 0.2)) {
                    lastCorrectMeasureIndex = nil
                    lastCorrectHearingSlot = nil
                }
                currentMeasureIndex = 0
                lastChordThatAdvanced = nil
                lastAdvanceTime = .distantPast
                chordWentSilentSinceAdvance = true
                resetHearingState()
            }
            Button("Stop Listening", role: .cancel) {
                withAnimation(.easeOut(duration: 0.2)) {
                    lastCorrectMeasureIndex = nil
                    lastCorrectHearingSlot = nil
                }
                UserDefaults.standard.set(0, forKey: "measureIndex-\(song.title)")
                listeningEngine.stop()
                listeningEnabled = false
                currentMeasureIndex = 0
                resetHearingState()
            }
        } message: {
            Text("You've played through the whole song.")
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("When listening starts") {
                        Picker("Start position", selection: $alwaysResumePosition) {
                            Text("From the beginning").tag(false)
                            Text("Resume where I left off").tag(true)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                .navigationTitle("Listening Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showSettings = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onReceive(listeningEngine.$stableChord) { chord in
            handleStableChord(chord)
        }
        .onChange(of: displayMode)         { _, _ in syncTempo() }
        .onChange(of: tempoEnabled)        { _, enabled in
            syncTempo()
            UserDefaults.standard.set(enabled, forKey: "tempoEnabled-\(song.title)")
        }
        .onChange(of: userTempo)           { _, bpm in
            syncTempo()
            UserDefaults.standard.set(bpm, forKey: "bpm-\(song.title)")
        }
        .onChange(of: currentMeasureIndex) { _, _ in syncTempo() }
        .onChange(of: selectedPatternId)   { _, _ in syncTempo() }
        .onChange(of: listeningEnabled) { _, enabled in
            if !enabled { cancelCleanup() }
        }
        .onAppear {
            guard !readOnly else { return }
            let now = Date()
            sessionStart = now
            song.lastPlayedAt = now
        }
        .onDisappear {
            listeningEngine.stop()
            tempoEngine.stop()
            cancelCleanup()
            guard !readOnly else { return }
            UserDefaults.standard.set(currentMeasureIndex, forKey: "measureIndex-\(song.title)")
            if let start = sessionStart {
                let elapsed = Date().timeIntervalSince(start)
                if elapsed >= 15 {
                    song.playCount += 1
                    song.totalPracticeSeconds += elapsed
                }
                sessionStart = nil
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            if listeningEnabled {
                HStack(spacing: 0) {
                    navStepButton(systemImage: "chevron.left")  { stepMeasure(by: -1) }

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

                    navStepButton(systemImage: "chevron.right") { stepMeasure(by: 1) }
                }
                .padding(.top, 6)
            }

            if displayMode != .chordsOnly {
                if listeningEnabled { Divider().padding(.top, 4) }

                if let pattern = currentStrummingPattern {
                    VStack(spacing: 2) {
                        if song.strummingPatterns.count > 1 {
                            Text(pattern.name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.top, 4)
                        }
                        StrummingMetronomeView(
                            pattern: pattern,
                            currentStrokeIndex: tempoEnabled ? tempoEngine.currentStrokeIndex : -1
                        )
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    }
                    .id(pattern.id)
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
            // Silence means the ring has faded — unblock the hearing display.
            heardChordBlocked = false
            return
        }

        // A chord different from the one that just advanced means the user has
        // started a new strum, even without a silence gap — unblock the display.
        if heardChordBlocked && chord != lastChordThatAdvanced {
            heardChordBlocked = false
        }

        if chord == lastChordThatAdvanced {
            let elapsed = Date().timeIntervalSince(lastAdvanceTime)
            if !chordWentSilentSinceAdvance && elapsed < 2.0 { return }
        }

        guard chord == expectedChordName else { return }

        // Flush any pending hearing-slot increment from the previous advance
        // so this advance starts from a clean slot.
        cancelCleanup()

        chordWentSilentSinceAdvance = false
        lastChordThatAdvanced = chord
        lastAdvanceTime = Date()
        heardChordBlocked = true

        let next = currentMeasureIndex + 1
        let currentSlot = hearingSlot          // not changed yet
        hearingHistory[currentSlot] = chord    // record before the slide

        // Phase A (immediate): advance the Playing column and light the Hearing
        // card green at full size.  hearingSlot does NOT change here — the card
        // sits at pos=0 full-size so the user can clearly see "correct".
        withAnimation(.spring(duration: 0.28, bounce: 0.0)) {
            lastCorrectMeasureIndex = currentMeasureIndex
            lastCorrectHearingSlot = currentSlot
            if next < allMeasures.count {
                currentMeasureIndex = next
            }
        }

        if next >= allMeasures.count {
            showSongEndAlert = true
            return
        }

        pendingHearingSlot = currentSlot

        cleanupTask = Task { @MainActor in
            // Phase B (250 ms): slide the Hearing card up to pos=-1.
            // Slightly slower spring so the movement is easy to follow.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                hearingSlot = currentSlot + 1
            }
            pendingHearingSlot = nil

            // Phase C (250 + 800 ms): fade green out of both columns.
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                lastCorrectMeasureIndex = nil
                lastCorrectHearingSlot = nil
            }
        }
    }

    private func cancelCleanup() {
        cleanupTask?.cancel()
        cleanupTask = nil
        // If a hearing-slot increment was queued, flush it now so the slot
        // counter is consistent before the next advance sets its own slot.
        if let pending = pendingHearingSlot {
            hearingSlot = pending + 1
            pendingHearingSlot = nil
        }
    }

    private func syncTempo() {
        if displayMode != .chordsOnly && tempoEnabled, let pattern = currentStrummingPattern {
            tempoEngine.start(bpm: Double(userTempo),
                              strokeCount: pattern.strokes.count,
                              intervals: pattern.intervals)
        } else {
            tempoEngine.stop()
        }
    }

    private func resetHearingState() {
        hearingSlot = 0
        hearingHistory = [:]
        lastCorrectHearingSlot = nil
        pendingHearingSlot = nil
        heardChordBlocked = false
    }

    private func jumpToMeasure(id: UUID) {
        cancelCleanup()
        guard let idx = allMeasures.firstIndex(where: { $0.measure.id == id }) else { return }
        currentMeasureIndex = idx
        lastChordThatAdvanced = nil
        lastAdvanceTime = .distantPast
        chordWentSilentSinceAdvance = true
        lastCorrectMeasureIndex = nil
        resetHearingState()
    }

    private func stepMeasure(by delta: Int) {
        let next = currentMeasureIndex + delta
        guard next >= 0, next < allMeasures.count else { return }
        cancelCleanup()
        currentMeasureIndex = next
        lastChordThatAdvanced = nil
        lastAdvanceTime = .distantPast
        chordWentSilentSinceAdvance = true
        lastCorrectMeasureIndex = nil
        resetHearingState()
    }

    @ViewBuilder
    private func navStepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 36)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleListening() {
        if listeningEnabled {
            UserDefaults.standard.set(currentMeasureIndex, forKey: "measureIndex-\(song.title)")
            listeningEngine.stop()
            listeningEnabled = false
        } else {
            Task {
                let granted = await requestMicPermission()
                await MainActor.run {
                    if granted {
                        listeningEngine.start()
                        listeningEnabled = true
                        if alwaysResumePosition {
                            let saved = UserDefaults.standard.integer(forKey: "measureIndex-\(song.title)")
                            currentMeasureIndex = allMeasures.isEmpty ? 0 : min(max(saved, 0), allMeasures.count - 1)
                        } else {
                            currentMeasureIndex = 0
                        }
                        lastChordThatAdvanced = nil
                        lastAdvanceTime = .distantPast
                        chordWentSilentSinceAdvance = true
                        lastCorrectMeasureIndex = nil
                        resetHearingState()
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
    let hearingSlot: Int
    let hearingHistory: [Int: String]
    let lastCorrectHearingSlot: Int?
    let lastCorrectMeasureIndex: Int?

    private let cardAreaHeight: CGFloat = 200
    private let slotSpacing: CGFloat = 88

    // Live heard chord, suppressed while heardChordBlocked (lingering ring window).
    private var effectiveHeardName: String? {
        heardChordBlocked ? nil : heardChordName
    }

    private var heardDef: ChordDefinition? {
        song.chords.first(where: { $0.name == effectiveHeardName })
    }

    // Include the previous slot only when history exists for it.
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
            //
            // Two-phase animation:
            //   Phase A (immediate): lastCorrectHearingSlot set — card at pos=0
            //     shows GREEN and FULL SIZE so the user can see "correct".
            //   Phase B (250 ms later): hearingSlot increments — the same card
            //     view now has pos=-1 and springs to the smaller "above" slot.
            //
            // heardChordBlocked suppresses live detection display after an advance
            // until silence OR a different chord is detected.  When isCurrent &&
            // isGreen, the card reads from hearingHistory instead so the correct
            // chord is still visible during Phase A even though display is blocked.
            VStack(spacing: 0) {
                columnLabel("Hearing")

                ZStack {
                    ForEach(hearingIndices, id: \.self) { idx in
                        let pos = idx - hearingSlot
                        let isCurrent = pos == 0
                        let isGreen = idx == lastCorrectHearingSlot

                        let scale: CGFloat  = isCurrent ? 1.0 : 0.70
                        let opacity: Double = isCurrent ? 1.0 : (isGreen ? 0.88 : 0.20)
                        let yOff: CGFloat   = CGFloat(pos) * slotSpacing

                        // During Phase A the current card is green and blocked —
                        // read the chord from history so the diagram/name shows.
                        let name: String = {
                            if isCurrent {
                                if isGreen, let h = hearingHistory[idx] { return h }
                                return effectiveHeardName ?? "—"
                            }
                            return hearingHistory[idx] ?? "—"
                        }()

                        let def: ChordDefinition? = {
                            if isCurrent {
                                if isGreen, let h = hearingHistory[idx] {
                                    return song.chords.first(where: { $0.name == h })
                                }
                                return heardDef
                            }
                            return song.chords.first(where: { $0.name == hearingHistory[idx] })
                        }()

                        let nameColor: Color = {
                            if isGreen { return .green }
                            if isCurrent {
                                if heardChordBlocked { return .secondary }
                                switch matchState {
                                case .correct: return .green
                                case .wrong:   return .red
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
                            showListeningIcon: isCurrent && effectiveHeardName == nil && !isGreen
                        )
                        .scaleEffect(scale)
                        .opacity(opacity)
                        .offset(y: yOff)
                        .zIndex(isCurrent ? 1 : 0)
                        .transition(.opacity)
                    }
                }
                .frame(height: cardAreaHeight)
                .clipped()
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: hearingSlot)
                .animation(.easeOut(duration: 0.30), value: lastCorrectHearingSlot)
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
    let currentStrokeIndex: Int

    // Fixed absolute sizes, not proportional to the row's available width —
    // grouped strums always sit `shortGap` apart, spread-out strums always
    // sit `longGap` apart. Patterns without a real short/long distinction
    // (no bar-notation spacing) fall back to the original uniform spacing.
    private let strokeWidth: CGFloat = 40
    private let defaultGap: CGFloat = 12
    private let shortGap: CGFloat = 6
    private let longGap: CGFloat = 22

    private func gapWidth(afterIndex idx: Int, longAfter: [Bool]) -> CGFloat {
        guard longAfter.contains(true) else { return defaultGap }
        return longAfter[idx] ? longGap : shortGap
    }

    // A pause is a lead-in rest, not a strike — render it as plain empty
    // space (no symbol, no label, no highlight) rather than a "·"/"-" glyph.
    @ViewBuilder
    private func strokeContent(_ stroke: StrummingPattern.Stroke, active: Bool) -> some View {
        if stroke == .pause {
            Color.clear
        } else {
            VStack(spacing: 2) {
                Text(stroke.symbol)
                    .font(.system(size: active ? 26 : 20))
                    .foregroundStyle(active ? Color.orange : (stroke.isDown ? Color.primary : Color.blue))
                Text(stroke.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(active ? Color.orange : Color.secondary)
            }
            .padding(.vertical, 6)
            .background(active ? Color.orange.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    var body: some View {
        let longAfter = pattern.longGapAfter
        HStack(spacing: 0) {
            ForEach(Array(pattern.strokes.enumerated()), id: \.offset) { idx, stroke in
                let active = idx == currentStrokeIndex
                // A pause has no glyph of its own; giving it a full stroke-width
                // column too would make the lead-in gap wider than a same-tier
                // gap between two real strokes, so it collapses to width 0 and
                // the gap after it is the only space rendered.
                strokeContent(stroke, active: active)
                    .frame(width: stroke == .pause ? 0 : strokeWidth)
                    .animation(.easeInOut(duration: 0.07), value: currentStrokeIndex)
                if idx < pattern.strokes.count - 1 {
                    Spacer().frame(width: gapWidth(afterIndex: idx, longAfter: longAfter))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Mode picker

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
