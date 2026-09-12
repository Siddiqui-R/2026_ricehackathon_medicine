import SwiftUI

enum RevaTheme {
    // Exact source palette. Adaptive roles are explicitly derived.
    static let ivory = Color(hex: 0xFAF4F4), gold = Color(hex: 0xC8A07D), slate = Color(hex: 0xA2B7BC)
    static let teal = Color(hex: 0x0A5B6C), aqua = Color(hex: 0x6FABB6), sky = Color(hex: 0xE1ECEE)
    static let canvas = adaptive(0xFAF4F4, 0x11191C)
    static let surface = adaptive(0xFFFFFF, 0x1D292D)
    static let accent = adaptive(0x0A5B6C, 0x8AC6D0)
    static let soft = adaptive(0xE1ECEE, 0x243C43)
    static let buttonText = adaptive(0xFFFFFF, 0x10292F)
    static func adaptive(_ light: UInt, _ dark: UInt) -> Color {
        Color(uiColor: UIColor { trait in UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light) })
    }
}
extension UIColor {
    convenience init(hex: UInt) { self.init(red: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: 1) }
}
extension Color { init(hex: UInt) { self.init(uiColor: UIColor(hex: hex)) } }
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).padding(.horizontal, 12)
            .foregroundStyle(RevaTheme.buttonText).background(RevaTheme.accent.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 15))
    }
}
struct RevaCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 16) { content }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(RevaTheme.surface, in: RoundedRectangle(cornerRadius: 22)) }
}
struct SectionHeading: View {
    let title: String
    var body: some View { Text(title).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10) }
}
struct ModeBadge: View {
    var text = "FICTIONAL DEMO"
    var body: some View { Text(text).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(RevaTheme.accent).padding(.horizontal, 9).padding(.vertical, 6).background(RevaTheme.soft, in: Capsule()) }
}
struct IconTile: View {
    let symbol: String
    var body: some View { Image(systemName: symbol).font(.title3).foregroundStyle(RevaTheme.accent).frame(width: 44, height: 44).background(RevaTheme.soft, in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true) }
}
struct DetailLine: View {
    let symbol: String
    let text: String
    var body: some View { Label(text, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
struct StatusNotice: View {
    let title: String
    let message: String
    var symbol = "info.circle"
    var body: some View { HStack(alignment: .top, spacing: 12) { Image(systemName: symbol).foregroundStyle(RevaTheme.accent); VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline.bold()); Text(message).font(.footnote).foregroundStyle(.secondary) } }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RevaTheme.soft, in: RoundedRectangle(cornerRadius: 16)) }
}
struct Page<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { content }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 32) }.background(RevaTheme.canvas) }
}
struct RecordRow: View {
    let record: MedicalRecord
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            IconTile(symbol: record.symbol)
            VStack(alignment: .leading, spacing: 5) {
                Text(record.title).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Text("\(record.kind) · \(RevaDate.display(record.date))").font(.caption).foregroundStyle(.secondary)
                if record.needsReview { Label("Review extraction", systemImage: "exclamationmark.circle").font(.caption.weight(.medium)).foregroundStyle(RevaTheme.accent) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary).padding(.top, 5)
        }.padding(.vertical, 5).contentShape(Rectangle())
    }
}
struct VisitRow: View {
    let visit: Visit
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: "calendar")
            VStack(alignment: .leading, spacing: 5) {
                Text(visit.title).font(.headline).foregroundStyle(.primary)
                Text(RevaDate.display(visit.date, time: true, zone: visit.timeZone)).font(.subheadline).foregroundStyle(.secondary)
                Text(visit.provider).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }.contentShape(Rectangle())
    }
}
