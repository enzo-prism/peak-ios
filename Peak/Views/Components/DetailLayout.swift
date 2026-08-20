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

struct LibrarySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Destructive library action. 44 pt minimum (HIG) and `Theme.destructive` so
/// the label reads as danger on glass, matching session detail.
struct LibraryDestructiveButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: "trash")
                .foregroundStyle(Theme.destructive)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .glassButtonStyle(prominent: false)
    }
}
