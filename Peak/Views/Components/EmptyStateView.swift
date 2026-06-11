import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let image: Image

    init(title: String, message: String, systemImage: String) {
        self.title = title
        self.message = message
        self.image = Image(systemName: systemImage)
    }

    init(title: String, message: String, imageName: String) {
        self.title = title
        self.message = message
        self.image = Image(imageName)
    }

    var body: some View {
        VStack(spacing: 16) {
            image
                .renderingMode(.template)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.xl)
        .glassCard(cornerRadius: Theme.Radius.section, tint: Theme.glassDimTint, isInteractive: false)
        .padding()
    }
}

#Preview {
    EmptyStateView(
        title: "No sessions yet",
        message: "Log your first surf and start tracking your streak.",
        systemImage: "wave.3.right"
    )
    .background(Theme.background)
}
