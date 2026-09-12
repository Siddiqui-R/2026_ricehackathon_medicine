// Purpose: Render the common appointment-list row without owning navigation.
// Inputs: A Visit.
// Outputs: Appointment title, localized time, provider, and icon.
// Side effects: None; the enclosing screen handles selection.

import SwiftUI

// MARK: - VisitRow
/// Render the common appointment-list row without owning navigation.
struct VisitRow: View {
    let visit: Visit
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: "calendar")
            VStack(alignment: .leading, spacing: 5) {
                Text(visit.title).font(.headline).foregroundStyle(.primary)
                Text(RevaDate.display(visit.date, time: true, zone: visit.timeZone)).font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(visit.provider).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }.contentShape(Rectangle())
    }
}
