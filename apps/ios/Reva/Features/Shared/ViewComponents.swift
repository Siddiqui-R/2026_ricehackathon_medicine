// Purpose: Provide shared cards, pages, labels, notices, and primary button styling.
// Inputs: Caller-supplied text, symbols, view content, and button press state.
// Outputs: Reusable views styled with RevaTheme.
// Side effects: None directly; supplied child content or buttons may define their own actions.

import SwiftUI

// MARK: - PrimaryButtonStyle
/// Style a primary action with the shared palette and visible pressed feedback.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).padding(
            .horizontal, 12
        )
        .foregroundStyle(RevaTheme.buttonText).background(
            RevaTheme.accent.opacity(configuration.isPressed ? 0.78 : 1),
            in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - RevaCard
/// Wrap related content in the shared outlined card surface.
struct RevaCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).outlined()
    }
}

// MARK: - View.outlined
/// Apply the outlined treatment: a white surface with a hairline border, so red stays reserved for actions and status.
extension View {
    func outlined(radius: CGFloat = 10) -> some View {
        background(RevaTheme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(RevaTheme.hairline, lineWidth: 1))
    }
}

// MARK: - SectionHeading
/// Render a consistent section heading inside a page.
struct SectionHeading: View {
    let title: String
    var body: some View {
        Text(title).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
    }
}

// MARK: - ModeBadge
/// Label the origin or mode of the content that follows.
struct ModeBadge: View {
    var text = "FICTIONAL DEMO"
    var body: some View {
        Text(text).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(RevaTheme.accentText).padding(
            .horizontal, 9
        ).padding(.vertical, 6).background(RevaTheme.soft, in: Capsule())
    }
}

// MARK: - StatusChip
/// Show a short state such as "Brief ready" as a petal capsule with deep-red text.
struct StatusChip: View {
    let text: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }.font(.caption.weight(.semibold)).foregroundStyle(RevaTheme.accentText).padding(.horizontal, 9)
            .padding(.vertical, 5).background(RevaTheme.soft, in: Capsule())
    }
}

// MARK: - IconTile
/// Provide a decorative symbol tile while leaving accessibility meaning to surrounding text.
struct IconTile: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.title3).foregroundStyle(RevaTheme.accent).frame(width: 42, height: 42)
            .background(RevaTheme.soft, in: Circle()).accessibilityHidden(true)
    }
}

// MARK: - DetailLine
/// Render an icon and secondary detail without truncating multiline text.
struct DetailLine: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary).fixedSize(
            horizontal: false, vertical: true)
    }
}

// MARK: - StatusNotice
/// Present an explanatory status message with an optional context symbol.
struct StatusNotice: View {
    let title: String
    let message: String
    var symbol = "info.circle"
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(RevaTheme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.bold())
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
            RevaTheme.soft, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Page
/// Provide shared scroll behavior, page spacing, and the blush canvas backdrop.
struct Page<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }.padding(.horizontal, 20).padding(.top, 10)
                .padding(.bottom, 32)
        }.background(RevaTheme.canvas)
    }
}

// MARK: - RevaForm
/// Apply the shared palette to native editor forms.
struct RevaForm<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        Form { content.listRowBackground(RevaTheme.surface) }
            .scrollContentBackground(.hidden).background(RevaTheme.canvas)
    }
}
