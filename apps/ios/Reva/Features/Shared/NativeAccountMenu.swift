// Account controls live behind the avatar on every native tab.
import SwiftUI

struct NativeAccountMenu: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var account: NativeSessionController
    @State private var settings = false
    @State private var switching = false
    var body: some View {
        Menu {
            Text(store.snapshot?.profile.name ?? "Your account")
            if store.needsSignIn {
                Button("Log in again") { account.finishSignOut() }
            }
            Button {
                settings = true
            } label: {
                Label("View settings", systemImage: "gearshape")
            }
            if store.account == nil {
                Button {
                    switching = true
                } label: {
                    Label("Switch account", systemImage: "person.2")
                }
            }
            Button(role: .destructive) {
                Task { await account.signOut() }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Text(store.snapshot?.profile.initials ?? "R").font(.caption.bold())
                .foregroundStyle(RevaTheme.accentText).frame(width: 36, height: 36)
                .background(RevaTheme.soft, in: Circle())
        }.accessibilityLabel("\(store.snapshot?.profile.name ?? "Your account") — account options")
            .disabled(account.busy)
            .sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
            .sheet(isPresented: $switching) {
                NavigationStack {
                    RevaForm {
                        Section {
                            Text("Each example keeps its own saved changes.").foregroundStyle(.secondary)
                        }
                        ForEach(NativeDemoPerson.allCases) { person in
                            Button {
                                switching = false
                                account.openDemo(person)
                            } label: {
                                HStack(spacing: 14) {
                                    Text(person.initials).font(.headline).frame(width: 40, height: 40)
                                        .background(RevaTheme.soft, in: Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(person.name)
                                        Text(person.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if account.demoPerson == person { Image(systemName: "checkmark") }
                                }.padding(.vertical, 8)
                            }.disabled(account.demoPerson == person)
                        }
                    }.navigationTitle("Switch demo account").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { switching = false }
                            }
                        }
                }
            }
    }
}
