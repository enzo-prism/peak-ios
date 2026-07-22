import SwiftUI

struct StatCardView: View {
    let title: String
    let value: String
    let subtitle: String?

    var body: some View {
        let sanitizedTitle = title.lowercased().replacingOccurrences(of: " ", with: "-")
        let identifier = "stats.card.\(sanitizedTitle)"
        VStack(alignment: .leading, spacing: 8) {
            // Display-only uppercasing so VoiceOver still speaks the real words.
            Text(title)
                .textCase(.uppercase)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassTint, isInteractive: false)
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    StatCardView(title: "Sessions", value: "24", subtitle: "Last 90 days")
        .padding()
        .background(Theme.background)
}
