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
        totalSessions: 0,
        monthlyCounts: [],
        currentWeekStreak: 0
    )
    @State private var cachedTimeSummary = SurfTimeSummary(
        totalMinutes: 0,
        averageMinutes: nil,
        sessionsWithDuration: 0
    )
    @State private var cachedLongestStreak = 0
    @State private var cachedHeatmap: [SessionHeatmapCell] = []
    @State private var cachedSpotMix: [CountedItem] = []
    @State private var cachedWaveSamples: [WaveRatingSample] = []
    @State private var cachedConditions: ConditionsInsight?
    @State private var cachedMonthlySurfDays: [MonthlyCount] = []

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
                            StatsMetricsRow(
                                yearSummary: yearSummary,
                                timeSummary: cachedTimeSummary,
                                longestStreak: cachedLongestStreak
                            )

                            if !cachedHeatmap.isEmpty {
                                ConsistencyHeatmapCard(cells: cachedHeatmap)
                            }

                            if !cachedMonthlySurfDays.isEmpty {
                                MonthlyBarsCard(data: cachedMonthlySurfDays)
                            }

                            if !cachedSpotMix.isEmpty {
                                SpotMixDonutCard(spots: cachedSpotMix)
                            }

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

    private func refreshSummaries() {
        cachedSummary = StatsCalculator.summarize(sessions: sessions)
        cachedYearSummary = StatsCalculator.surfDaysThisYear(sessions: sessions)
        cachedTimeSummary = StatsCalculator.timeInWater(sessions: sessions)
        cachedLongestStreak = StatsCalculator.longestWeekStreak(sessions: sessions)
        cachedHeatmap = StatsCalculator.sessionHeatmap(sessions: sessions)
        cachedSpotMix = StatsCalculator.spotMix(sessions: sessions)
        cachedWaveSamples = StatsCalculator.waveHeightRatingSamples(sessions: sessions)
        cachedConditions = StatsCalculator.bestConditions(sessions: sessions)
        cachedMonthlySurfDays = StatsCalculator.monthlySurfDays(sessions: sessions)
    }
}

private struct StatListSection: View {
    let title: String
    let items: [CountedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            if items.isEmpty {
                Text("Not enough data yet")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            } else {
                GlassContainer(spacing: 10) {
                    VStack(spacing: 8) {
                        ForEach(items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    if let detail = item.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(Theme.textMuted)
                                    }
                                }
                                Spacer()
                                Text("\(item.count)")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding(12)
                            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
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
