import SwiftData
import SwiftUI

/// Lists surf workouts recorded elsewhere (Apple Watch, other apps) that Peak
/// has not written itself and that do not overlap an already-logged session, so
/// the user can turn them into Peak sessions. Self-contained and pushable — it
/// is opened from the Settings > Apple Health section.
struct HealthImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(SurfSession.sortedByDateDescending())
    private var sessions: [SurfSession]
    @Query(sort: \Spot.name)
    private var spots: [Spot]

    private enum LoadState {
        case loading
        case unavailable
        case failed
        case loaded([HealthKitLogic.WorkoutSummary])
    }

    @State private var state: LoadState = .loading
    @State private var importedWorkoutIDs: Set<UUID> = []
    @State private var importFeedback = 0
    /// Derived wave stats per workout, filled in lazily as rows appear. Absent
    /// means "not looked at yet"; a present-but-nil value means "looked, and this
    /// workout has no usable route" — the row then simply shows no estimate.
    @State private var routePreviews: [UUID: WaveStats?] = [:]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch state {
            case .loading:
                ProgressView("Checking Apple Health…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("health.import.loading")

            case .unavailable:
                EmptyStateView(
                    title: "Apple Health is off",
                    message: "Turn on Apple Health sync in Settings to import Apple Watch surf workouts.",
                    systemImage: "heart.text.square"
                )

            case .failed:
                VStack(spacing: 16) {
                    EmptyStateView(
                        title: "Couldn't read Health",
                        message: "Something went wrong reading your workouts.",
                        systemImage: "exclamationmark.triangle"
                    )
                    Button {
                        state = .loading
                        Task { await load() }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 4)
                    }
                    .glassButtonStyle(prominent: true)
                    .accessibilityIdentifier("health.import.retry")
                }

            case .loaded(let workouts):
                if workouts.isEmpty {
                    EmptyStateView(
                        title: "Nothing to import",
                        message: "Apple Watch surf workouts you haven't logged will appear here.",
                        systemImage: "applewatch"
                    )
                } else {
                    workoutList(workouts)
                }
            }
        }
        .navigationTitle("Import from Health")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: importFeedback)
        .task {
            await load()
        }
    }

    private func workoutList(_ workouts: [HealthKitLogic.WorkoutSummary]) -> some View {
        ScrollView {
            GlassContainer(spacing: 12) {
                // Lazy on purpose: each row's `.task` kicks off a route fetch +
                // wave analysis, so an eager VStack would start one per unlogged
                // workout the moment the screen appears — forty at once for a
                // long-time Watch user. Lazy rows analyze on scroll instead.
                LazyVStack(spacing: 12) {
                    ForEach(workouts) { workout in
                        workoutRow(workout)
                    }
                }
                .padding()
            }
        }
    }

    private func workoutRow(_ workout: HealthKitLogic.WorkoutSummary) -> some View {
        let draft = HealthKitLogic.draftValues(workoutStart: workout.start, workoutEnd: workout.end)
        let isImported = importedWorkoutIDs.contains(workout.id)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(timeRange(for: workout))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 6) {
                    Label(SessionDurationFormatter.string(from: draft.durationMinutes), systemImage: "timer")
                    Text("·")
                    Label(workout.sourceName, systemImage: "applewatch")
                }
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                waveStatsPreview(for: workout)
            }

            Spacer(minLength: 8)

            if isImported {
                Label("Imported", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.surfGreen)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Imported")
            } else {
                Button {
                    importWorkout(workout)
                } label: {
                    Text("Import")
                        .font(.subheadline.weight(.semibold))
                }
                .glassButtonStyle(prominent: true)
                .accessibilityIdentifier("health.import.button")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        .opacity(isImported ? 0.6 : 1)
        // `.contain`, not `.combine`: combine flattens the row into one static
        // element, which makes the Import button — the screen's only action —
        // unreachable to VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("health.import.row")
        .task(id: workout.id) {
            await loadRoutePreview(for: workout)
        }
    }

    /// Shows what Peak would derive from this workout's route *before* the user
    /// commits to importing it, so the decision is informed rather than a
    /// surprise. Silent when the workout has no route: most surf workouts
    /// recorded indoors or with GPS off simply have nothing to show, and an
    /// error there would be noise about a non-problem.
    @ViewBuilder
    private func waveStatsPreview(for workout: HealthKitLogic.WorkoutSummary) -> some View {
        if let stats = routePreviews[workout.id] ?? nil,
           let summary = WaveStatsFormatter.summary(
               waveCount: stats.waveCount,
               topSpeedKph: stats.topSpeedKph,
               longestRideSeconds: stats.longestRideSeconds
           ) {
            VStack(alignment: .leading, spacing: 2) {
                Label(summary, systemImage: "water.waves")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(WaveStatsFormatter.estimatePreviewCaption)
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
            .accessibilityIdentifier("health.import.waveStats")
        }
    }

    private func loadRoutePreview(for workout: HealthKitLogic.WorkoutSummary) async {
        // Route mining walks thousands of GPS fixes per workout. UI tests never
        // have a Health database to read, so skip the work entirely rather than
        // let every row spin up an analysis that can only return nothing.
        guard !TestingDefaults.isUITest else { return }
        guard routePreviews[workout.id] == nil else { return }
        let stats = await WaveStatsDeriver.stats(
            forWorkoutID: workout.id,
            provider: HealthKitService.shared
        )
        routePreviews[workout.id] = stats
    }

    private func timeRange(for workout: HealthKitLogic.WorkoutSummary) -> String {
        let start = workout.start.formatted(.dateTime.hour().minute())
        let end = workout.end.formatted(.dateTime.hour().minute())
        return "\(start) – \(end)"
    }

    private func importWorkout(_ workout: HealthKitLogic.WorkoutSummary) {
        // The workout came FROM Health (e.g. Apple Watch); create a matching
        // Peak session but do NOT write it back — that would duplicate the
        // original workout. Spot is guessed from the route start when a pin
        // is close enough; otherwise it stays nil for the surfer to set.
        Task {
            let stats: WaveStats?
            if let cached = routePreviews[workout.id] {
                stats = cached
            } else if TestingDefaults.isUITest {
                stats = nil
            } else {
                stats = await WaveStatsDeriver.stats(
                    forWorkoutID: workout.id,
                    provider: HealthKitService.shared
                )
            }
            var spot: Spot?
            if !TestingDefaults.isUITest,
               spots.contains(where: { $0.latitude != nil && $0.longitude != nil }) {
                let samples = await HealthKitService.shared.routeSamples(forWorkoutID: workout.id)
                spot = SpotProximity.nearest(to: samples, in: spots)
            }
            let session = HealthKitLogic.importedSession(workout: workout, stats: stats, spot: spot)
            modelContext.insert(session)
            importedWorkoutIDs.insert(workout.id)
            importFeedback += 1
        }
    }

    private func load() async {
        guard HealthKitService.isHealthDataAvailable, HealthKitService.shared.isEnabled else {
            state = .unavailable
            return
        }
        do {
            let workouts = try await HealthKitService.shared.fetchUnloggedSurfWorkouts(existingSessions: sessions)
            state = .loaded(workouts)
        } catch {
            state = .failed
        }
    }
}

#Preview {
    NavigationStack {
        HealthImportView()
            .modelContainer(PreviewData.container)
    }
}
