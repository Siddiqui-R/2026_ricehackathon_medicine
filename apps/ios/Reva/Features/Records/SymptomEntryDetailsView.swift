// Purpose: Display the user's saved symptom observations and exact source text.
// Inputs: A structured SymptomEntry.
// Outputs: Readable occurrence details, optional observations, and expandable record text.
// Side effects: None; the view only renders the supplied entry.

import SwiftUI

// MARK: - SymptomEntryDetailsView
/// Display the user's saved symptom observations and exact source text.
struct SymptomEntryDetailsView: View {
    // MARK: - Inputs and view state

    let entry: SymptomEntry

    // MARK: - Rendering and navigation
    var body: some View {
        RevaCard {
            Label("Your observation", systemImage: "square.and.pencil").font(.headline).foregroundStyle(
                RevaTheme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text("When it happened").font(.subheadline.bold())
                Text(RevaDate.display(entry.observedAt, time: true, zone: entry.timeZone))
                Text(entry.timeZone).font(.caption).foregroundStyle(.secondary)
            }
            if let severity = entry.severity { field("Severity", severity.capitalized) }
            if !entry.duration.isEmpty { field("Duration", entry.duration) }
            if !entry.details.isEmpty { field("Details", entry.details) }
            if !entry.triggers.isEmpty { field("Possible triggers", entry.triggers) }
            if !entry.whatHelped.isEmpty { field("What helped", entry.whatHelped) }
            Text("Self-reported by you.").font(.caption).foregroundStyle(.secondary)
        }
        RevaCard {
            DisclosureGroup("Entry text") {
                Text(entry.recordText).font(.subheadline).textSelection(.enabled).padding(.top, 10)
            }
        }
    }

    // MARK: - Optional observation presentation
    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.bold())
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
