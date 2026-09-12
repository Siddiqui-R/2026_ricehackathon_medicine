import SwiftUI

@main struct RevaApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(RevaTheme.accent)
                .preferredColorScheme(.light)
        }
    }
}
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var welcome = false
    @State private var selectedTab: RevaTab = .summary
    @State private var recordsGeneration = 0
    var body: some View {
        Group {
            if let error = store.startupError {
                ContentUnavailableView { Label("Your data needs attention", systemImage: "externaldrive.badge.exclamationmark") } description: { Text(error) } actions: {
                    Button("Restore fictional demo") { store.perform { try store.resetDemo() } }.buttonStyle(.borderedProminent)
                }
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        SummaryView(showAllRecords: { recordsGeneration += 1; selectedTab = .records }, showMedicalProfile: { selectedTab = .medicalProfile })
                    }.tabItem { Label("Summary", systemImage: "heart.text.square") }.tag(RevaTab.summary)
                    NavigationStack { RecordsView() }.id(recordsGeneration).tabItem { Label("Records", systemImage: "folder") }.tag(RevaTab.records)
                    NavigationStack { VisitsView() }.tabItem { Label("Visits", systemImage: "calendar") }.tag(RevaTab.visits)
                    NavigationStack { MedicalProfileView() }.tabItem { Label("Medical profile", systemImage: "person.text.rectangle") }.tag(RevaTab.medicalProfile)
                }
            }
        }
        .alert("Something needs attention", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK", role: .cancel) { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        .sheet(isPresented: $welcome) { WelcomeView { hasSeenWelcome = true; welcome = false } }
        .onAppear { if !hasSeenWelcome { welcome = true } }
    }
}
private enum RevaTab: Hashable { case summary, records, visits, medicalProfile }
struct WelcomeView: View {
    let enter: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Image(systemName: "heart.text.square.fill").font(.system(size: 64)).foregroundStyle(RevaTheme.accent)
            Text("Reva").font(.system(size: 48, weight: .bold, design: .rounded))
            Text("Making every\nappointment count.").font(.largeTitle.bold())
            Text("Your records, your questions, and a clearer conversation with your doctor.").font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                Label("Bring your records together", systemImage: "doc.text")
                Label("Prepare with relevant history", systemImage: "list.bullet.clipboard")
                Label("Keep the details after your visit", systemImage: "waveform")
            }
            Spacer()
            Text("Explore with a fictional profile. Summaries and booking are local demonstrations; live services are not connected.").font(.footnote).foregroundStyle(.secondary)
            Button("Explore Reva", action: enter).buttonStyle(PrimaryButtonStyle())
        }.padding(28).background(RevaTheme.canvas).interactiveDismissDisabled()
    }
}
