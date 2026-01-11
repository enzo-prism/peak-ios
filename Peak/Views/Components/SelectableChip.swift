import SwiftUI

struct SelectableChip: View {
    let label: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                }
                Text(label)
                    .font(.custom("Avenir Next", size: 15, relativeTo: .subheadline).weight(.semibold))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .foregroundStyle(isSelected ? Theme.textInverse : Theme.textPrimary)
            .glassCapsule(tint: isSelected ? Theme.glassStrongTint : Theme.glassDimTint, isInteractive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressFeedbackButtonStyle())
    }
}

struct PressFeedbackButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.98
    var pressedOpacity: Double = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    SelectableChip(label: "Trestles", systemImage: "mappin", isSelected: true) {}
        .padding()
        .background(Theme.background)
}
