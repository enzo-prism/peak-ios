import SwiftUI

extension View {
    /// Caps content at a comfortable reading measure and centers it on large
    /// canvases (iPad, landscape, Split View). This is a no-op at iPhone-portrait
    /// widths, so it only reshapes regular-width layouts and never changes the
    /// iPhone appearance the UI tests baseline against.
    ///
    /// HIG (Layout): keep comfortable margins and don't stretch content across a
    /// wide display — running text and cards read best around a 600–760pt measure.
    func readableContentWidth(_ maxWidth: CGFloat = 720) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
