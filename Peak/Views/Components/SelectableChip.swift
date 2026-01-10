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
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SelectableChip(label: "Trestles", systemImage: "mappin", isSelected: true) {}
        .padding()
        .background(Theme.background)
}
