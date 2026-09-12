// Purpose: Capture visit audio after recording consent and save the completed recording.
// Inputs: The Visit, user consent, AudioRecorder, and AppStore.
// Outputs: Recording controls and a saved VisitRecording linked to its audio file.
// Side effects: Captures audio, retries metadata saves, shares originals, and can discard unfinished capture.

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
    @State private var restart = false
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
                        saveDraft.recording != nil
                            ? "Audio finished — waiting to save"
                            : recorder.hasFinalizationFailure
                                ? "Recording could not be finalized"
                                : recorder.isRecording
                                    ? recorder.isPaused ? "Paused" : "Recording on this device"
                                    : "Ready when you are"
                    ).font(.subheadline).foregroundStyle(.secondary)
                    if saveDraft.recording != nil {
                        Button("Retry saving recording") { finish() }.buttonStyle(PrimaryButtonStyle())
                        if let audioURL = saveDraft.audioURL {
                            ShareLink(item: audioURL) {
                                Label("Save or share audio", systemImage: "square.and.arrow.up")
                            }.buttonStyle(.bordered).controlSize(.large)
                        }
                        Text(
                            "Your completed audio is kept on this device. Retry saving or share a copy before closing."
                        )
                        .font(.subheadline).foregroundStyle(.secondary)
                    } else if recorder.hasFinalizationFailure {
                        Button("Discard & start again", role: .destructive) { restart = true }
                            .buttonStyle(.bordered).controlSize(.large)
                    } else if recorder.isRecording {
                        Button(recorder.isPaused ? "Resume recording" : "Pause recording") {
                            if recorder.isPaused { recorder.resume() } else { recorder.pause() }
                        }.buttonStyle(.bordered).controlSize(.large)
                        Button("Finish & save audio") { finish() }.buttonStyle(PrimaryButtonStyle())
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
                        if recorder.isRecording || recorder.hasFinalizationFailure || starting
                            || saveDraft.recording != nil
                        {
                            discard = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .interactiveDismissDisabled(
                recorder.isRecording || recorder.hasFinalizationFailure || starting
                    || saveDraft.recording != nil
            )
            .confirmationDialog(
                saveDraft.recording != nil
                    ? "Leave without saving this recording?" : "Discard this unfinished recording?",
                isPresented: $discard, titleVisibility: .visible
            ) {
                if saveDraft.recording != nil {
                    Button("Leave without saving", role: .destructive) { dismiss() }
                } else {
                    Button("Discard recording", role: .destructive) {
                        recorder.cancel()
                        dismiss()
                    }
                }
            } message: {
                if saveDraft.recording != nil {
                    Text(
                        "Closing ends this save attempt. Use Save or share audio to keep an accessible copy before leaving."
                    )
                }
            }
            .confirmationDialog(
                "Discard this failed recording and start again?", isPresented: $restart,
                titleVisibility: .visible
            ) {
                Button("Discard recording", role: .destructive) { recorder.cancel() }
            } message: {
                Text("This recording cannot resume. Discarding returns you to the start controls.")
            }
            .navigationDestination(item: $savedID) { RecordingDetailView(id: $0) }
            .onDisappear { if recorder.isRecording { recorder.pause() } }
    }
    // MARK: - Finalize capture
    /// Finalize once; a failed metadata write keeps the original and stable recording available for retry.
    private func finish() {
        store.perform {
            savedID = try saveDraft.save(
                visit: visit,
                finishAudio: {
                    let url = try recorder.finish()
                    return (url, recorder.elapsed)
                }, persist: { try store.save($0) })
        }
    }
}
