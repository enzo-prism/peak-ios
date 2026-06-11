import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot, \.gear, \.buddies]))
    private var sessions: [SurfSession]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showContent = false
    @State private var cachedSummary = StatsSummary(
        totalSessions: 0,
        averageRating: 0,
        topSpots: [],
        topGear: [],
        topBuddies: []
    )
    @State private var cachedYearSummary = SurfYearSummary(
        year: Calendar.current.component(.year, from: Date()),
        totalDays: 0,
        monthlyCounts: [],
        currentWeekStreak: 0
    )

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if sessions.isEmpty {
                    EmptyStateView(
                        title: "No stats yet",
                        message: "Log sessions to see your totals and patterns.",
                        systemImage: "chart.bar.xaxis"
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            surfDaysSection
                            summaryCards

                            StatListSection(title: "Top spots", items: summary.topSpots)
                            StatListSection(title: "Most-used gear", items: summary.topGear)
                            StatListSection(title: "Surf buddies", items: summary.topBuddies)
                        }
                        .padding()
                        .opacity(showContent || reduceMotion ? 1 : 0)
                        .offset(y: showContent || reduceMotion ? 0 : 12)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: showContent)
                    }
                    .onAppear {
                        showContent = true
                    }
                }
            }
            .navigationTitle("Stats")
        }
        .onAppear {
            refreshSummaries()
        }
        .onChange(of: sessions) { _, _ in
            refreshSummaries()
        }
    }

    private var summary: StatsSummary {
        cachedSummary
    }

    private var yearSummary: SurfYearSummary {
        cachedYearSummary
    }

    private var summaryCards: some View {
        GlassContainer(spacing: 12) {
            HStack(spacing: 12) {
                StatCardView(title: "Sessions", value: "\(summary.totalSessions)", subtitle: "All time")
                StatCardView(title: "Avg rating", value: averageRatingLabel, subtitle: "Rated sessions")
            }
        }
    }

    private var surfDaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricCardView(title: "Week Streak", value: "\(yearSummary.currentWeekStreak)", subtitle: "Weeks")

            UsageChartCard(
                title: "Monthly surf days",
                data: yearSummary.monthlyCounts,
                valueLabel: "Surf Days"
            )
        }
    }

    private var averageRatingLabel: String {
        if summary.averageRating == 0 {
            return "-"
        }
        return String(format: "%.1f", summary.averageRating)
    }

    private func refreshSummaries() {
        cachedSummary = StatsCalculator.summarize(sessions: sessions)
        cachedYearSummary = StatsCalculator.surfDaysThisYear(sessions: sessions)
    }
}

private struct StatListSection: View {
    let title: String
    let items: [CountedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("Avenir Next", size: 18, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            if items.isEmpty {
                Text("Not enough data yet")
                    .font(.custom("Avenir Next", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textMuted)
            } else {
                GlassContainer(spacing: 10) {
                    VStack(spacing: 8) {
                        ForEach(items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.custom("Avenir Next", size: 15, relativeTo: .subheadline).weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    if let detail = item.detail {
                                        Text(detail)
                                            .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                                            .foregroundStyle(Theme.textMuted)
                                    }
                                }
                                Spacer()
                                Text("\(item.count)")
                                    .font(.custom("Avenir Next", size: 18, relativeTo: .headline).weight(.bold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding(12)
                            .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    StatsView()
        .modelContainer(PreviewData.container)
}
