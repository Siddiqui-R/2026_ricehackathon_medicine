// Purpose: Coordinate main tabs, first-run onboarding, and shared error presentation.
// Inputs: AppStore and the persisted hasSeenWelcome preference.
// Outputs: Summary, Records, Visits, and Medical profile navigation stacks.
// Side effects: Updates the welcome preference and tab state; explicit recovery restores the fictional demo.

import SwiftUI

// MARK: - RootView
/// Coordinate main tabs, first-run onboarding, and shared error presentation.
struct RootView: View {
    // MARK: - Inputs and view state

    @EnvironmentObject private var store: AppStore
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var welcome = false
    @State private var confirmRestore = false
    @State private var selectedTab: RevaTab = .summary
    @State private var recordsGeneration = 0
    // MARK: - Rendering and navigation
    var body: some View {
        Group {
            if let error = store.startupError {
                ContentUnavailableView {
                    Label("Your data needs attention", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Restore fictional demo") { confirmRestore = true }.buttonStyle(
                        .borderedProminent)
                }
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        SummaryView(
                            showAllRecords: {
                                recordsGeneration += 1
                                selectedTab = .records
                            }, showMedicalProfile: { selectedTab = .medicalProfile })
                    }.tabItem { Label("Summary", systemImage: "heart.text.square") }.tag(RevaTab.summary)
                    NavigationStack { RecordsView() }.id(recordsGeneration).tabItem {
                        Label("Records", systemImage: "folder")
                    }.tag(RevaTab.records)
                    NavigationStack { VisitsView() }.tabItem { Label("Visits", systemImage: "calendar") }.tag(
                        RevaTab.visits)
                    NavigationStack { MedicalProfileView() }.tabItem {
                        Label("Medical profile", systemImage: "person.text.rectangle")
                    }.tag(RevaTab.medicalProfile)
                }
            }
        }
        .alert(
            "Something needs attention",
            isPresented: Binding(
                get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .confirmationDialog(
            "Restore the fictional demo and replace your local changes?", isPresented: $confirmRestore,
            titleVisibility: .visible
        ) {
            Button("Restore demo", role: .destructive) { store.perform { try store.resetDemo() } }
        }
        .sheet(isPresented: $welcome) {
            WelcomeView {
                hasSeenWelcome = true
                welcome = false
            }
        }
        .onAppear { if !hasSeenWelcome { welcome = true } }
    }
}

// MARK: - RevaTab
/// Keep tab-selection identities scoped to root navigation.
private enum RevaTab: Hashable { case summary, records, visits, medicalProfile }
