import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            VStack(spacing: 8) {
                Text(title)
                    .font(.custom("Avenir Next", size: 22, relativeTo: .title2).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.custom("Avenir Next", size: 15, relativeTo: .body))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .glassCard(cornerRadius: 26, tint: Color.black, isInteractive: false)
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
