// Purpose: Start the iPhone app with one shared observable state owner.
// Inputs: Application launch and the persisted data loaded by AppStore.
// Outputs: The root scene with the shared store and fixed light appearance.
// Side effects: Creates AppStore, which loads or initializes local state.

import SwiftUI

// MARK: - RevaApp
/// Start the iPhone app with one shared observable state owner.
@main struct RevaApp: App {
    // MARK: - Inputs and view state

    @StateObject private var store = AppStore()
    // MARK: - Rendering and navigation
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(RevaTheme.accent)
                .preferredColorScheme(.light)
        }
    }
}
