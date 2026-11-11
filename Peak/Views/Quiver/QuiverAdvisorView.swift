import Charts
import SwiftData
import SwiftUI

struct QuiverAdvisorView: View {
    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(sort: \Gear.name) private var gear: [Gear]
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot, \.gear])) private var sessions: [SurfSession]
    @State private var spotKey: String

    init(initialSpotKey: String = "", initialHeight: WaveHeight? = nil, initialPeriod: SwellPeriodBand? = nil) {
        _spotKey = State(initialValue: initialSpotKey)
        _height = State(initialValue: initialHeight)
        _period = State(initialValue: initialPeriod)
    }
    @State private var height: WaveHeight?
    @State private var period: SwellPeriodBand?

    private var spot: Spot? { spots.first { $0.key == spotKey } ?? spots.first }
    @State private var report: QuiverAdvisor.Report?

    private var evidenceStamp: Int {
        var hasher = Hasher()
        hasher.combine(SessionQueryStamp.make(sessions))
        for board in gear { hasher.combine(board.key); hasher.combine(board.isArchived); hasher.combine(board.name) }
        return hasher.finalize()
    }

    var body: some View {
        List {
            Section {
                Text("Compare boards at the same spot, in similar conditions. Ratings describe your experience; they do not prove a board caused a better surf.")
                    .font(.subheadline)
                Picker("Spot", selection: $spotKey) {
                    ForEach(spots) { Text($0.name).tag($0.key) }
                }
                Picker("Wave size", selection: $height) {
                    Text("Any logged size").tag(nil as WaveHeight?)
                    ForEach(WaveHeight.allCases) { Text($0.label).tag(Optional($0)) }
                }
                Picker("Swell period", selection: $period) {
                    Text("Any logged period").tag(nil as SwellPeriodBand?)
                    ForEach(SwellPeriodBand.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
                if height == nil || period == nil {
                    Text("Mixed conditions: choose wave size and swell period to narrow this comparison.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let report, !report.comparisons.isEmpty {
                Section("Your comparison") {
                    if let suggested = report.suggestedBoard {
                        Label("\(suggested.name) rated higher in this cohort", systemImage: "surfboard")
                    } else {
                        Text("No clear board preference yet")
                            .font(.headline)
                    }
                    Chart(report.comparisons) { comparison in
                        BarMark(x: .value("Average rating", comparison.averageRating),
                                y: .value("Board", comparison.gear.name))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityLabel(comparison.gear.name)
                        .accessibilityValue("\(comparison.averageRating.formatted(.number.precision(.fractionLength(1)))) stars from \(comparison.count) sessions")
                    }
                    .chartXScale(domain: 0...5)
                    .frame(height: CGFloat(max(100, report.comparisons.count * 48)))
                    Text("At least three rated, single-board sessions per comparison. A suggestion needs a meaningful separation after accounting for variability.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(report.comparisons) { comparison in
                    Section("\(comparison.gear.name) · \(comparison.count) sessions") {
                        Text("\(comparison.averageRating.formatted(.number.precision(.fractionLength(1)))) / 5 average rating")
                        ForEach(comparison.sessions) { session in
                            Button {
                                PeakNavigationCoordinator.shared.handle(.session(id: SessionIntentQueries.identifier(for: session)))
                            } label: {
                                Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(session.rating) stars")
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("Not enough comparable data yet").font(.headline)
                    Text("Each board needs three rated, single-board surfs at this spot with the selected conditions. Your progress and recent evidence are below.")
                    if spots.isEmpty { Text("Add a spot when logging your first surf.") }
                    if gear.filter({ $0.kind == .board && !$0.isArchived }).isEmpty {
                        NavigationLink("Add your first board") { GearEditorView(mode: .new) }
                    }
                }
            }
            if let report {
                ForEach(report.coverage) { coverage in
                    Section(coverage.gear.name) {
                        Text(coverage.qualifyingCount < 3
                             ? "\(coverage.qualifyingCount) of 3 qualifying surfs"
                             : "\(coverage.qualifyingCount) qualifying surfs")
                            .font(.headline)
                        if coverage.sessions.isEmpty {
                            Text("Select this board when you next log a surf at this spot.")
                        }
                        ForEach(Array(coverage.sessions.prefix(5))) { session in
                            Button {
                                PeakNavigationCoordinator.shared.handle(.session(id: SessionIntentQueries.identifier(for: session)))
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                    Text(evidenceLabel(session)).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Compare Boards")
        .onAppear {
            if !spots.contains(where: { $0.key == spotKey }) {
                spotKey = QuiverAdvisor.preferredSpot(spots: spots, sessions: sessions)?.key ?? ""
            }
            refresh()
        }
        .onChange(of: evidenceStamp) { _, _ in refresh() }
        .onChange(of: spotKey) { _, _ in refresh() }
        .onChange(of: height) { _, _ in refresh() }
        .onChange(of: period) { _, _ in refresh() }
        .accessibilityIdentifier("quiver.advisor")
    }

    private func refresh() {
        report = spot.map { QuiverAdvisor.compare(spot: $0, height: height, period: period, gear: gear, sessions: sessions) }
    }

    private func evidenceLabel(_ session: SurfSession) -> String {
        if !(1...5).contains(session.rating) { return "Add a rating to include this surf" }
        if session.gear.filter({ $0.kind == .board }).count != 1 { return "Multiple boards: rating cannot be assigned to one board" }
        if let height, GearInsightsCalculator.waveBand(for: session) != height {
            return GearInsightsCalculator.waveBand(for: session) == nil ? "Add wave size to check this filter" : "Different wave size"
        }
        if let period, session.swellWavePeriodSeconds.map(SwellPeriodBand.band(forSeconds:)) != period {
            return session.swellWavePeriodSeconds == nil ? "Add swell period to check this filter" : "Different swell period"
        }
        return "Qualifies · \(session.rating) stars"
    }
}
