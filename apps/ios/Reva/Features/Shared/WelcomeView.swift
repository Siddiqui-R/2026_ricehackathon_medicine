// Purpose: Introduce the fictional demo and its primary journeys.
// Inputs: A caller-provided enter action.
// Outputs: The onboarding screen and Explore Reva action.
// Side effects: Invokes the caller when the user enters; cannot be interactively dismissed.

import SwiftUI

// MARK: - WelcomeView
/// Introduce the fictional demo and its primary journeys.
struct WelcomeView: View {
    // MARK: - Inputs and view state

    let enter: () -> Void
    // MARK: - Rendering and navigation
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Image(systemName: "heart.text.square.fill").font(.system(size: 64)).foregroundStyle(
                RevaTheme.accent)
            Text("Reva").font(.system(size: 48, weight: .bold, design: .rounded))
            Text("Making every\nappointment count.").font(.largeTitle.bold())
            Text("Your records, your questions, and a clearer conversation with your doctor.").font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                Label("Bring your records together", systemImage: "doc.text")
                Label("Prepare with relevant history", systemImage: "list.bullet.clipboard")
                Label("Keep the details after your visit", systemImage: "waveform")
            }
            Spacer()
            Text(
                "Explore with a fictional profile. Summaries and booking are local demonstrations; live services are not connected."
            ).font(.footnote).foregroundStyle(.secondary)
            Button("Explore Reva", action: enter).buttonStyle(PrimaryButtonStyle())
        }.padding(28).background(RevaTheme.canvas).interactiveDismissDisabled()
    }
}
