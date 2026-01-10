import SwiftUI

struct GlassContainer<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 20, tint: Color = Theme.glassTint, isInteractive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let glass = isInteractive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint)
            self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            )
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color = Theme.glassTint, isInteractive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            let glass = isInteractive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint)
            self.glassEffect(glass, in: .capsule)
        } else {
            self.background(
                Capsule().fill(tint)
            )
        }
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}
