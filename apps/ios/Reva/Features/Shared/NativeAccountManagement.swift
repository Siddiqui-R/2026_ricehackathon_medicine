// Password confirmation is required before destructive account management.
import SwiftUI

enum NativeAccountAction: String, Identifiable {
    case password, delete
    var id: String { rawValue }
}
struct NativeAccountManagement: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var account: NativeSessionController
    @Environment(\.dismiss) private var dismiss
    let action: NativeAccountAction
    @State private var current = ""
    @State private var replacement = ""
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var error: String?
    var body: some View {
        RevaForm {
            Section {
                SecureField("Current password", text: $current).textContentType(.password)
                if action == .password {
                    SecureField("New password", text: $replacement).textContentType(.newPassword)
                    Text("At least 8 characters, 1 capital letter, 1 number, and 1 symbol.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(
                        "Permanently delete your account, records, and uploaded files. This cannot be undone."
                    )
                    .foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(RevaTheme.accentText) }
                if busy { ProgressView("Updating your account…") }
                Button(
                    action == .password ? "Save new password" : "Delete account",
                    role: action == .delete ? .destructive : nil
                ) {
                    if action == .delete { confirmDelete = true } else { Task { await submit() } }
                }.disabled(
                    busy || current.isEmpty
                        || (action == .password && NativeAccount.passwordProblem(replacement) != nil))
            }
        }.navigationTitle(action == .password ? "Change password" : "Delete account")
            .navigationBarTitleDisplayMode(.inline).interactiveDismissDisabled(busy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
            }
            .confirmationDialog(
                "Permanently delete this account and its records?", isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Permanently delete account", role: .destructive) { Task { await submit() } }
            }
    }
    private func submit() async {
        guard let session = store.account, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let client = NativeAuthClient(token: session.token)
            if action == .password {
                try await client.changePassword(current: current, new: replacement)
                store.notice = "Password changed. Your other sessions were logged out."
                dismiss()
            } else {
                try await client.deleteAccount(password: current)
                store.closeWorkspace()
                // This directory is scoped to the authenticated account, never to demo data.
                do { try FileManager.default.removeItem(at: store.repository.directory) } catch {
                    account.error =
                        "Your account was deleted. A local copy could not be removed; remove Reva from this device to clear it."
                }
                account.finishSignOut()
            }
        } catch let failure as NativeAuthFailure where failure.status == 401 {
            error = "The current password is incorrect. No changes were made."
        } catch { self.error = error.localizedDescription }
    }
}
