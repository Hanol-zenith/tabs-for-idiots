import SwiftUI
import AVFoundation

struct SongDetailView: View {
    let song: Song
    @StateObject private var listeningEngine = ListeningEngine()
    @State private var listeningEnabled = false
    @State private var currentSectionIndex = 0
    @State private var micPermissionDenied = false

    var body: some View {
        VStack(spacing: 0) {
            LegendView(song: song)
                .padding()
                .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(Array(song.sections.enumerated()), id: \.element.id) { index, section in
                            SongSectionView(
                                section: section,
                                song: song,
                                isCurrent: index == currentSectionIndex && listeningEnabled
                            )
                            .id(section.id)
                        }
                    }
                    .padding()
                    .onChange(of: currentSectionIndex) { _, newIndex in
                        if newIndex < song.sections.count {
                            withAnimation {
                                proxy.scrollTo(song.sections[newIndex].id, anchor: .top)
                            }
                        }
                    }
                }
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
        .onReceive(listeningEngine.$detectedChord) { chord in
            guard listeningEnabled, let chord, listeningEngine.confidence > 0.7 else { return }
            let sections = song.sections
            guard currentSectionIndex < sections.count else { return }
            let section = sections[currentSectionIndex]
            guard let firstMeasure = section.measures.first,
                  let chordId = firstMeasure.chordId,
                  let expected = song.chords.first(where: { $0.id == chordId }) else { return }
            if chord == expected.name {
                currentSectionIndex = min(currentSectionIndex + 1, sections.count - 1)
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
                if granted {
                    listeningEngine.start()
                    await MainActor.run { listeningEnabled = true }
                } else {
                    await MainActor.run { micPermissionDenied = true }
                }
            }
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
