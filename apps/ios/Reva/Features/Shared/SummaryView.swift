// Overview matches the web's preparation, standalone recording, recent records and saved sessions.
import SwiftUI

struct SummaryView: View {
    @EnvironmentObject private var store: AppStore
    let showAllRecords: () -> Void
    @State private var addRecord = false
    @State private var logSymptoms = false
    @State private var recording = false
    var body: some View {
        Page {
            Text("A little preparation. A clearer conversation.").font(.subheadline).foregroundStyle(
                .secondary)
            if store.account != nil { Text(store.syncStatus).font(.caption).foregroundStyle(.secondary) }
            if let notice = store.notice {
                HStack(alignment: .top) {
                    Text(notice).font(.footnote)
                    Spacer()
                    Button {
                        store.notice = nil
                    } label: {
                        Image(systemName: "xmark")
                    }.accessibilityLabel("Dismiss notice")
                }.padding(14).background(RevaTheme.soft, in: RoundedRectangle(cornerRadius: 10))
            }
            RevaCard {
                Label("Before your visit", systemImage: "list.bullet.clipboard").font(.headline)
                Text("Bring your relevant history and the questions that matter to you.").font(.subheadline)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    NativeVisitPreparation()
                } label: {
                    Label("Prepare for this visit", systemImage: "arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            RevaCard {
                Label("Keep the conversation", systemImage: "waveform").font(.headline)
                Text(
                    "Record with permission. Your transcript and summary are prepared automatically after saving."
                ).font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    recording = true
                } label: {
                    Label("Record session", systemImage: "mic")
                }.buttonStyle(PrimaryButtonStyle())
            }
            HStack(spacing: 12) {
                Button {
                    addRecord = true
                } label: {
                    Label("Add record", systemImage: "plus.rectangle.on.folder").frame(maxWidth: .infinity)
                        .padding(14).outlined()
                }
                Button {
                    logSymptoms = true
                } label: {
                    Label("Log a symptom", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                        .padding(14).outlined()
                }
            }.font(.subheadline.weight(.semibold)).buttonStyle(.plain)
            SectionHeading(title: "Recent records")
            RevaCard {
                if store.records.isEmpty {
                    Text("Add a document to start building your history.").foregroundStyle(.secondary)
                }
                ForEach(Array(store.records.prefix(3).enumerated()), id: \.element.id) { index, record in
                    if index > 0 { Divider() }
                    NavigationLink {
                        RecordDetailView(id: record.id)
                    } label: {
                        RecordRow(record: record)
                    }.buttonStyle(.plain)
                }
                Button(action: showAllRecords) { Label("View all records", systemImage: "arrow.right") }.font(
                    .subheadline.weight(.semibold))
            }
            SectionHeading(title: "Session recordings")
            RevaCard {
                if store.recordings.isEmpty {
                    Text("Your saved sessions will appear here.").font(.subheadline).foregroundStyle(
                        .secondary)
                }
                ForEach(store.recordings.sorted { $0.createdAt > $1.createdAt }) { item in
                    NavigationLink {
                        RecordingDetailView(id: item.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform").foregroundStyle(RevaTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(
                                    RevaDate.display(item.createdAt) + " · "
                                        + RevaDate.duration(item.duration)
                                ).font(.caption).foregroundStyle(.secondary)
                                if let progress = store.recordingProcessingMessage(item) {
                                    Text(progress).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }.buttonStyle(.plain)
                }
            }
            NavigationLink {
                VisitsView()
            } label: {
                Label("Visit history", systemImage: "clock.arrow.circlepath")
            }.font(.subheadline)
        }.navigationTitle("Overview")
            .sheet(isPresented: $addRecord) { NavigationStack { AddRecordView() } }
            .sheet(isPresented: $logSymptoms) { NavigationStack { SymptomEntryEditorView() } }
            .fullScreenCover(isPresented: $recording) { NavigationStack { RecordingSessionView() } }
    }
}
