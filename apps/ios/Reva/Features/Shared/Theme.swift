// Purpose: Define the exact six-color palette and its semantic roles.
// Inputs: User-supplied RGB hex values.
// Outputs: SwiftUI colors and UIKit/SwiftUI hex conversion initializers.
// Side effects: None; colors use fixed values with no adaptive substitutions.

import SwiftUI

// MARK: - RevaTheme
/// Define the exact six-color palette and its semantic roles.
enum RevaTheme {
    // MARK: - Exact palette values
    // Exact six-color user palette, reaffirmed September12. No adaptive color substitutions.
    static let ivory = Color(hex: 0xFAF4F4), gold = Color(hex: 0xC8A07D), slate = Color(hex: 0xA2B7BC)
    static let teal = Color(hex: 0x0A5B6C), aqua = Color(hex: 0x6FABB6), sky = Color(hex: 0xE1ECEE)
    // MARK: - Semantic surface and action roles
    // Opaque supplied Sky backdrop and warm Ivory cards, with no blended blue substitute.
    static let canvas = sky
    static let surface = ivory
    static let accent = teal
    static let soft = sky
    static let buttonText = ivory

}

// MARK: - UIColor
/// Convert an integer RGB value into an opaque UIKit color.
extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

// MARK: - Color
/// Convert an integer RGB value into an explicit opaque sRGB SwiftUI color.
extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB, red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}
