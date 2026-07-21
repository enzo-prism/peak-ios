import SwiftUI

/// This month, summed up.
///
/// The card is a plain-stats card first: the figure line and the highlight rows
/// are aggregates and render on every device Peak supports. When the phone can
/// run Apple's on-device model, a sentence of connective prose is layered on top
/// — it adds phrasing, never facts. Nothing is lost when it is absent, which is
/// why the whole AI half simply does not appear rather than showing a placeholder
/// or an explanation nobody asked for.
///
/// No `.accessibilityIdentifier` anywhere in here: the card lives inside the
/// Stats `ScrollView`, and identifiers on scrolled content clobber each other.
/// The identifier is on the ScrollView itself.
struct MonthlyRecapCard: View {
    let recap: MonthlyRecap

    private var facts: MonthlyRecapFacts { recap.facts }

    var body: some View {
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(facts.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)

                Text(facts.plainFigures)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let narrative = recap.narrative {
                    Text(narrative)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !facts.plainHighlights.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(facts.plainHighlights, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let suggestion = recap.suggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if recap.isModelWritten {
                    OnDeviceInsightFootnote()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassTint, isInteractive: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(facts.title))
            .accessibilityValue(Text(accessibilityValue))
        }
    }

    /// VoiceOver gets the whole card as one utterance, figures first, because
    /// hearing six fragments in a row is how you lose the shape of a month. The
    /// privacy line is part of it: where the words came from is exactly the sort
    /// of thing a screen-reader user should not have to take on trust.
    private var accessibilityValue: String {
        var parts = [facts.accessibilitySummary]
        if let narrative = recap.narrative {
            parts.append(narrative)
        }
        if let suggestion = recap.suggestion {
            parts.append(suggestion)
        }
        if recap.isModelWritten {
            parts.append(OnDeviceInsightFootnote.text)
        }
        return parts.joined(separator: ". ")
    }
}

/// The one line of privacy copy the AI surfaces share.
///
/// It is a plain statement of what the code does — `FoundationModelsInsights.swift`
/// has no networking of any kind — and it is deliberately flat. "Never leaves
/// your iPhone" is the useful fact; anything more would be advertising.
struct OnDeviceInsightFootnote: View {
    static let text = "Written on this iPhone. Your logbook never leaves it."

    var body: some View {
        HStack(spacing: 6) {
            // "sparkles" is already this app's insight glyph (conditions card,
            // recap prompt). `apple.intelligence` would need its own availability
            // gate for an iOS 17 deployment target and buys nothing.
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            Text(Self.text)
                .font(.caption2)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

#Preview {
    MonthlyRecapCard(
        recap: MonthlyRecap(
            facts: MonthlyRecapFacts(
                monthName: "July",
                year: 2026,
                sessionCount: 9,
                surfDays: 8,
                totalMinutes: 680,
                averageRating: 4.2,
                topSpot: InsightsNamedCount(name: "Ocean Beach", count: 5),
                distinctSpotCount: 3,
                topBoard: InsightsBoardFact(
                    name: "6'2\" Fish",
                    sessionCount: 6,
                    averageRating: 4.5,
                    conditionsPhrase: "short-period waist-high"
                ),
                previousMonthSessionCount: 6,
                hasEarlierHistory: true,
                previousBestMonthName: "March"
            ),
            narrative: "You got in the water more than you have in a while, and it paid off.",
            suggestion: "Keep favouring the days that suited your fish."
        )
    )
    .padding()
}
