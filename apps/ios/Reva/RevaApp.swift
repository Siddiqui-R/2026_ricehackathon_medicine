// Purpose: Start the iPhone app with one shared observable state owner.
// Inputs: Application launch and the persisted data loaded by AppStore.
// Outputs: The root scene with the shared store, Central time default, and fixed light appearance.
// Side effects: Creates AppStore, which loads or initializes local state.

import SwiftUI

// MARK: - RevaApp
/// Start the iPhone app with one shared observable state owner.
@main struct RevaApp: App {
    // MARK: - Inputs and view state

    @StateObject private var account = NativeSessionController()
    // MARK: - Rendering and navigation
    var body: some Scene {
        WindowGroup {
            NativeAccountEntry().environmentObject(account).tint(RevaTheme.accent)
                .environment(\.timeZone, RevaDate.defaultTimeZone)
                .preferredColorScheme(.light)
        }
    }
}
