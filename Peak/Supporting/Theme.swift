import SwiftUI
import UIKit

/// Peak's design tokens. Every color is dynamic, resolving per trait
/// collection, so the whole app supports light and dark mode through this one
/// file. The palette stays monochrome (ink on paper in light, foam on ocean in
/// dark) with a single green success accent.
enum Theme {
    // MARK: - Base palette

    static let oceanDeep = Color(white: 0.04)
    static let oceanMid = Color(white: 0.12)
    static let foam = Color(white: 0.98)
    static let ink = Color(white: 0.06)

    // MARK: - Canvas

    /// App canvas: white paper in light, near-black ocean in dark.
    static let background = dynamic(light: UIColor.white, dark: UIColor(white: 0.04, alpha: 1))

    // MARK: - Text

    // Light values are darker than Apple's defaults on purpose: the contrast
    // tests enforce 7:1 for all body text over the tinted glass surfaces.
    static let textPrimary = dynamic(light: UIColor(white: 0.10, alpha: 1), dark: UIColor(white: 0.98, alpha: 1))
    static let textSecondary = dynamic(light: UIColor(white: 0.22, alpha: 1), dark: UIColor(white: 0.88, alpha: 1))
    static let textMuted = dynamic(light: UIColor(white: 0.28, alpha: 1), dark: UIColor(white: 0.80, alpha: 1))
    /// Text placed on `glassStrongTint` (selected chips).
    static let textInverse = dynamic(light: UIColor(white: 0.98, alpha: 1), dark: UIColor(white: 0.06, alpha: 1))

    /// Destructive action text (delete / reset). Tuned to clear the app's 7:1 key-text bar on the
    /// glassDimTint surfaces it renders on, in both light and dark, while reading clearly as "danger".
    static let destructive = dynamic(
        light: UIColor(red: 0.56, green: 0.0, blue: 0.10, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.52, blue: 0.50, alpha: 1)
    )

    /// Monochrome accent used for tint: ink in light, foam in dark.
    static let accent = textPrimary

    static let surfGreen = dynamic(
        light: UIColor(red: 0.00, green: 0.50, blue: 0.27, alpha: 1),
        dark: UIColor(red: 0.22, green: 0.74, blue: 0.48, alpha: 1)
    )

    // MARK: - Glass surfaces

    static let glassTint = dynamic(
        light: UIColor(white: 0.0, alpha: 0.06),
        dark: UIColor(white: 1.0, alpha: 0.12)
    )
    static let glassDimTint = dynamic(
        light: UIColor(white: 0.0, alpha: 0.04),
        dark: UIColor(white: 1.0, alpha: 0.06)
    )
    /// Near-solid fill for selected chips; pair with `textInverse`.
    static let glassStrongTint = dynamic(
        light: UIColor(white: 0.0, alpha: 0.85),
        dark: UIColor(white: 1.0, alpha: 0.85)
    )
    static let surface = dynamic(
        light: UIColor(white: 0.0, alpha: 0.04),
        dark: UIColor(white: 1.0, alpha: 0.06)
    )
    /// Hairline border on glass cards.
    static let glassStroke = dynamic(
        light: UIColor(white: 0.0, alpha: 0.10),
        dark: UIColor(white: 1.0, alpha: 0.18)
    )

    // MARK: - Layout scale

    /// 4pt-based spacing scale; prefer these over ad-hoc values.
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// Corner radius scale: inputs < cards < sections.
    enum Radius {
        static let input: CGFloat = 14
        static let card: CGFloat = 20
        static let section: CGFloat = 24
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
