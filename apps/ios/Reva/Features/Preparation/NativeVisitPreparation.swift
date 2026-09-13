// Prepare and export a concise native visit brief without creating a saved appointment.
import SwiftUI

struct NativeVisitPreparation: View {
    @EnvironmentObject private var store: AppStore
    @State private var type = ""
    @State private var concern = ""
    @State private var questions = ["", "", ""]
    @State private var generating = false
    @State private var brief: NativeVisitBrief?
    @State private var error: String?
    var body: some View {
        Page {
            Text("A clearer starting point.").font(.title.bold())
            Text("Bring together your relevant history and the questions on your mind.").foregroundStyle(
                .secondary)
            RevaCard {
                Text("Visit type").font(.subheadline.weight(.semibold))
                TextField("For example, primary care or orthopedics", text: $type).textFieldStyle(
                    .roundedBorder)
                Text("What would you like to discuss?").font(.subheadline.weight(.semibold))
                TextField("Your concern · optional", text: $concern, axis: .vertical).lineLimit(3...6)
                Text("Questions to ask · optional").font(.subheadline.weight(.semibold))
                ForEach(questions.indices, id: \.self) { index in
                    TextField("Question \(index + 1)", text: $questions[index]).textFieldStyle(.roundedBorder)
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(RevaTheme.accentText) }
            Button {
                Task { await generate() }
            } label: {
                if generating {
                    ProgressView().tint(.white)
                } else {
                    Label("Create pre-visit brief", systemImage: "sparkles")
                }
            }.buttonStyle(PrimaryButtonStyle()).disabled(
                generating || type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text(
                "AI uses your records and current medical profile. Review the brief and original sources before your visit."
            )
            .font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Visit preparation").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $brief) { NativeBriefView(brief: $0) }
    }
    private func generate() async {
        guard let snapshot = store.snapshot else { return }
        generating = true
        error = nil
        defer { generating = false }
        do {
            let cleaned = questions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
                !$0.isEmpty
            }
            let (visit, sources) = try NativeVisitBrief.inputs(
                snapshot: snapshot, type: type, concern: concern, questions: cleaned)
            let context = store.providerContext
            if store.providerStatus == nil { await store.checkProviders() }
            guard store.providerStatus?.gemini.configured == true else {
                throw RevaError.invalid(
                    "Connect AI from your account’s settings to generate a brief. Your records remain available offline."
                )
            }
            let result = try await store.providerClient().prepare(visit, records: sources)
            guard context == store.providerContext, store.snapshot?.profile == snapshot.profile,
                store.snapshot?.records == snapshot.records
            else {
                throw RevaError.invalid(
                    "Your records changed during preparation. Generate the brief again using the latest sources."
                )
            }
            brief = try NativeVisitBrief.checked(
                snapshot: snapshot, visit: visit, sources: sources, result: result)
        } catch { self.error = error.localizedDescription }
    }
}
private struct NativeBriefView: View {
    @EnvironmentObject private var store: AppStore
    let brief: NativeVisitBrief
    @State private var export: URL?
    private var stale: Bool {
        store.snapshot?.profile != brief.snapshot.profile || store.snapshot?.records != brief.snapshot.records
    }
    var body: some View {
        Page {
            HStack {
                Text("reva.").font(.title.bold()).foregroundStyle(RevaTheme.accent)
                Spacer()
                Text("Pre-visit brief").font(.subheadline)
            }
            Text(brief.patient.name).font(.headline)
            Text(brief.visitType + " · " + RevaDate.display(brief.createdAt)).font(.subheadline)
                .foregroundStyle(.secondary)
            if stale {
                StatusNotice(
                    title: "Your sources changed",
                    message: "Return to preparation and generate a new brief before sharing.")
            }
            RevaCard {
                Text("Before your visit").font(.headline)
                Text(brief.overview).textSelection(.enabled)
            }
            if !brief.questions.isEmpty {
                RevaCard {
                    Text("Questions to ask").font(.headline)
                    ForEach(Array(brief.questions.enumerated()), id: \.offset) { index, text in
                        Text("\(index + 1). \(text)")
                    }
                }
            }
            RevaCard {
                Text("Sources").font(.headline)
                ForEach(brief.sources) { source in
                    if store.record(source.id) != nil {
                        NavigationLink {
                            RecordDetailView(id: source.id)
                        } label: {
                            Label(source.title, systemImage: "doc.text")
                        }.font(.subheadline)
                    } else {
                        Text(source.title).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if let export, !stale {
                ShareLink(item: export) { Label("Share or print brief", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryButtonStyle())
            } else if !stale {
                Button("Prepare PDF") { makePDF() }.buttonStyle(PrimaryButtonStyle())
            }
            Text(
                "Review AI output against your original records. This brief is preparation for a conversation, not a diagnosis."
            ).font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Your brief").navigationBarTitleDisplayMode(.inline).onAppear { makePDF() }
    }
    private func makePDF() {
        guard !stale else { return }
        store.perform {
            var sections = [PDFSection(title: "Before your visit", body: brief.overview)]
            if !brief.questions.isEmpty {
                sections.append(
                    PDFSection(
                        title: "Questions to ask",
                        body: brief.questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(
                            separator: "\n")))
            }
            export = try ReportPDFRenderer.render(
                title: "Pre-visit brief", subtitle: brief.patient.name + " · " + brief.visitType,
                sections: sections,
                sources: brief.sources.map { $0.title + " · " + RevaDate.display($0.date) })
        }
    }
}
