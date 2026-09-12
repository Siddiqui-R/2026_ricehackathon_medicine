// Purpose: Coordinate preparation, booking, and memory actions for one visit.
// Inputs: A visit ID plus AppStore visits, records, bookings, and recordings.
// Outputs: Visit details and routes to briefs, booking, audio, and editors.
// Side effects: Can generate a brief, load a sample transcript, or update visit status through AppStore.

import SwiftUI

// MARK: - VisitDetailView
/// Coordinate preparation, booking, and memory actions for one visit.
struct VisitDetailView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    let id: String
    @State private var editing = false
    @State private var booking = false
    @State private var recording = false
    @State private var showReport = false
    @State private var generating = false
    @State private var sampleID: String?
    // MARK: - Rendering and navigation
    var body: some View {
        Group {
            if let visit = store.visit(id) {
                Page {
                    HStack {
                        ModeBadge(text: visit.status == "completed" ? "PAST VISIT" : "UPCOMING VISIT")
                        Spacer()
                        Text(visit.type).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(visit.title).font(.title.bold())
                    DetailLine(
                        symbol: "calendar",
                        text: RevaDate.display(visit.date, time: true, zone: visit.timeZone))
                    DetailLine(symbol: "globe.americas", text: visit.timeZone)
                    DetailLine(symbol: "person.crop.circle", text: visit.provider + " · " + visit.clinic)
                    RevaCard {
                        Text("What matters to you").font(.headline)
                        Text(visit.concern)
                        if !visit.goal.isEmpty {
                            Divider()
                            Text("Your goal").font(.caption.bold()).foregroundStyle(RevaTheme.accent)
                            Text(visit.goal).font(.subheadline)
                        }
                    }
                    if let report = visit.report {
                        if ReportEngine.isStale(visit, records: store.records) {
                            StatusNotice(
                                title: "Your brief needs an update",
                                message:
                                    "Records or visit details changed since this brief was made. Regenerate it before sharing.",
                                symbol: "arrow.clockwise")
                        }
                        RevaCard {
                            Label("Your pre-visit brief", systemImage: "doc.text").font(.headline)
                            Text(
                                "\(report.selectedRecordIDs.count) source records · \(report.questions.count) questions"
                            ).font(.subheadline).foregroundStyle(.secondary)
                            Button("Read your brief") { showReport = true }.buttonStyle(PrimaryButtonStyle())
                        }
                    } else {
                        RevaCard {
                            Label("Arrive with a clearer picture", systemImage: "list.bullet.clipboard").font(
                                .headline)
                            Text(
                                "We’ll bring together relevant source excerpts and the questions you want to ask."
                            ).font(.subheadline).foregroundStyle(.secondary)
                            Button {
                                prepare()
                            } label: {
                                if generating {
                                    ProgressView().tint(RevaTheme.buttonText)
                                } else {
                                    Text("Create pre-visit brief")
                                }
                            }.buttonStyle(PrimaryButtonStyle()).disabled(generating)
                            Text(
                                store.useConnectedAI
                                    ? "Connected Gemini · source review required"
                                    : "Local source excerpts · no cloud request"
                            ).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    SectionHeading(title: "Plan the appointment")
                    RevaCard {
                        Button {
                            booking = true
                        } label: {
                            Label("Request a booking · simulation", systemImage: "phone.arrow.up.right").font(
                                .headline)
                        }.padding(.vertical, 5)
                        if store.providerStatus?.booking.configured == true
                            && store.providerStatus?.liveCallsEnabled == true
                        {
                            NavigationLink {
                                LiveBookingEditorView(visit: visit)
                            } label: {
                                Label("Call clinic with connected agent", systemImage: "phone.arrow.up.right")
                            }
                        }
                        ForEach(store.bookings.filter { $0.visitID == id }) { request in
                            Divider()
                            NavigationLink {
                                BookingStatusView(id: request.id)
                            } label: {
                                HStack {
                                    Text(request.clinic)
                                    Spacer()
                                    Text(BookingStatusView.label(request.status)).font(.caption)
                                        .foregroundStyle(RevaTheme.accent)
                                }
                            }
                        }
                    }
                    SectionHeading(title: "During & after your visit")
                    RevaCard {
                        Button {
                            recording = true
                        } label: {
                            Label("Record this visit", systemImage: "mic").font(.headline)
                        }.padding(.vertical, 5)
                        Divider()
                        Button {
                            store.perform { sampleID = try store.loadSample(visitID: id) }
                        } label: {
                            Label("Explore sample transcript", systemImage: "text.bubble").font(.headline)
                        }.padding(.vertical, 5)
                        Text("The sample is a separate fictional conversation with no matching audio.").font(
                            .caption
                        ).foregroundStyle(.secondary)
                        ForEach(store.recordings.filter { $0.visitID == id }) { item in
                            Divider()
                            NavigationLink {
                                RecordingDetailView(id: item.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                    Text(
                                        item.isSample
                                            ? "Sample transcript"
                                            : "Saved recording · \(RevaDate.duration(item.duration))"
                                    ).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button(visit.status == "completed" ? "Move to upcoming" : "Mark visit completed") {
                        var changed = visit
                        changed.status = visit.status == "completed" ? "upcoming" : "completed"
                        store.perform { try store.save(changed) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .sheet(isPresented: $editing) { NavigationStack { VisitEditorView(existing: visit) } }
                .sheet(isPresented: $booking) { NavigationStack { BookingEditorView(visit: visit) } }
                .sheet(isPresented: $recording) { NavigationStack { RecordingSessionView(visit: visit) } }
                .navigationDestination(isPresented: $showReport) { ReportView(visitID: id) }
                .navigationDestination(item: $sampleID) { RecordingDetailView(id: $0) }
            } else {
                ContentUnavailableView("Visit unavailable", systemImage: "calendar.badge.exclamationmark")
            }
        }.navigationTitle("Visit").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
    }
    // MARK: - Brief generation
    /// Let AppStore choose local or connected preparation and navigate only after success.
    private func prepare() {
        generating = true
        Task {
            if await store.generatePreferredReport(id) { showReport = true }
            generating = false
        }
    }
}
