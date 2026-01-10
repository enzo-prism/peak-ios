import SwiftUI

struct StatCardView: View {
    let title: String
    let value: String
    let subtitle: String?

    var body: some View {
        let sanitizedTitle = title.lowercased().replacingOccurrences(of: " ", with: "-")
        let identifier = "stats.card.\(sanitizedTitle)"
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.custom("Avenir Next", size: 11, relativeTo: .caption).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.custom("Avenir Next", size: 24, relativeTo: .title).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22, tint: Theme.glassTint, isInteractive: false)
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    StatCardView(title: "Sessions", value: "24", subtitle: "Last 90 days")
        .padding()
        .background(Theme.background)
}
