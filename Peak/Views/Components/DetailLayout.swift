import SwiftUI

struct DetailMetricGrid<Content: View>: View {
    let minColumnWidth: CGFloat
    let spacing: CGFloat
    let content: () -> Content

    init(
        minColumnWidth: CGFloat = 148,
        spacing: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.minColumnWidth = minColumnWidth
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            content()
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: minColumnWidth),
                spacing: spacing,
                alignment: .top
            )
        ]
    }
}

struct DetailInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleText
                Spacer(minLength: 12)
                valueText
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                titleText
                valueText
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(Theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
