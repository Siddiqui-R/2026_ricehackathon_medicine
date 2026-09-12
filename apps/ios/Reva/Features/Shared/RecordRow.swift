// Purpose: Render the common record-list row without owning navigation.
// Inputs: A MedicalRecord.
// Outputs: Title, kind, date, icon, and review indicator.
// Side effects: None; the enclosing screen handles selection.

import SwiftUI

// MARK: - RecordRow
/// Render the common record-list row without owning navigation.
struct RecordRow: View {
    // MARK: - Inputs and view state

    let record: MedicalRecord
    // MARK: - Rendering and navigation
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            IconTile(symbol: record.symbol)
            VStack(alignment: .leading, spacing: 5) {
                Text(record.title).font(.headline).foregroundStyle(.primary).fixedSize(
                    horizontal: false, vertical: true)
                Text("\(record.kind) · \(RevaDate.display(record.date))").font(.caption).foregroundStyle(
                    .secondary)
                if record.needsReview {
                    Label("Review extraction", systemImage: "exclamationmark.circle").font(
                        .caption.weight(.medium)
                    ).foregroundStyle(RevaTheme.accent)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary).padding(
                .top, 5)
        }.padding(.vertical, 5).contentShape(Rectangle())
    }
}
