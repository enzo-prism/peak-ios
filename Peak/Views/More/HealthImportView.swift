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

    private enum LoadState {
        case loading
        case unavailable
        case failed
        case loaded([HealthKitLogic.WorkoutSummary])
    }

    @State private var state: LoadState = .loading
    @State private var importedWorkoutIDs: Set<UUID> = []
    @State private var importFeedback = 0

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
                EmptyStateView(
                    title: "Couldn't read Health",
                    message: "Something went wrong reading your workouts. Pull to refresh or try again later.",
                    systemImage: "exclamationmark.triangle"
                )

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
                VStack(spacing: 12) {
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
                    importWorkout(workout, draft: draft)
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("health.import.row")
    }

    private func timeRange(for workout: HealthKitLogic.WorkoutSummary) -> String {
        let start = workout.start.formatted(.dateTime.hour().minute())
        let end = workout.end.formatted(.dateTime.hour().minute())
        return "\(start) – \(end)"
    }

    private func importWorkout(_ workout: HealthKitLogic.WorkoutSummary, draft: HealthKitLogic.SessionDraftValues) {
        // The workout came FROM Health (e.g. Apple Watch); create a matching
        // Peak session but do NOT write it back — that would duplicate the
        // original workout.
        let session = SurfSession(
            date: draft.date,
            spot: nil,
            durationMinutes: draft.durationMinutes,
            notes: "Imported from Apple Health"
        )
        modelContext.insert(session)
        importedWorkoutIDs.insert(workout.id)
        importFeedback += 1
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
