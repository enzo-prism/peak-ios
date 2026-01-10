import SwiftUI

struct RatingPickerView: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = value
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .foregroundStyle(value <= rating ? Theme.textPrimary : Theme.textMuted.opacity(0.4))
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rate \(value) stars")
            }
            if rating > 0 {
                Button {
                    rating = 0
                } label: {
                    Text("Clear")
                        .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassCapsule(tint: Theme.glassDimTint, isInteractive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear rating")
            }
        }
    }
}

#Preview {
    RatingPickerView(rating: .constant(4))
        .padding()
        .background(Theme.background)
}
