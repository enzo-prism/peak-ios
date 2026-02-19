import SwiftUI

struct GlassContainer<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: spacing) {
                    content()
                }
            } else {
                content()
            }
        #else
            content()
        #endif
    }
}

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 20, tint: Color = Theme.glassTint, isInteractive: Bool = false) -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                let glass = isInteractive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint)
                self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
            } else {
                self.background(
                    GlassFallbackSurface(
                        shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                        tint: tint
                    )
                )
            }
        #else
            self.background(
                GlassFallbackSurface(
                    shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                    tint: tint
                )
            )
        #endif
    }

    @ViewBuilder
    func glassCapsule(tint: Color = Theme.glassTint, isInteractive: Bool = true) -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                let glass = isInteractive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint)
                self.glassEffect(glass, in: .capsule)
            } else {
                self.background(
                    GlassFallbackSurface(shape: Capsule(), tint: tint)
                )
            }
        #else
            self.background(
                GlassFallbackSurface(shape: Capsule(), tint: tint)
            )
        #endif
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
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
        #else
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        #endif
    }

    @ViewBuilder
    func glassInput(cornerRadius: CGFloat = 14, tint: Color = Theme.glassDimTint) -> some View {
        self.glassCard(cornerRadius: cornerRadius, tint: tint, isInteractive: true)
    }

    @ViewBuilder
    func glassUnion(id: String, namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                self.glassEffectUnion(id: id, namespace: namespace)
            } else {
                self
            }
        #else
            self
        #endif
    }
}

private struct GlassFallbackSurface<S: Shape>: View {
    let shape: S
    let tint: Color

    var body: some View {
        shape
            .fill(tint)
            .overlay(
                shape.stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)
            )
    }
}
