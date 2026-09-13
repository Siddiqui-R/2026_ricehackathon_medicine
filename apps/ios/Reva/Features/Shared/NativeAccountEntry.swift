// Native sign-up/login and a separate demo entry use the hosted account API without embedding a website.
import SwiftUI

struct NativeAccountEntry: View {
    @EnvironmentObject private var account: NativeSessionController
    @State private var form: AccountFormMode?
    var body: some View {
        if let store = account.store {
            RootView().environmentObject(store).id(account.workspaceID)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("reva.").font(.system(size: 42, weight: .bold)).foregroundStyle(RevaTheme.accent)
                        .padding(.bottom, 44)
                    Text("Making every\nappointment count.").font(.system(size: 42, weight: .bold)).tracking(
                        -1.5)
                    Text("Your records, your health, and a clearer conversation with your doctor.")
                        .font(.title3).foregroundStyle(.secondary)
                    Button("Sign up") { form = .signup }.buttonStyle(PrimaryButtonStyle())
                    Button("Log in") { form = .login }.buttonStyle(.bordered).controlSize(.large)
                        .frame(maxWidth: .infinity)
                    Button("View the demo") { account.openDemo() }.font(.headline).frame(maxWidth: .infinity)
                    if let error = account.error {
                        Text(error).font(.footnote).foregroundStyle(RevaTheme.accentText)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Your original records, kept together", systemImage: "folder")
                        Label(
                            "A clearer conversation at your appointment", systemImage: "list.bullet.clipboard"
                        )
                        Label("Record, transcribe and revisit your visit", systemImage: "waveform")
                    }.font(.subheadline).foregroundStyle(.secondary).padding(.top, 28)
                }.padding(28).frame(maxWidth: 540)
            }.background(RevaTheme.canvas)
                .sheet(item: $form) { mode in NavigationStack { NativeAccountForm(mode: mode) } }
        }
    }
}
enum AccountFormMode: String, Identifiable {
    case login, signup
    var id: String { rawValue }
}
private struct NativeAccountForm: View {
    @EnvironmentObject private var account: NativeSessionController
    @Environment(\.dismiss) private var dismiss
    let mode: AccountFormMode
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    var body: some View {
        RevaForm {
            Section {
                Text(mode == .signup ? "Start with your own records." : "Welcome back.")
                    .font(.largeTitle.bold()).listRowBackground(Color.clear)
                Text(
                    mode == .signup
                        ? "A private workspace for your records, questions and visits."
                        : "Your records and visit notes, exactly where you left them."
                )
                .foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
            Section {
                if mode == .signup { TextField("Name", text: $name).textContentType(.name) }
                TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack {
                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(mode == .signup ? .newPassword : .password).textInputAutocapitalization(
                        .never
                    ).autocorrectionDisabled()
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }
            } footer: {
                if mode == .signup { Text("At least 8 characters, 1 capital letter, 1 number and 1 symbol.") }
            }
            if let error = account.error { Section { Text(error).foregroundStyle(RevaTheme.accentText) } }
            Section {
                Button {
                    Task {
                        if await account.signIn(
                            email: email, password: password, name: mode == .signup ? name : nil)
                        {
                            password = ""
                            dismiss()
                        }
                    }
                } label: {
                    if account.busy {
                        ProgressView()
                    } else {
                        Text(mode == .signup ? "Create account" : "Log in")
                    }
                }.disabled(
                    account.busy || email.isEmpty || password.isEmpty || (mode == .signup && name.isEmpty))
            }
        }.navigationTitle(mode == .signup ? "Sign up" : "Log in").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(account.busy)
                }
            }
            .interactiveDismissDisabled(account.busy)
    }
}
