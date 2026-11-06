import Charts
import SwiftData
import SwiftUI

struct QuiverAdvisorView: View {
    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(sort: \Gear.name) private var gear: [Gear]
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot, \.gear])) private var sessions: [SurfSession]
    @State private var spotKey: String

    init(initialSpotKey: String = "") {
        _spotKey = State(initialValue: initialSpotKey)
    }
    @State private var height: WaveHeight?
    @State private var period: SwellPeriodBand?

    private var spot: Spot? { spots.first { $0.key == spotKey } ?? spots.first }
    private var report: QuiverAdvisor.Report? {
        spot.map { QuiverAdvisor.compare(spot: $0, height: height, period: period, gear: gear, sessions: sessions) }
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
                    ContentUnavailableView("Not enough comparable data yet", systemImage: "surfboard",
                        description: Text("Log and rate at least three single-board sessions per board at this spot. Unknown conditions are excluded when a filter is selected."))
                }
            }
        }
        .navigationTitle("Compare Boards")
        .onAppear { if spotKey.isEmpty { spotKey = spots.first?.key ?? "" } }
        .accessibilityIdentifier("quiver.advisor")
    }
}
