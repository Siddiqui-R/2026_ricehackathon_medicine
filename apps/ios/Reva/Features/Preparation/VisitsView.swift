import SwiftUI

struct VisitsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var adding = false
    @State private var selection = "Upcoming"
    var filtered: [Visit] { store.visits.filter { $0.status == (selection == "Upcoming" ? "upcoming" : "completed") } }
    var body: some View {
        Page {
            Text("Before, during, and after your visit.").font(.subheadline).foregroundStyle(.secondary)
            Picker("Visits", selection: $selection) { Text("Upcoming").tag("Upcoming"); Text("Past").tag("Past") }.pickerStyle(.segmented)
            if filtered.isEmpty { ContentUnavailableView("No \(selection.lowercased()) visits", systemImage: "calendar", description: Text("Add an appointment to prepare your history and questions.")); Button("Add a visit") { adding = true }.buttonStyle(PrimaryButtonStyle()) }
            ForEach(filtered) { visit in
                NavigationLink { VisitDetailView(id: visit.id) } label: {
                    RevaCard {
                        VisitRow(visit: visit)
                        Divider()
                        Text(visit.concern).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        Label(visit.report == nil ? "Ready to prepare" : ReportEngine.isStale(visit, records: store.records) ? "Brief needs an update" : "Brief ready", systemImage: visit.report == nil ? "list.bullet.clipboard" : "doc.text").font(.caption.weight(.medium)).foregroundStyle(RevaTheme.accent)
                    }
                }.buttonStyle(.plain)
            }
        }.navigationTitle("Visits").toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add visit") } }
            .sheet(isPresented: $adding) { NavigationStack { VisitEditorView() } }
    }
}

struct VisitDetailView: View {
    @EnvironmentObject private var store: AppStore
    let id: String
    @State private var editing = false
    @State private var booking = false
    @State private var recording = false
    @State private var showReport = false
    @State private var generating = false
    @State private var sampleID: String?
    var body: some View {
        Group {
            if let visit = store.visit(id) {
                Page {
                    HStack { ModeBadge(text: visit.status == "completed" ? "PAST VISIT" : "UPCOMING VISIT"); Spacer(); Text(visit.type).font(.caption).foregroundStyle(.secondary) }
                    Text(visit.title).font(.title.bold())
                    DetailLine(symbol: "calendar", text: RevaDate.display(visit.date, time: true, zone: visit.timeZone))
                    DetailLine(symbol: "globe.americas", text: visit.timeZone)
                    DetailLine(symbol: "person.crop.circle", text: visit.provider + " · " + visit.clinic)
                    RevaCard {
                        Text("What matters to you").font(.headline)
                        Text(visit.concern)
                        if !visit.goal.isEmpty { Divider(); Text("Your goal").font(.caption.bold()).foregroundStyle(RevaTheme.accent); Text(visit.goal).font(.subheadline) }
                    }
                    if let report = visit.report {
                        if ReportEngine.isStale(visit, records: store.records) { StatusNotice(title: "Your brief needs an update", message: "Records or visit details changed since this brief was made. Regenerate it before sharing.", symbol: "arrow.clockwise") }
                        RevaCard {
                            Label("Your pre-visit brief", systemImage: "doc.text").font(.headline)
                            Text("\(report.selectedRecordIDs.count) source records · \(report.questions.count) questions").font(.subheadline).foregroundStyle(.secondary)
                            Button("Read your brief") { showReport = true }.buttonStyle(PrimaryButtonStyle())
                        }
                    } else {
                        RevaCard {
                            Label("Arrive with a clearer picture", systemImage: "list.bullet.clipboard").font(.headline)
                            Text("We’ll bring together relevant source excerpts and the questions you want to ask.").font(.subheadline).foregroundStyle(.secondary)
                            Button { prepare() } label: { if generating { ProgressView().tint(RevaTheme.buttonText) } else { Text("Create pre-visit brief") } }.buttonStyle(PrimaryButtonStyle()).disabled(generating)
                            Text(store.useConnectedAI ? "Connected Gemini · source review required" : "Local source excerpts · no cloud request").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    SectionHeading(title: "Plan the appointment")
                    RevaCard {
                        Button { booking = true } label: { Label("Request a booking · simulation", systemImage: "phone.arrow.up.right").font(.headline) }.padding(.vertical, 5)
                        if store.providerStatus?.booking.configured == true && store.providerStatus?.liveCallsEnabled == true {
                            NavigationLink { LiveBookingEditorView(visit: visit) } label: { Label("Call clinic with connected agent", systemImage: "phone.arrow.up.right") }
                        }
                        ForEach(store.bookings.filter { $0.visitID == id }) { request in
                            Divider(); NavigationLink { BookingStatusView(id: request.id) } label: { HStack { Text(request.clinic); Spacer(); Text(BookingStatusView.label(request.status)).font(.caption).foregroundStyle(RevaTheme.accent) } }
                        }
                    }
                    SectionHeading(title: "During & after your visit")
                    RevaCard {
                        Button { recording = true } label: { Label("Record this visit", systemImage: "mic").font(.headline) }.padding(.vertical, 5)
                        Divider()
                        Button { store.perform { sampleID = try store.loadSample(visitID: id) } } label: { Label("Explore sample transcript", systemImage: "text.bubble").font(.headline) }.padding(.vertical, 5)
                        Text("The sample is a separate fictional conversation with no matching audio.").font(.caption).foregroundStyle(.secondary)
                        ForEach(store.recordings.filter { $0.visitID == id }) { item in
                            Divider(); NavigationLink { RecordingDetailView(id: item.id) } label: { VStack(alignment: .leading, spacing: 4) { Text(item.title); Text(item.isSample ? "Sample transcript" : "Saved recording · \(RevaDate.duration(item.duration))").font(.caption).foregroundStyle(.secondary) } }
                        }
                    }
                    Button(visit.status == "completed" ? "Move to upcoming" : "Mark visit completed") { var changed = visit; changed.status = visit.status == "completed" ? "upcoming" : "completed"; store.perform { try store.save(changed) } }.frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .sheet(isPresented: $editing) { NavigationStack { VisitEditorView(existing: visit) } }
                .sheet(isPresented: $booking) { NavigationStack { BookingEditorView(visit: visit) } }
                .sheet(isPresented: $recording) { NavigationStack { RecordingSessionView(visit: visit) } }
                .navigationDestination(isPresented: $showReport) { ReportView(visitID: id) }
                .navigationDestination(item: $sampleID) { RecordingDetailView(id: $0) }
            } else { ContentUnavailableView("Visit unavailable", systemImage: "calendar.badge.exclamationmark") }
        }.navigationTitle("Visit").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
    }
    private func prepare() {
        generating = true
        Task { if await store.generatePreferredReport(id) { showReport = true }; generating = false }
    }
}

struct VisitEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var existing: Visit?
    @State private var title = ""
    @State private var type = "Primary care"
    @State private var provider = ""
    @State private var clinic = ""
    @State private var date = Date().addingTimeInterval(86400 * 3)
    @State private var zone = "America/Chicago"
    @State private var concern = ""
    @State private var goal = ""
    @State private var questions = ""
    @State private var pins: Set<String> = []
    var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !concern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && TimeZone(identifier: zone) != nil }
    var body: some View {
        RevaForm {
            Section("Appointment") {
                TextField("Visit title", text: $title)
                Picker("Visit type", selection: $type) { ForEach(["Primary care", "Orthopedics", "Cardiology", "Other"], id: \.self) { Text($0) } }
                TextField("Provider", text: $provider); TextField("Clinic", text: $clinic)
                DatePicker("Date & time", selection: $date).environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
                Picker("Time zone", selection: $zone) { ForEach(["America/Chicago", "America/New_York", "America/Denver", "America/Los_Angeles", "Europe/London", "UTC"], id: \.self) { Text($0) } }
            }
            Section("What would you like to discuss?") { TextField("Your concern or symptoms", text: $concern, axis: .vertical).lineLimit(3...6); TextField("What would make this visit useful?", text: $goal, axis: .vertical).lineLimit(2...5) }
            Section { TextEditor(text: $questions).frame(minHeight: 100) } header: { Text("Questions to ask") } footer: { Text("One question per line. You can also edit the questions in your generated brief.") }
            Section { ForEach(store.records) { record in Toggle(record.title, isOn: Binding(get: { pins.contains(record.id) }, set: { if $0 { pins.insert(record.id) } else { pins.remove(record.id) } })) } } header: { Text("Always include these records") } footer: { Text("Pinned records are included alongside the relevant history selected for your visit.") }
        }.navigationTitle(existing == nil ? "Add visit" : "Edit visit").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid) } }
            .onAppear { guard let existing else { return }; title = existing.title; type = existing.type; provider = existing.provider; clinic = existing.clinic; date = RevaDate.parse(existing.date); zone = existing.timeZone; concern = existing.concern; goal = existing.goal; questions = existing.questions.joined(separator: "\n"); pins = Set(existing.pinnedRecordIDs) }
    }
    private func save() {
        var visit = existing ?? Visit(title: title, type: type, provider: provider, clinic: clinic, date: RevaDate.iso(date), concern: concern, goal: goal)
        visit.title = title.trimmingCharacters(in: .whitespacesAndNewlines); visit.type = type; visit.provider = provider; visit.clinic = clinic; visit.date = RevaDate.iso(date); visit.timeZone = zone; visit.concern = concern; visit.goal = goal; visit.questions = questions.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }; visit.pinnedRecordIDs = pins.sorted()
        if store.perform({ try store.save(visit) }) { dismiss() }
    }
}

struct ReportView: View {
    @EnvironmentObject private var store: AppStore
    let visitID: String
    @State private var edit = false
    @State private var exportDocument: ExportDocument?
    var body: some View {
        Group {
            if let visit = store.visit(visitID), let report = visit.report {
                Page {
                    ModeBadge(text: report.generationModel == nil ? "LOCAL PRE-VISIT BRIEF" : "AI-ASSISTED · REVIEW SOURCES")
                    Text(visit.title).font(.title.bold())
                    Text("Prepared \(RevaDate.display(report.createdAt)) · \(report.selectedRecordIDs.count) source records").font(.caption).foregroundStyle(.secondary)
                    if ReportEngine.isStale(visit, records: store.records) { StatusNotice(title: "Out of date", message: "Your records or visit details changed. Regenerate before sharing.", symbol: "arrow.clockwise") }
                    ForEach(report.sections) { section in
                        RevaCard {
                            Text(section.title).font(.headline)
                            Text(section.body).font(.subheadline).textSelection(.enabled)
                            ForEach(section.sources) { source in
                                NavigationLink { RecordDetailView(id: source.recordID, sourcePage: source.page) } label: { Label("\(store.record(source.recordID)?.title ?? "Deleted source") · \(source.locationLabel)", systemImage: "doc.text.magnifyingglass").font(.caption.weight(.medium)) }.padding(.top, 4)
                            }
                        }
                    }
                    RevaCard {
                        Text("Questions to bring").font(.headline)
                        ForEach(Array(report.questions.enumerated()), id: \.offset) { index, question in HStack(alignment: .top, spacing: 10) { Text("\(index + 1)").font(.caption.bold()).foregroundStyle(RevaTheme.accent).frame(width: 24, height: 24).background(RevaTheme.soft, in: Circle()); Text(question).font(.subheadline) } }
                        if report.questions.isEmpty { Text("Add the questions you want to discuss.").foregroundStyle(.secondary) }
                        Button("Edit questions & notes") { edit = true }.font(.subheadline.weight(.semibold))
                    }
                    if !report.notes.isEmpty { RevaCard { Text("Your notes").font(.headline); Text(report.notes) } }
                    StatusNotice(title: "A conversation aid", message: "This brief brings together selected source excerpts. Any AI overview needs review. It does not diagnose or recommend treatment; check the sources with your clinician.")
                    Button(store.isProviderBusy ? "Preparing…" : "Regenerate from current records") { Task { await store.generatePreferredReport(visitID) } }.buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity).disabled(store.isProviderBusy)
                    Button { exportReport(visit, report) } label: { Label("Share visit brief", systemImage: "square.and.arrow.up") }.buttonStyle(PrimaryButtonStyle()).disabled(ReportEngine.isStale(visit, records: store.records))
                }.sheet(isPresented: $edit) { NavigationStack { ReportEditorView(visit: visit) } }
            } else { ContentUnavailableView("No brief yet", systemImage: "doc.text", description: Text("Generate a brief from the visit screen.")) }
        }.navigationTitle("Visit brief").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $exportDocument) { document in SourcePreview(url: document.url, title: "Visit brief") }
    }
    private func exportReport(_ visit: Visit, _ report: VisitReport) {
        store.perform {
            var sections = report.sections.map { section in PDFSection(title: section.title, body: section.body + (section.sources.isEmpty ? "" : "\n\nSource: " + section.sources.map { "\(store.record($0.recordID)?.title ?? "Missing") · \($0.locationLabel)" }.joined(separator: "; "))) }
            sections.append(PDFSection(title: "Questions to bring", body: report.questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")))
            if !report.notes.isEmpty { sections.append(PDFSection(title: "Your notes", body: report.notes)) }
            let url = try ReportPDFRenderer.render(title: "Reva · " + visit.title, subtitle: (report.generationModel.map { "AI-assisted (" + $0 + ") · review sources · " } ?? "Local source brief · ") + RevaDate.display(visit.date, time: true, zone: visit.timeZone), sections: sections, sources: report.selectedRecordIDs.compactMap { store.record($0) }.map { "\($0.title) · \(RevaDate.display($0.date)) · source version \($0.version)" })
            exportDocument = ExportDocument(url: url)
        }
    }
}
struct ExportDocument: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
struct ReportEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    @State private var questions = ""
    @State private var notes = ""
    var body: some View { RevaForm {
        Section { TextEditor(text: $questions).frame(minHeight: 220) } header: { Text("Questions to ask") } footer: { Text("One question per line. Your edits stay when the brief is regenerated.") }
        Section("Your notes") { TextEditor(text: $notes).frame(minHeight: 160) }
    }.navigationTitle("Make it yours").navigationBarTitleDisplayMode(.inline).onAppear { questions = visit.report?.questions.joined(separator: "\n") ?? ""; notes = visit.report?.notes ?? "" }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { var latest = store.visit(visit.id) ?? visit; latest.questions = questions.components(separatedBy: .newlines).filter { !$0.isEmpty }; latest.notes = notes; if store.perform({ try store.save(latest) }) { dismiss() } } } }
    }
}
