import SwiftData
import SwiftUI

/// Station predictions are a separate MLLW-referenced view. They never replace
/// or train the MSL-referenced model values in a session or WindowScorer.
struct TideStationCard: View {
    let spot: Spot
    @Environment(\.modelContext) private var modelContext
    @State private var station: TideService.Station?
    @State private var extremes: [TideService.TideExtreme] = []
    @State private var isWorking = false
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    @State private var checkedAt: Date?

    var body: some View {
        DisclosureGroup("Station Tide Predictions") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Optional NOAA CO-OPS predictions. A nearby gauge may not represent this break. Station heights use MLLW; model heights above use mean sea level.")
                    .font(.caption).foregroundStyle(Theme.textMuted)
                if let station {
                    Text(station.name).font(.subheadline.weight(.semibold))
                    if extremes.isEmpty {
                        Text("Confirm this station is appropriate for your spot before using its predictions.").font(.caption)
                        Button("Use This Station") { fetchPredictions(station) }
                            .disabled(isWorking)
                    }
                    ForEach(extremes, id: \.date) { tide in
                        Text("\(tide.isHigh ? "High" : "Low") · \(tide.date.formatted(date: .abbreviated, time: .shortened)) · \(SurfConditionsFormatter.meters(tide.heightMeters)) MLLW")
                            .font(.subheadline)
                    }
                    if let checkedAt {
                        Text("NOAA CO-OPS · checked \(checkedAt.formatted(date: .omitted, time: .shortened)). Predictions, not observed water levels.")
                            .font(.caption).foregroundStyle(Theme.textMuted)
                    }
                }
                if let message { Text(message).font(.caption) }
                if isWorking { ProgressView() }
                Button(station == nil ? "Find Nearby NOAA Station" : "Find Station Again") { findStation() }
                    .disabled(isWorking || TestingDefaults.isRunningTests)
                    .frame(minHeight: 44)
            }
        }
        .onDisappear { task?.cancel() }
    }

    private func findStation() {
        guard !isWorking, !TestingDefaults.isRunningTests, let lat = spot.latitude, let lon = spot.longitude else { return }
        task?.cancel(); isWorking = true; message = nil; extremes = []; checkedAt = nil
        task = Task {
            defer { isWorking = false }
            do {
                let nearest = try await TideService.nearestStation(latitude: lat, longitude: lon)
                try Task.checkCancellation()
                station = nearest
                if nearest == nil { message = "No nearby NOAA station was found. The model conditions remain available." }
            } catch is CancellationError {} catch {
                message = "Station information is unavailable. The model conditions remain available."
            }
        }
    }

    private func fetchPredictions(_ station: TideService.Station) {
        guard !isWorking, !TestingDefaults.isRunningTests else { return }
        task?.cancel(); isWorking = true
        task = Task {
            defer { isWorking = false }
            do {
                let now = Date()
                let values = try await TideService.predictions(stationId: station.id, start: now, end: now.addingTimeInterval(36 * 3600))
                try Task.checkCancellation()
                extremes = values.filter { $0.date >= now }.sorted { $0.date < $1.date }
                checkedAt = now
                if extremes.isEmpty { message = "No upcoming high/low predictions were returned." }
                // This explicit confirmation, not nearest-distance guessing,
                // authorizes associating the station with this spot.
                let previous = spot.tideStationId
                spot.tideStationId = station.id
                do { try modelContext.save() }
                catch { spot.tideStationId = previous; message = "Predictions loaded, but the station preference could not be saved." }
            } catch is CancellationError {} catch {
                message = "Tide predictions are unavailable. The model conditions remain available."
            }
        }
    }
}
