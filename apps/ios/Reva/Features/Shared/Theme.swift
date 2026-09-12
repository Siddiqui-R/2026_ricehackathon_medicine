// Purpose: Define the heart-red palette and its semantic roles.
// Inputs: Hex values from design/palette.json, selected September 12, 2026.
// Outputs: SwiftUI colors and UIKit/SwiftUI hex conversion initializers.
// Side effects: None; colors use fixed light-appearance values with no adaptive substitutions.

import SwiftUI

// MARK: - RevaTheme
/// Define the heart-red palette and its semantic roles.
enum RevaTheme {
    // MARK: - Palette values
    // Heart red and ivory, softened from comparison option M. Light appearance only; dark roles are reserved in palette.json.
    static let blushIvory = Color(hex: 0xFBF7F5), heartRed = Color(hex: 0xB84250),
        deepRed = Color(hex: 0x8C2F3B)
    static let petal = Color(hex: 0xFAE6E5), linen = Color(hex: 0xDBCBC9), white = Color(hex: 0xFFFFFF)
    // MARK: - Semantic surface and action roles
    // Contrast-checked pairings: white on heartRed 5.3:1, heartRed on blushIvory 5.0:1, deepRed on petal 6.8:1.
    static let canvas = blushIvory  // Page background.
    static let surface = white  // Outlined cards, tiles, and unselected chips.
    static let accent = heartRed  // Primary actions, selected navigation, the heart glyph, row icons.
    static let accentText = deepRed  // Chip labels, mode badges, small red text; accent alone is only 4.45:1 on petal.
    static let soft = petal  // Chips, notices, circular icon fills.
    static let hairline = linen  // Card, tile, and chip outlines.
    static let buttonText = white  // Text on filled heart-red buttons.
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
