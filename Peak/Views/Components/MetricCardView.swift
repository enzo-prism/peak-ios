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
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.custom("Avenir Next", size: 20, relativeTo: .title3).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
    }
}
