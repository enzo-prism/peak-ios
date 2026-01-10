import Foundation
import SwiftUI
import XCTest

@testable import Peak

private struct ContrastSample {
    let name: String
    let foreground: Color
    let background: RGBA
    let minimumRatio: CGFloat
}

final class ContrastTests: XCTestCase {
    func testContrastTokensMeetMinimums() {
        let baseMid = composedBackground(base: Theme.oceanMid)
        let baseDeep = composedBackground(base: Theme.oceanDeep)
        let glassDim = composedBackground(base: Theme.oceanMid, overlays: [Theme.glassDimTint])
        let glassTint = composedBackground(base: Theme.oceanMid, overlays: [Theme.glassTint])
        let strongGlass = composedBackground(base: Theme.oceanDeep, overlays: [Theme.glassStrongTint])
        let inputSurface = composedBackground(base: Theme.oceanMid, overlays: [Theme.glassDimTint, Theme.surface])

        let samples = [
            ContrastSample(name: "textPrimary on oceanDeep", foreground: Theme.textPrimary, background: baseDeep, minimumRatio: 7.0),
            ContrastSample(name: "textPrimary on oceanMid", foreground: Theme.textPrimary, background: baseMid, minimumRatio: 7.0),
            ContrastSample(name: "textPrimary on glassDim", foreground: Theme.textPrimary, background: glassDim, minimumRatio: 7.0),
            ContrastSample(name: "textPrimary on glassTint", foreground: Theme.textPrimary, background: glassTint, minimumRatio: 7.0),
            ContrastSample(name: "textPrimary on inputSurface", foreground: Theme.textPrimary, background: inputSurface, minimumRatio: 7.0),
            ContrastSample(name: "textSecondary on oceanMid", foreground: Theme.textSecondary, background: baseMid, minimumRatio: 7.0),
            ContrastSample(name: "textSecondary on glassDim", foreground: Theme.textSecondary, background: glassDim, minimumRatio: 7.0),
            ContrastSample(name: "textSecondary on glassTint", foreground: Theme.textSecondary, background: glassTint, minimumRatio: 7.0),
            ContrastSample(name: "textSecondary on inputSurface", foreground: Theme.textSecondary, background: inputSurface, minimumRatio: 7.0),
            ContrastSample(name: "textMuted on oceanMid", foreground: Theme.textMuted, background: baseMid, minimumRatio: 7.0),
            ContrastSample(name: "textMuted on glassDim", foreground: Theme.textMuted, background: glassDim, minimumRatio: 7.0),
            ContrastSample(name: "textMuted on glassTint", foreground: Theme.textMuted, background: glassTint, minimumRatio: 7.0),
            ContrastSample(name: "textMuted on inputSurface", foreground: Theme.textMuted, background: inputSurface, minimumRatio: 7.0),
            ContrastSample(name: "textInverse on glassStrong", foreground: Theme.textInverse, background: strongGlass, minimumRatio: 4.5)
        ]

        for sample in samples {
            assertContrast(sample)
        }
    }
}

private struct RGBA {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat
}

private func rgba(_ color: Color) -> RGBA {
    guard let cgColor = color.cgColor, let components = cgColor.components else {
        return RGBA(r: 0, g: 0, b: 0, a: 1)
    }

    if components.count == 2 {
        return RGBA(r: components[0], g: components[0], b: components[0], a: components[1])
    }

    if components.count >= 3 {
        return RGBA(r: components[0], g: components[1], b: components[2], a: cgColor.alpha)
    }

    return RGBA(r: 0, g: 0, b: 0, a: 1)
}

private func composedBackground(base: Color, overlays: [Color] = []) -> RGBA {
    var result = rgba(base)
    for overlay in overlays {
        result = blend(rgba(overlay), over: result)
    }
    return result
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

private func assertContrast(_ sample: ContrastSample, file: StaticString = #filePath, line: UInt = #line) {
    let ratio = contrastRatio(foreground: sample.foreground, background: sample.background)
    let formattedRatio = String(format: "%.2f", ratio)
    let message = "\(sample.name) contrast \(formattedRatio) below \(sample.minimumRatio)"
    XCTAssertGreaterThanOrEqual(ratio, sample.minimumRatio, message, file: file, line: line)
}

private func contrastRatio(foreground: Color, background: RGBA) -> CGFloat {
    let fg = rgba(foreground)
    let composite = fg.a < 1 ? blend(fg, over: background) : fg
    let l1 = relativeLuminance(composite)
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
