import SwiftUI
import SwiftData

/// The on-demand year recap. Everything here is derived from existing session
/// fields, so it works on a library of one session as well as one of hundreds —
/// sparse years simply render fewer rows rather than a wall of dashes.
struct YearInReviewView: View {
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot, \.gear, \.media]))
    private var sessions: [SurfSession]

    /// December's Log-tab card jumps straight to that year; More opens on the
    /// most recent year with sessions.
    var initialYear: Int?

    @State private var selectedYear: Int?
    @State private var review: YearInReview?
    @State private var highlights: [SessionMedia] = []
    @State private var shareContent: RecapShareContent?
    /// The model's version of the paragraph. `nil` means the plain one renders —
    /// same facts, flatter prose — which is what every device without Apple
    /// Intelligence sees.
    @State private var narrative: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if availableYears.isEmpty {
                EmptyStateView(
                    title: "No year to review yet",
                    message: "Log a session and your recap starts building itself.",
                    systemImage: "sparkles"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if availableYears.count > 1 {
                            yearPicker
                        }

                        if let review {
                            headlineCard(review)
                            narrativeCard(review)
                            metricsSection(review)
                            if !review.waveHeightDistribution.isEmpty {
                                waveDistributionSection(review)
                            }
                            if !highlights.isEmpty {
                                highlightsSection
                            }
                        }
                    }
                    .padding()
                    .readableContentWidth()
                }
                .accessibilityIdentifier("recap.scroll")
            }
        }
        .navigationTitle("Year in Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                shareToolbarButton
            }
        }
        .onAppear {
            if selectedYear == nil {
                selectedYear = initialYear.flatMap { availableYears.contains($0) ? $0 : nil }
                    ?? availableYears.first
            }
            refresh()
        }
        .onChange(of: selectedYear) { _, _ in
            refresh()
        }
        .onChange(of: sessions) { _, _ in
            refresh()
        }
        .task(id: review) {
            await prepareShareContent()
        }
        .task(id: review) {
            await refreshNarrative()
        }
    }

    private var availableYears: [Int] {
        YearInReviewCalculator.availableYears(sessions: sessions)
    }

    private var yearPicker: some View {
        Picker("Year", selection: $selectedYear) {
            ForEach(availableYears, id: \.self) { year in
                Text(String(year)).tag(Int?.some(year))
            }
        }
        .pickerStyle(.segmented)
    }

    private func headlineCard(_ review: YearInReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(review.year))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(headline(review))
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let spot = review.topSpot {
                Text("Most days at \(spot.name) (\(spot.count))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassTint, isInteractive: false)
    }

    /// The year in a paragraph. Always present, because the plain rendering is
    /// built from the same aggregates the metric grid below shows; the model only
    /// ever changes how it reads, never what it says.
    private func narrativeCard(_ review: YearInReview) -> some View {
        let facts = InsightsEngine.yearFacts(review: review)
        let text = narrative ?? facts.plainNarrative
        return VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if narrative != nil {
                OnDeviceInsightFootnote()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Year summary"))
        // The privacy line rides along in the value: where the words came from
        // is not something a screen-reader user should have to take on trust.
        .accessibilityValue(Text(narrative == nil ? text : "\(text) \(OnDeviceInsightFootnote.text)"))
    }

    private func headline(_ review: YearInReview) -> String {
        let sessions = "\(review.sessionCount) session\(review.sessionCount == 1 ? "" : "s")"
        guard review.totalMinutes > 0 else { return sessions }
        return "\(sessions), \(StatsFormat.duration(review.totalMinutes)) in the water"
    }

    private func metricsSection(_ review: YearInReview) -> some View {
        DetailMetricGrid {
            MetricCardView(title: "Sessions", value: "\(review.sessionCount)")
            MetricCardView(title: "Surf days", value: "\(review.surfDays)")
            MetricCardView(
                title: "Hours",
                value: review.totalMinutes > 0 ? StatsFormat.duration(review.totalMinutes) : "-"
            )
            MetricCardView(
                title: "Best month",
                value: review.bestMonth.map { $0.month.formatted(.dateTime.month(.wide)) } ?? "-",
                subtitle: review.bestMonth.map { "\($0.count) session\($0.count == 1 ? "" : "s")" }
            )
            MetricCardView(
                title: "Longest streak",
                value: review.longestWeekStreak > 0 ? StatsFormat.spokenWeeks(review.longestWeekStreak) : "-"
            )
            MetricCardView(
                title: "Avg rating",
                value: review.averageRating.map { "\(StatsFormat.rating($0))★" } ?? "-"
            )
        }
    }

    private func waveDistributionSection(_ review: YearInReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wave heights")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(spacing: 10) {
                ForEach(review.waveHeightDistribution) { slice in
                    distributionRow(slice, total: review.waveHeightDistribution.map(\.count).max() ?? 1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        }
    }

    private func distributionRow(_ slice: YearInReviewWaveSlice, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(slice.height.label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(slice.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            GeometryReader { geometry in
                Capsule()
                    .fill(Theme.textPrimary.opacity(0.7))
                    .frame(width: max(geometry.size.width * barRatio(slice.count, total: total), 3))
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(slice.height.label))
        .accessibilityValue(Text("\(slice.count) session\(slice.count == 1 ? "" : "s")"))
    }

    private func barRatio(_ count: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlights")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                spacing: 8
            ) {
                ForEach(highlights) { media in
                    SessionMediaThumbnailView(
                        imageData: media.thumbnailData ?? media.photoData,
                        isVideo: media.kind == .video,
                        crop: media.cropRect
                    )
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var shareToolbarButton: some View {
        if let shareContent {
            ShareLink(
                item: shareContent,
                preview: SharePreview(shareContent.caption, image: Image(uiImage: shareContent.image))
            ) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share year in review")
            .accessibilityIdentifier("recap.share")
        } else {
            Button {} label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(true)
            .accessibilityLabel("Share year in review")
            .accessibilityIdentifier("recap.share")
        }
    }

    private func refresh() {
        guard let year = selectedYear else {
            review = nil
            highlights = []
            return
        }
        review = YearInReviewCalculator.summary(sessions: sessions, year: year)
        highlights = YearInReviewCalculator.mediaHighlights(sessions: sessions, year: year)
    }

    /// Same contract as the Stats card: silent on every failure, and the
    /// paragraph on screen is already correct before this runs.
    private func refreshNarrative() async {
        narrative = nil
        guard let review, !review.isEmpty else { return }
        guard let generator = InsightsModel.makeGenerator() else { return }
        let facts = InsightsEngine.yearFacts(review: review)
        let result = await InsightsEngine.yearNarrative(facts: facts, generator: generator)
        guard !Task.isCancelled, self.review == review else { return }
        narrative = result
    }

    private func prepareShareContent() async {
        guard let review else {
            shareContent = nil
            return
        }
        shareContent = await RecapShareCardRenderer.makeContent(review: review, media: highlights)
    }
}

/// The December nudge on the Log tab.
struct YearInReviewPromptCard: View {
    let year: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 56, height: 56)
                .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: false)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your \(String(year)) in review")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Sessions, hours, and the year's highlights.")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassTint, isInteractive: true)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your \(String(year)) in review"))
        .accessibilityHint(Text("Opens your year recap"))
    }
}

#Preview {
    NavigationStack {
        YearInReviewView()
            .modelContainer(PreviewData.container)
    }
}
