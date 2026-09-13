// Compact native profile with section-specific edits and links to original report evidence.
import SwiftUI

private struct ProfileEditTarget: Identifiable {
    var field: MedicalProfileField?
    var id: String { field?.rawValue ?? "identity" }
}
struct MedicalProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: ProfileEditTarget?
    var body: some View {
        Page {
            if let profile = store.snapshot?.profile {
                HStack(spacing: 12) {
                    Text(profile.initials).font(.headline).foregroundStyle(RevaTheme.accentText)
                        .frame(width: 42, height: 42).background(RevaTheme.soft, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name).font(.headline)
                        if !profile.dateOfBirth.isEmpty {
                            Text("Born " + RevaDate.display(profile.dateOfBirth)).font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    editButton("personal details") { editing = .init(field: nil) }
                }.padding(.vertical, 4)
                HStack(alignment: .top) {
                    Text(store.profileUpdateMessage).font(.footnote).foregroundStyle(.secondary)
                    if store.profileUpdateMessage.contains("could not") {
                        Button("Retry") { store.retryMedicalProfile() }.font(.footnote)
                    }
                }
                ForEach(MedicalProfileField.allCases) { field in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: field.symbol).foregroundStyle(RevaTheme.accent).frame(width: 24)
                            Text(field.title).font(.headline)
                            Spacer()
                            editButton(field.title.lowercased()) { editing = .init(field: field) }
                        }
                        let values = field.values(profile)
                        if values.isEmpty {
                            Text("Not provided").font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(value).font(.subheadline).textSelection(.enabled)
                                if let fact = field.facts(
                                    profile.aiMedicalHistory?.facts ?? NativeMedicalProfile.emptyFacts
                                ).first(where: {
                                    NativeMedicalProfile.key($0.text) == NativeMedicalProfile.key(value)
                                }) {
                                    ForEach(fact.recordIDs, id: \.self) { id in
                                        if let record = store.record(id) {
                                            NavigationLink {
                                                RecordDetailView(id: id)
                                            } label: {
                                                Label(record.title, systemImage: "doc.text")
                                            }
                                            .font(.caption).foregroundStyle(RevaTheme.accentText)
                                        }
                                    }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).outlined(radius: 8)
                }
                Text(
                    "Review report-derived details against their linked originals. Your own entries and corrections are preserved."
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Medical profile").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { target in
                if let profile = store.snapshot?.profile {
                    NavigationStack { MedicalProfileEditor(profile: profile, field: target.field) }
                }
            }
    }
    private func editButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "pencil").font(.system(size: 15)).frame(width: 36, height: 36).contentShape(
                Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Edit " + label)
    }
}
