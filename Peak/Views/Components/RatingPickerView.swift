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
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressFeedbackButtonStyle())
                .accessibilityLabel("Rate \(value) stars")
            }
            if rating > 0 {
                Button {
                    rating = 0
                } label: {
                    Text("Clear")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassCapsule(tint: Theme.glassDimTint, isInteractive: true)
                }
                .buttonStyle(PressFeedbackButtonStyle())
                .accessibilityLabel("Clear rating")
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating) out of 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                rating = min(5, rating + 1)
            case .decrement:
                rating = max(0, rating - 1)
            @unknown default:
                break
            }
        }
    }
}

#Preview {
    RatingPickerView(rating: .constant(4))
        .padding()
        .background(Theme.background)
}
