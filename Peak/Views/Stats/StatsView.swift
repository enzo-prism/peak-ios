import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot, \.gear, \.buddies]))
    private var sessions: [SurfSession]
    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(sort: \Gear.name) private var gear: [Gear]
    @Query(sort: \Buddy.name) private var buddies: [Buddy]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MonthlyGoalCalculator.metricKey) private var goalMetricRaw = MonthlyGoalMetric.sessions.rawValue
    @AppStorage(MonthlyGoalCalculator.targetKey) private var goalTarget = MonthlyGoalCalculator.defaultTarget
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
    @State private var cachedGearReports: [GearReport] = []
    @State private var cachedWaveRecords = WaveRecords()
    @State private var cachedWavesPerSession: [WavesPerMonth] = []
    @State private var cachedGoal = MonthlyGoalProgress(
        metric: .sessions,
        target: MonthlyGoalCalculator.defaultTarget,
        achieved: 0,
        fraction: 0,
        isMet: false
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
                            StatsMetricsRow(
                                yearSummary: yearSummary,
                                timeSummary: cachedTimeSummary,
                                longestStreak: cachedLongestStreak
                            )

                            // Goal above the heatmap: the goal is the thing the
                            // surfer can act on this month, the heatmap is the
                            // record of what already happened.
                            MonthlyGoalCard(progress: cachedGoal, monthName: currentMonthName)

                            if !cachedHeatmap.isEmpty {
                                ConsistencyHeatmapCard(cells: cachedHeatmap)
                            }

                            if !cachedMonthlySurfDays.isEmpty {
                                MonthlyBarsCard(data: cachedMonthlySurfDays)
                            }

                            if !cachedSpotMix.isEmpty {
                                SpotMixDonutCard(spots: cachedSpotMix)
                            }

                            ConditionsInsightsCard(
                                samples: cachedWaveSamples,
                                insight: cachedConditions
                            )

                            GearInsightsCard(reports: cachedGearReports)

                            // Suppressed entirely when no session carries wave
                            // stats — see WaveRecordsCard for why.
                            WaveRecordsCard(
                                records: cachedWaveRecords,
                                trend: cachedWavesPerSession
                            )

                            StatListSection(
                                title: "Top spots",
                                idPrefix: "spot",
                                items: summary.topSpots
                            ) { item in
                                spotsByKey[item.key].map { SpotDetailView(spot: $0) }
                            }
                            StatListSection(
                                title: "Most-used gear",
                                idPrefix: "gear",
                                items: summary.topGear
                            ) { item in
                                gearByKey[item.key].map { GearDetailView(gear: $0) }
                            }
                            StatListSection(
                                title: "Surf buddies",
                                idPrefix: "buddy",
                                items: summary.topBuddies
                            ) { item in
                                buddiesByKey[item.key].map { BuddyDetailView(buddy: $0) }
                            }
                        }
                        .padding()
                        .readableContentWidth()
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
        .onChange(of: goalMetricRaw) { _, _ in
            refreshGoal()
        }
        .onChange(of: goalTarget) { _, _ in
            refreshGoal()
        }
    }

    private var currentMonthName: String {
        Date().formatted(.dateTime.month(.wide))
    }

    private var goalMetric: MonthlyGoalMetric {
        MonthlyGoalMetric(rawValue: goalMetricRaw) ?? .sessions
    }

    private var summary: StatsSummary {
        cachedSummary
    }

    private var yearSummary: SurfYearSummary {
        cachedYearSummary
    }

    private var spotsByKey: [String: Spot] {
        Dictionary(spots.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var gearByKey: [String: Gear] {
        Dictionary(gear.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var buddiesByKey: [String: Buddy] {
        Dictionary(buddies.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
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
        // Boards only: a wetsuit's rating average says more about the season
        // than about the wetsuit.
        cachedGearReports = GearInsightsCalculator.reports(
            for: gear.filter { $0.kind == .board },
            sessions: sessions
        )
        cachedWaveRecords = WaveStatsCalculator.records(sessions: sessions)
        cachedWavesPerSession = WaveStatsCalculator.wavesPerSession(sessions: sessions)
        refreshGoal()
    }

    private func refreshGoal() {
        cachedGoal = MonthlyGoalCalculator.progress(
            sessions: sessions,
            metric: goalMetric,
            target: goalTarget
        )
    }
}

private struct StatListSection<Destination: View>: View {
    let title: String
    let idPrefix: String
    let items: [CountedItem]
    let destination: (CountedItem) -> Destination?

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
                            if let destination = destination(item) {
                                NavigationLink {
                                    destination
                                } label: {
                                    row(for: item, isLink: true)
                                }
                                .buttonStyle(.plain)
                            } else {
                                row(for: item, isLink: false)
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(for item: CountedItem, isLink: Bool) -> some View {
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
            if isLink {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        .contentShape(Rectangle())
        .accessibilityIdentifier("stats.row.\(idPrefix).\(item.key)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.name))
        .accessibilityValue(Text("\(item.count) session\(item.count == 1 ? "" : "s")"))
        .modifier(OpensDetailsHint(isLink: isLink))
    }
}

/// Adds an "Opens details" VoiceOver hint only when the row actually links out,
/// so plain (unresolved) rows stay quiet.
private struct OpensDetailsHint: ViewModifier {
    let isLink: Bool

    func body(content: Content) -> some View {
        if isLink {
            content.accessibilityHint(Text("Opens details"))
        } else {
            content
        }
    }
}

#Preview {
    StatsView()
        .modelContainer(PreviewData.container)
}
