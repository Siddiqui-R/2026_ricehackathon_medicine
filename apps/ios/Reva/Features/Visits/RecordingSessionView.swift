// Purpose: Capture visit audio after recording consent and save the completed recording.
// Inputs: The Visit, user consent, AudioRecorder, and AppStore.
// Outputs: Recording controls and a saved VisitRecording linked to its audio file.
// Side effects: Requests microphone capture, writes audio, pauses on exit, and can discard unfinished capture.

import SwiftUI

// MARK: - RecordingSessionView
/// Capture visit audio after recording consent and save the completed recording.
struct RecordingSessionView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    let visit: Visit
    @State private var agreed = false
    @State private var starting = false
    @State private var savedID: String?
    @State private var saveDraft = RecordingSaveDraft()
    @State private var discard = false
    // MARK: - Rendering and navigation
    var body: some View {
        Page {
            Text("Keep the conversation.").font(.title2.bold())
            Text(visit.title).foregroundStyle(.secondary)
            StatusNotice(
                title: "Before you record",
                message:
                    "Ask everyone present for permission to record. Keep Reva on screen; recording pauses when the app leaves the foreground.",
                symbol: "person.2")
            RevaCard {
                VStack(spacing: 24) {
                    Image(systemName: recorder.isRecording && !recorder.isPaused ? "waveform" : "mic.circle")
                        .font(.system(size: 56)).foregroundStyle(RevaTheme.accent)
                    Text(RevaDate.duration(recorder.elapsed)).font(
                        .system(size: 48, weight: .medium, design: .rounded)
                    ).monospacedDigit().accessibilityLabel("Elapsed \(RevaDate.duration(recorder.elapsed))")
                    Text(
                        recorder.finishFailed
                            ? "Recording could not be finalized"
                            : saveDraft.recording != nil
                                ? "Audio captured · waiting to save"
                                : recorder.isRecording
                                    ? recorder.isPaused ? "Paused" : "Recording on this device"
                                    : "Ready when you are"
                    ).font(.subheadline).foregroundStyle(.secondary)
                    if recorder.finishFailed {
                        Button("Discard & start again", role: .destructive) { recorder.cancel() }
                            .buttonStyle(.bordered).controlSize(.large)
                    } else if recorder.isRecording {
                        Button(recorder.isPaused ? "Resume recording" : "Pause recording") {
                            if recorder.isPaused { recorder.resume() } else { recorder.pause() }
                        }.buttonStyle(.bordered).controlSize(.large)
                        Button("Finish & save audio") { finish() }.buttonStyle(PrimaryButtonStyle())
                    } else if saveDraft.recording != nil {
                        Text("Your captured audio is kept here. Retry saving to add it to this visit.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Retry saving recording") { saveFinishedRecording() }
                            .buttonStyle(PrimaryButtonStyle())
                    } else if savedID == nil {
                        Toggle("Everyone agreed to be recorded", isOn: $agreed)
                        Button {
                            Task {
                                starting = true
                                defer { starting = false }
                                do {
                                    try await recorder.start(directory: store.repository.attachmentDirectory)
                                } catch { store.errorMessage = error.localizedDescription }
                            }
                        } label: {
                            if starting {
                                ProgressView()
                            } else {
                                Label("Start recording", systemImage: "record.circle")
                            }
                        }.buttonStyle(PrimaryButtonStyle()).disabled(!agreed || starting)
                    }
                }.frame(maxWidth: .infinity)
            }
            if let message = recorder.errorMessage {
                StatusNotice(title: "Recording status", message: message, symbol: "mic.badge.xmark")
            }
            StatusNotice(
                title: "Audio now, transcription later",
                message:
                    "Captured audio is saved for playback. Live transcription is not configured. The fictional sample transcript is a separate action on the visit screen."
            )
        }.navigationTitle("Record visit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if recorder.isRecording || starting || saveDraft.recording != nil {
                            discard = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .interactiveDismissDisabled(recorder.isRecording || starting || saveDraft.recording != nil)
            .confirmationDialog(
                saveDraft.recording == nil
                    ? "Discard this unfinished recording?"
                    : "Leave without saving this recording? Retry saving to keep the captured audio in Visits.",
                isPresented: $discard, titleVisibility: .visible
            ) {
                Button(
                    saveDraft.recording == nil ? "Discard recording" : "Leave without saving",
                    role: .destructive
                ) {
                    recorder.cancel()
                    dismiss()
                }
            }
            .navigationDestination(item: $savedID) { RecordingDetailView(id: $0) }
            .onDisappear { if recorder.isRecording { recorder.pause() } }
    }
    // MARK: - Finalize capture
    /// Finish the audio file before adding its recording metadata to the visit history.
    private func finish() {
        store.perform {
            let url = try recorder.finish()
            let recording = VisitRecording(
                visitID: visit.id, title: visit.title + " · audio", duration: recorder.elapsed,
                audioFilename: url.lastPathComponent)
            saveDraft.retain(recording)
            savedID = try saveDraft.save(to: store)
        }
    }

    // MARK: - Retry metadata persistence
    /// Reuse the finalized recording identity and audio file without starting or finishing capture again.
    private func saveFinishedRecording() {
        store.perform { savedID = try saveDraft.save(to: store) }
    }
}
