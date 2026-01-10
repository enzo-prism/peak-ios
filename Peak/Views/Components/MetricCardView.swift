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
            Text(title.uppercased())
                .font(.custom("Avenir Next", size: 11, relativeTo: .caption).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.custom("Avenir Next", size: 20, relativeTo: .title3).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
    }
}
