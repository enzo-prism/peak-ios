import SwiftUI

enum Theme {
    static let oceanDeep = Color(white: 0.04)
    static let oceanMid = Color(white: 0.12)
    static let foam = Color(white: 0.98)
    static let sand = Color(white: 0.88)
    static let ink = Color(white: 0.06)

    static let glassTint = Color(white: 1.0, opacity: 0.12)
    static let glassStrongTint = Color(white: 1.0, opacity: 0.5)
    static let glassDimTint = Color(white: 1.0, opacity: 0.06)
    static let surface = Color.white.opacity(0.06)

    static let textPrimary = foam
    static let textSecondary = foam.opacity(0.9)
    static let textMuted = foam.opacity(0.8)
    static let textInverse = ink

    static var background: some View {
        Color.black
    }
}
