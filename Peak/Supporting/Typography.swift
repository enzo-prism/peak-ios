import SwiftUI

extension Font {
    /// Peak's branded typeface. Single source of truth for the app's font family so the
    /// family name isn't duplicated across every view. `relativeTo` keeps text responsive
    /// to Dynamic Type.
    static func peak(_ size: CGFloat, relativeTo textStyle: TextStyle = .body) -> Font {
        .custom(peakFontName, size: size, relativeTo: textStyle)
    }

    private static let peakFontName = "Avenir Next"

    // Semantic tokens for the most common roles. Prefer these over raw point sizes.
    static var peakSectionHeader: Font { peak(12, relativeTo: .caption).weight(.semibold) }
    static var peakCaption: Font { peak(12, relativeTo: .caption) }
    static var peakBody: Font { peak(15, relativeTo: .body) }
    static var peakSubheadline: Font { peak(14, relativeTo: .subheadline) }
    static var peakHeadline: Font { peak(18, relativeTo: .headline) }
}
