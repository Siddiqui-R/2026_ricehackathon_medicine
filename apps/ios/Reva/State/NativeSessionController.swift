import Combine
// Own the native login and selected workspace. Tokens are stored only in the device Keychain.
import Foundation
import Security

private enum NativeSessionKeychain {
    static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "health.revamed.Reva.session", kSecAttrAccount as String: "current",
    ]
    static func read() -> NativeAccountSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let session = try? JSONDecoder().decode(NativeAccountSession.self, from: data),
            (try? session.validate()) != nil
        else { return nil }
        return session
    }
    static func save(_ session: NativeAccountSession) throws {
        let data = try JSONEncoder().encode(session)
        let fields: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, fields as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(
                query.merging(fields, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw RevaError.invalid("Your sign-in could not be saved securely. Please try again.")
        }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

@MainActor final class NativeSessionController: ObservableObject {
    @Published var store: AppStore?
    @Published var session: NativeAccountSession?
    @Published var workspaceID = UUID()
    @Published var error: String?
    @Published var busy = false
    @Published var demoPerson = NativeDemoPerson.jordan

    init() {
        if let saved = NativeSessionKeychain.read() { openAccount(saved) }
    }
    func signIn(email: String, password: String, name: String? = nil) async -> Bool {
        guard !busy else { return false }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let result = try await NativeAuthClient().authenticate(
                email: email, password: password, name: name)
            try NativeSessionKeychain.save(result)
            openAccount(result)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    private func openAccount(_ session: NativeAccountSession) {
        store?.closeWorkspace()
        self.session = session
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RevaAccounts", isDirectory: true)
            .appendingPathComponent(NativeAccount.directoryName(session.user.id), isDirectory: true)
        let next = AppStore(repository: LocalRepository(directory: root), account: session)
        next.sessionExpired = { [weak self] in self?.expire(session.token) }
        store = next
        workspaceID = UUID()
    }
    func openDemo(_ person: NativeDemoPerson = .jordan) {
        guard session == nil else { return }
        store?.closeWorkspace()
        demoPerson = person
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(
                person == .jordan ? "Reva" : "RevaDemo-" + person.rawValue, isDirectory: true)
        store = AppStore(repository: LocalRepository(directory: root), demoPerson: person)
        workspaceID = UUID()
    }
    func signOut(all: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let exitingStore = store
        exitingStore?.suspendProviderWork()
        do {
            if let session {
                await store?.synchronizeAccount()
                do { try await NativeAuthClient(token: session.token).logout(all: all) } catch let failure
                    as NativeAuthFailure where failure.status == 401
                {}
            }
            finishSignOut()
        } catch {
            if store === exitingStore {
                exitingStore?.resumeProviderWork()
                exitingStore?.errorMessage = error.localizedDescription
            }
        }
    }
    func finishSignOut() {
        store?.closeWorkspace()
        NativeSessionKeychain.clear()
        session = nil
        store = nil
        workspaceID = UUID()
    }
    private func expire(_ token: String) {
        guard session?.token == token else { return }
        // Keep the workspace mounted so a recording or open editor cannot be lost on expiry.
        store?.cancelProviderRequests()
        store?.stopBackgroundUpdates()
        NativeSessionKeychain.clear()
        store?.needsSignIn = true
        store?.syncStatus = "Saved on this device · log in again to sync"
        store?.notice =
            "Your session ended. Finish any recording or edits, then log in again from your account menu."
    }
}
