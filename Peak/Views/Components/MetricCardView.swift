import SwiftUI

struct MetricCardView: View {
    let title: String
    let value: String
    let subtitle: String?

    init(title: String, value: String, subtitle: String? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // `textCase` uppercases for display only; `title.uppercased()` would
            // also change the string VoiceOver speaks (letter-by-letter for short
            // titles), so keep the transform presentation-only.
            Text(title)
                .textCase(.uppercase)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        // Read the title + value + subtitle as one unit instead of as separate,
        // unpaired VoiceOver stops.
        .accessibilityElement(children: .combine)
    }
}
