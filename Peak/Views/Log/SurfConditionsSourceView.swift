import SwiftUI

struct SurfConditionsSourceDetails: Identifiable {
    let id = UUID()
    let source: String
    let fetchedAt: Date?
    let spotName: String?
    let latitude: Double?
    let longitude: Double?
    let sessionStart: Date
    let durationMinutes: Int
}

struct SurfConditionsSourceView: View {
    @Environment(\.dismiss) private var dismiss
    let details: SurfConditionsSourceDetails

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    GlassContainer(spacing: 16) {
                        VStack(alignment: .leading, spacing: 16) {
                            sourceSection
                            locationSection
                            timeSection
                            footnote
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Conditions Source")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Source")
            detailRow(title: "Provider", value: details.source)
            detailRow(title: "Fetched", value: fetchedAtLabel)
        }
        .padding(16)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Location")
            detailRow(title: "Spot", value: spotLabel)
            detailRow(title: "Coordinates", value: coordinatesLabel)
        }
        .padding(16)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Time")
            detailRow(title: "Session date", value: sessionDateLabel)
            detailRow(title: "Start time", value: startTimeLabel)
            detailRow(title: "End time", value: endTimeLabel)
            detailRow(title: "Duration", value: durationLabel)
        }
        .padding(16)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    private var footnote: some View {
        Text("Times shown in your local time zone. Auto-fill averages data across the session window. Tide is modelled relative to mean sea level, so it is reliable for direction — rising or falling — but not for exact heights or turn times.")
            .font(.caption)
            .foregroundStyle(Theme.textMuted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    private var fetchedAtLabel: String {
        details.fetchedAt?.formatted(.dateTime.month(.abbreviated).day().hour().minute()) ?? "Unknown"
    }

    private var spotLabel: String {
        if let trimmed = details.spotName?.trimmedNonEmpty {
            return trimmed
        }
        return "Unknown spot"
    }

    private var coordinatesLabel: String {
        guard let latitude = details.latitude, let longitude = details.longitude else {
            return "Not available"
        }
        return "\(coordinateLabel(latitude, positive: "N", negative: "S")), \(coordinateLabel(longitude, positive: "E", negative: "W"))"
    }

    private var sessionDateLabel: String {
        details.sessionStart.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    private var startTimeLabel: String {
        details.sessionStart.formatted(.dateTime.hour().minute())
    }

    private var endTimeLabel: String {
        sessionEnd.formatted(.dateTime.hour().minute())
    }

    private var durationLabel: String {
        SessionDurationFormatter.string(from: details.durationMinutes)
    }

    private var sessionEnd: Date {
        details.sessionStart.addingTimeInterval(Double(details.durationMinutes) * 60)
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        DetailInfoRow(title: title, value: value)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textMuted)
    }

    private func coordinateLabel(_ value: Double, positive: String, negative: String) -> String {
        let direction = value >= 0 ? positive : negative
        return String(format: "%.4f° %@", abs(value), direction)
    }
}

#Preview {
    SurfConditionsSourceView(details: SurfConditionsSourceDetails(
        source: "Open-Meteo",
        fetchedAt: Date(),
        spotName: "Trestles",
        latitude: 33.3866,
        longitude: -117.5934,
        sessionStart: Date(),
        durationMinutes: 90
    ))
    .background(Theme.background)
}
