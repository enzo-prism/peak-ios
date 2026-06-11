import SwiftUI
import UIKit
import XCTest

@testable import Peak

/// Verifies the design tokens meet the project's contrast bar (7:1 for text,
/// 4.5:1 for inverse text on strong fills) in BOTH light and dark mode, since
/// every Theme color is now a dynamic color.
final class ContrastTests: XCTestCase {
    func testContrastTokensMeetMinimumsInLightAndDark() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let name = style == .dark ? "dark" : "light"

            func resolved(_ color: Color) -> RGBA {
                rgba(UIColor(color).resolvedColor(with: traits))
            }

            let base = resolved(Theme.background)
            let card = blend(resolved(Theme.glassTint), over: base)
            let dim = blend(resolved(Theme.glassDimTint), over: base)
            let input = blend(resolved(Theme.surface), over: dim)
            let strong = blend(resolved(Theme.glassStrongTint), over: base)

            let samples: [(String, Color, RGBA, CGFloat)] = [
                ("textPrimary on background (\(name))", Theme.textPrimary, base, 7.0),
                ("textPrimary on card (\(name))", Theme.textPrimary, card, 7.0),
                ("textPrimary on dim (\(name))", Theme.textPrimary, dim, 7.0),
                ("textPrimary on input (\(name))", Theme.textPrimary, input, 7.0),
                ("textSecondary on card (\(name))", Theme.textSecondary, card, 7.0),
                ("textSecondary on dim (\(name))", Theme.textSecondary, dim, 7.0),
                ("textSecondary on input (\(name))", Theme.textSecondary, input, 7.0),
                ("textMuted on card (\(name))", Theme.textMuted, card, 7.0),
                ("textMuted on dim (\(name))", Theme.textMuted, dim, 7.0),
                ("textMuted on input (\(name))", Theme.textMuted, input, 7.0),
                ("textInverse on strong (\(name))", Theme.textInverse, strong, 4.5)
            ]

            for (label, foreground, background, minimum) in samples {
                let fg = blendIfTranslucent(resolved(foreground), over: background)
                let ratio = contrastRatio(fg, background)
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    minimum,
                    "\(label) contrast \(String(format: "%.2f", ratio)) below \(minimum)"
                )
            }
        }
    }
}

private struct RGBA {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat
}

private func rgba(_ color: UIColor) -> RGBA {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return RGBA(r: r, g: g, b: b, a: a)
}

private func blendIfTranslucent(_ foreground: RGBA, over background: RGBA) -> RGBA {
    foreground.a < 1 ? blend(foreground, over: background) : foreground
}

private func blend(_ foreground: RGBA, over background: RGBA) -> RGBA {
    let outAlpha = foreground.a + background.a * (1 - foreground.a)
    guard outAlpha > 0 else {
        return RGBA(r: 0, g: 0, b: 0, a: 0)
    }

    let r = (foreground.r * foreground.a + background.r * background.a * (1 - foreground.a)) / outAlpha
    let g = (foreground.g * foreground.a + background.g * background.a * (1 - foreground.a)) / outAlpha
    let b = (foreground.b * foreground.a + background.b * background.a * (1 - foreground.a)) / outAlpha

    return RGBA(r: r, g: g, b: b, a: outAlpha)
}

private func contrastRatio(_ foreground: RGBA, _ background: RGBA) -> CGFloat {
    let l1 = relativeLuminance(foreground)
    let l2 = relativeLuminance(background)
    let lighter = max(l1, l2)
    let darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)
}

private func relativeLuminance(_ color: RGBA) -> CGFloat {
    func linearize(_ component: CGFloat) -> CGFloat {
        if component <= 0.04045 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }

    let r = linearize(color.r)
    let g = linearize(color.g)
    let b = linearize(color.b)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
