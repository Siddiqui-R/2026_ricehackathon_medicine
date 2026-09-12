// Purpose: Review visit audio, transcript, separate notes, and saved record memory.
// Inputs: A recording ID, AppStore, and AudioPlayback.
// Outputs: Playback and transcript details with correction, notes, sharing, and memory actions.
// Side effects: Controls playback, requests transcription, saves memory, or removes the recording from state.

import SwiftUI

// MARK: - RecordingDetailView
/// Review visit audio, transcript, separate notes, and saved record memory.
struct RecordingDetailView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = AudioPlayback()
    let id: String
    @State private var editing = false
    @State private var editingTranscript = false
    @State private var deleting = false
    @State private var memorySaved = false
    // MARK: - Rendering and navigation
    var body: some View {
        if let recording = store.recording(id) {
            Page {
                ModeBadge(text: recording.isSample ? "FICTIONAL SAMPLE · NO AUDIO" : "SAVED RECORDING")
                Text(recording.title).font(.title2.bold())
                Text(RevaDate.display(recording.createdAt) + " · " + RevaDate.duration(recording.duration))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let filename = recording.audioFilename, let url = store.sourceURL(filename) {
                    RevaCard {
                        HStack {
                            Button {
                                if playback.isPlaying {
                                    playback.pause()
                                } else {
                                    store.perform { try playback.play(url: url) }
                                }
                            } label: {
                                Image(
                                    systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill"
                                ).font(.system(size: 46))
                            }.accessibilityLabel(playback.isPlaying ? "Pause audio" : "Play audio")
                            VStack(alignment: .leading) {
                                Text("Your recorded audio").font(.headline)
                                Text(
                                    RevaDate.duration(playback.currentTime) + " / "
                                        + RevaDate.duration(
                                            playback.duration > 0 ? playback.duration : recording.duration)
                                ).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        Slider(
                            value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }),
                            in: 0...max(1, playback.duration)
                        ).disabled(playback.duration == 0).accessibilityLabel("Playback position")
                        ShareLink(item: url) { Label("Share audio", systemImage: "square.and.arrow.up") }
                            .font(.subheadline)
                    }
                }
                if !recording.isSample {
                    if let model = recording.transcriptionModel {
                        StatusNotice(
                            title: "Transcript · " + model,
                            message:
                                "Review the words against your audio. Speaker labels are generic; this service does not identify people."
                        )
                    } else {
                        StatusNotice(
                            title: "Your saved audio",
                            message:
                                "Add notes, or connect transcription in Profile & settings to generate a reviewable transcript."
                        )
                    }
                    if store.providerStatus?.transcription.configured == true {
                        Button(store.isProviderBusy ? "Transcribing…" : "Transcribe saved audio") {
                            Task { await store.transcribeRecording(id) }
                        }.buttonStyle(.bordered).disabled(
                            store.isProviderBusy || recording.audioFilename == nil
                                || !recording.segments.isEmpty)
                    }
                }
                if !recording.summary.isEmpty {
                    RevaCard {
                        Text("Separate visit notes").font(.headline)
                        Text(recording.summary).textSelection(.enabled)
                        Text(
                            "These editable notes are separate from the transcript. Correcting transcript text does not rewrite them."
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !recording.segments.isEmpty {
                    RevaCard {
                        Text(
                            recording.isSample
                                ? "Local excerpt of sample transcript" : "Local excerpt of transcript"
                        ).font(.headline)
                        Text(
                            ReportEngine.localExcerpt(
                                recording.segments.map {
                                    "[\(RevaDate.duration($0.start))] \($0.speaker): \($0.text)"
                                }.joined(separator: "\n\n"))
                        ).textSelection(.enabled)
                        Text(
                            "From the current transcript text. Corrections update this excerpt and any memory already saved to Records."
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                    SectionHeading(title: "Transcript")
                    RevaCard {
                        ForEach(recording.segments) { segment in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(segment.speaker).font(.caption.bold()).foregroundStyle(
                                        RevaTheme.accent)
                                    Spacer()
                                    Text(
                                        RevaDate.duration(segment.start) + "–"
                                            + RevaDate.duration(segment.end)
                                    ).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Text(segment.text).font(.subheadline).textSelection(.enabled)
                            }.padding(.vertical, 8)
                        }
                    }
                    Button("Edit transcript text") { editingTranscript = true }.buttonStyle(.bordered)
                        .controlSize(.large).frame(maxWidth: .infinity)
                }
                Button("Edit visit notes") { editing = true }.buttonStyle(.bordered).controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button(
                    memorySaved
                        || store.records.contains(where: {
                            $0.sourceRecordingID == id || $0.id == "memory-" + id
                        }) ? "Update memory in Records" : "Save visit memory to Records"
                ) { if store.perform({ try store.saveMemory(recordingID: id) }) { memorySaved = true } }
                .buttonStyle(PrimaryButtonStyle()).disabled(
                    recording.segments.isEmpty && recording.summary.isEmpty)
                Button("Delete recording", role: .destructive) { deleting = true }.frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }.navigationTitle("Visit memory").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $editing) {
                    NavigationStack { RecordingNotesEditor(recording: recording) }
                }
                .sheet(isPresented: $editingTranscript) {
                    NavigationStack { TranscriptTextEditor(recording: recording) }
                }
                .confirmationDialog(
                    "Delete this recording from your local history? Saved record memories remain in Records.",
                    isPresented: $deleting, titleVisibility: .visible
                ) {
                    Button("Delete recording", role: .destructive) {
                        playback.stop()
                        if store.perform({ try store.mutate { $0.recordings.removeAll { $0.id == id } } }) {
                            dismiss()
                        }
                    }
                }
                .onDisappear { playback.stop() }
        } else {
            ContentUnavailableView("Recording unavailable", systemImage: "waveform")
        }
    }
}
