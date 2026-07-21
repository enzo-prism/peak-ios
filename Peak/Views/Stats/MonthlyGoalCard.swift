import SwiftUI

/// This month's goal, ring first. Goals lead and streaks follow on purpose:
/// surfing is condition-gated, and a rigid streak turns a flat week into a
/// failure the surfer can't do anything about.
struct MonthlyGoalCard: View {
    let progress: MonthlyGoalProgress
    let monthName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ringValue: CGFloat {
        // Reduce Motion still gets the final value, it just arrives without the
        // sweep (the ring is drawn straight to its resting position).
        CGFloat(progress.fraction)
    }

    var body: some View {
        HStack(spacing: 16) {
            ring

            VStack(alignment: .leading, spacing: 4) {
                Text("\(monthName) goal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(progress.summaryLabel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.8)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassTint, isInteractive: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(monthName) goal"))
        .accessibilityValue(Text("\(progress.summaryLabel). \(statusLine)"))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.glassDimTint, lineWidth: 10)
            Circle()
                .trim(from: 0, to: ringValue)
                .stroke(
                    progress.isMet ? Theme.surfGreen : Theme.textPrimary,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: ringValue)

            Text(percentLabel)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 68, height: 68)
        .accessibilityHidden(true)
    }

    private var percentLabel: String {
        guard progress.isActive else { return "—" }
        return "\(Int((progress.fraction * 100).rounded()))%"
    }

    private var statusLine: String {
        guard progress.isActive else {
            return "Set a monthly goal in Settings."
        }
        if progress.isMet {
            let extra = progress.achieved - Double(progress.target)
            return extra > 0 ? "Goal met, and then some." : "Goal met."
        }
        switch progress.metric {
        case .sessions:
            let remaining = Int(progress.remaining.rounded(.up))
            return "\(remaining) more session\(remaining == 1 ? "" : "s") to go."
        case .hours:
            return "\(String(format: "%.1f", progress.remaining)) more hours to go."
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        MonthlyGoalCard(
            progress: MonthlyGoalProgress(metric: .sessions, target: 8, achieved: 0, fraction: 0, isMet: false),
            monthName: "July"
        )
        MonthlyGoalCard(
            progress: MonthlyGoalProgress(metric: .sessions, target: 8, achieved: 5, fraction: 0.625, isMet: false),
            monthName: "July"
        )
        MonthlyGoalCard(
            progress: MonthlyGoalProgress(metric: .hours, target: 10, achieved: 14, fraction: 1, isMet: true),
            monthName: "July"
        )
    }
    .padding()
    .background(Theme.background)
}
