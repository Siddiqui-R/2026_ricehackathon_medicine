import SwiftUI

struct RecordingSessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    let visit: Visit
    @State private var agreed = false
    @State private var starting = false
    @State private var savedID: String?
    @State private var discard = false
    var body: some View {
        Page {
            Text("Keep the conversation.").font(.title2.bold())
            Text(visit.title).foregroundStyle(.secondary)
            StatusNotice(title: "Before you record", message: "Ask everyone present for permission to record. Keep Reva on screen; recording pauses when the app leaves the foreground.", symbol: "person.2")
            RevaCard {
                VStack(spacing: 24) {
                    Image(systemName: recorder.isRecording && !recorder.isPaused ? "waveform" : "mic.circle").font(.system(size: 56)).foregroundStyle(RevaTheme.accent)
                    Text(RevaDate.duration(recorder.elapsed)).font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit().accessibilityLabel("Elapsed \(RevaDate.duration(recorder.elapsed))")
                    Text(recorder.isRecording ? recorder.isPaused ? "Paused" : "Recording on this device" : "Ready when you are").font(.subheadline).foregroundStyle(.secondary)
                    if recorder.isRecording {
                        Button(recorder.isPaused ? "Resume recording" : "Pause recording") { if recorder.isPaused { recorder.resume() } else { recorder.pause() } }.buttonStyle(.bordered).controlSize(.large)
                        Button("Finish & save audio") { finish() }.buttonStyle(PrimaryButtonStyle())
                    } else if savedID == nil {
                        Toggle("Everyone agreed to be recorded", isOn: $agreed)
                        Button { Task { starting = true; defer { starting = false }; do { try await recorder.start(directory: store.repository.attachmentDirectory) } catch { store.errorMessage = error.localizedDescription } } } label: { if starting { ProgressView() } else { Label("Start recording", systemImage: "record.circle") } }.buttonStyle(PrimaryButtonStyle()).disabled(!agreed || starting)
                    }
                }.frame(maxWidth: .infinity)
            }
            if let message = recorder.errorMessage { StatusNotice(title: "Recording status", message: message, symbol: "mic.badge.xmark") }
            StatusNotice(title: "Audio now, transcription later", message: "Captured audio is saved for playback. Live transcription is not configured. The fictional sample transcript is a separate action on the visit screen.")
        }.navigationTitle("Record visit").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { if recorder.isRecording || starting { discard = true } else { dismiss() } } } }
            .interactiveDismissDisabled(recorder.isRecording || starting)
            .confirmationDialog("Discard this unfinished recording?", isPresented: $discard, titleVisibility: .visible) { Button("Discard recording", role: .destructive) { recorder.cancel(); dismiss() } }
            .navigationDestination(item: $savedID) { RecordingDetailView(id: $0) }
            .onDisappear { if recorder.isRecording { recorder.pause() } }
    }
    private func finish() {
        store.perform {
            let url = try recorder.finish()
            let recording = VisitRecording(visitID: visit.id, title: visit.title + " · audio", duration: recorder.elapsed, audioFilename: url.lastPathComponent)
            try store.save(recording); savedID = recording.id
        }
    }
}
struct RecordingDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback = AudioPlayback()
    let id: String
    @State private var editing = false
    @State private var deleting = false
    @State private var memorySaved = false
    var body: some View {
        if let recording = store.recording(id) {
            Page {
                ModeBadge(text: recording.isSample ? "FICTIONAL SAMPLE · NO AUDIO" : "SAVED RECORDING")
                Text(recording.title).font(.title2.bold())
                Text(RevaDate.display(recording.createdAt) + " · " + RevaDate.duration(recording.duration)).font(.subheadline).foregroundStyle(.secondary)
                if let filename = recording.audioFilename, let url = store.sourceURL(filename) {
                    RevaCard {
                        HStack { Button { if playback.isPlaying { playback.pause() } else { store.perform { try playback.play(url: url) } } } label: { Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 46)) }.accessibilityLabel(playback.isPlaying ? "Pause audio" : "Play audio"); VStack(alignment: .leading) { Text("Your recorded audio").font(.headline); Text(RevaDate.duration(playback.currentTime) + " / " + RevaDate.duration(playback.duration > 0 ? playback.duration : recording.duration)).font(.caption).monospacedDigit().foregroundStyle(.secondary) } }
                        Slider(value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }), in: 0...max(1, playback.duration)).disabled(playback.duration == 0).accessibilityLabel("Playback position")
                        ShareLink(item: url) { Label("Share audio", systemImage: "square.and.arrow.up") }.font(.subheadline)
                    }
                }
                if !recording.isSample { StatusNotice(title: "Transcription not connected", message: "This is your actual saved audio. Add your own notes below; a generated transcript will require a configured service.") }
                if !recording.summary.isEmpty { RevaCard { Text(recording.isSample ? "Sample visit memory" : "Your visit notes").font(.headline); Text(recording.summary).textSelection(.enabled) } }
                if !recording.segments.isEmpty {
                    SectionHeading(title: "Transcript")
                    RevaCard {
                        ForEach(recording.segments) { segment in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(segment.speaker).font(.caption.bold()).foregroundStyle(RevaTheme.accent); Spacer(); Text(RevaDate.duration(segment.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                                Text(segment.text).font(.subheadline).textSelection(.enabled)
                            }.padding(.vertical, 8)
                        }
                    }
                }
                Button("Edit visit notes") { editing = true }.buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                Button(memorySaved ? "Memory saved to Records" : "Save visit memory to Records") { if store.perform({ try store.saveMemory(recordingID: id) }) { memorySaved = true } }.buttonStyle(PrimaryButtonStyle()).disabled(recording.segments.isEmpty && recording.summary.isEmpty)
                Button("Delete recording", role: .destructive) { deleting = true }.frame(maxWidth: .infinity).padding(.top, 8)
            }.navigationTitle("Visit memory").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $editing) { NavigationStack { RecordingNotesEditor(recording: recording) } }
                .confirmationDialog("Delete this recording from your local history? Saved record memories remain in Records.", isPresented: $deleting, titleVisibility: .visible) { Button("Delete recording", role: .destructive) { playback.stop(); if store.perform({ try store.mutate { $0.recordings.removeAll { $0.id == id } } }) { dismiss() } } }
                .onDisappear { playback.stop() }
        } else { ContentUnavailableView("Recording unavailable", systemImage: "waveform") }
    }
}
struct RecordingNotesEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var recording: VisitRecording
    var body: some View { Form { Section("Your visit notes") { TextEditor(text: $recording.summary).frame(minHeight: 300) }; Text("These are your editable notes. They do not change the original transcript or audio.").font(.footnote).foregroundStyle(.secondary) }.navigationTitle("Visit notes").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.perform({ try store.save(recording) }) { dismiss() } } } } }
}
