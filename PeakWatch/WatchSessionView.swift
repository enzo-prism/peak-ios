import SwiftUI

/// The whole watch app: one screen that starts a session, shows it running, and
/// ends it.
///
/// Kept to a single screen on purpose. Once the surfer is in the water, Water
/// Lock has blanked the touch screen and the only interaction available is a
/// crown twist to unlock followed by one deliberate tap. Anything that needs
/// navigating to would never be reached.
struct WatchSessionView: View {
    @EnvironmentObject private var controller: WatchWorkoutController
    @State private var confirmDiscard = false

    var body: some View {
        Group {
            switch controller.state {
            case .idle:
                startScreen
            case .running, .paused:
                activeScreen
            case .ended:
                endedScreen
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Idle

    private var startScreen: some View {
        VStack(spacing: 12) {
            Text("Peak")
                .font(.title3.weight(.semibold))
            Text("Track a surf")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task { await controller.start() }
            } label: {
                Label("Start", systemImage: "water.waves")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .disabled(controller.isStarting)

            if let error = controller.startupError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Running / paused

    private var activeScreen: some View {
        VStack(spacing: 8) {
            elapsedLabel

            HStack(spacing: 12) {
                metric(
                    value: controller.heartRate.map { String(Int($0.rounded())) } ?? "--",
                    unit: "BPM",
                    systemImage: "heart.fill",
                    tint: .pink
                )
                metric(
                    value: distanceText,
                    unit: "KM",
                    systemImage: "figure.pool.swim",
                    tint: .teal
                )
            }

            HStack(spacing: 8) {
                Button {
                    if controller.state == .running {
                        controller.pause()
                    } else {
                        controller.resume()
                    }
                } label: {
                    Image(systemName: controller.state == .running ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.orange)

                Button {
                    Task { await controller.end() }
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.red)
            }
            .buttonStyle(.bordered)

            if controller.isMirroring {
                // Informational only. Mirroring failing is invisible by design;
                // this just confirms the phone is showing the Live Activity.
                Label("On iPhone", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The live clock.
    ///
    /// `Text(timerInterval:)` is used while running so watchOS ticks the digits
    /// itself — a `Timer` in the app would be throttled the moment the wrist
    /// drops, which is most of a surf session. When paused the value is frozen
    /// and rendered as plain text, since there is nothing to count.
    @ViewBuilder
    private var elapsedLabel: some View {
        if controller.state == .running, let since = controller.timeline.timerReferenceDate {
            Text(
                timerInterval: since...Date.distantFuture,
                pauseTime: nil,
                countsDown: false
            )
            .font(.system(.title, design: .rounded).monospacedDigit())
            .foregroundStyle(.teal)
        } else {
            Text(SurfWorkoutClockFormatter.string(from: controller.timeline.elapsed(at: Date())))
                .font(.system(.title, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var distanceText: String {
        guard let meters = controller.distanceMeters, meters > 0 else { return "--" }
        return String(format: "%.2f", meters / 1000)
    }

    private func metric(value: String, unit: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.body, design: .rounded).monospacedDigit())
            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Ended

    private var endedScreen: some View {
        ScrollView {
            VStack(spacing: 10) {
                if controller.saveStatus == .saving {
                    ProgressView("Saving to Health…")
                } else if controller.saveStatus == .failed {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Workout Not Saved").font(.headline)
                    Text(controller.startupError ?? "Try saving again.").font(.caption)
                    Text(SurfWorkoutClockFormatter.string(from: controller.timeline.elapsed(at: Date())))
                    Button("Retry Save") { Task { await controller.end() } }
                    Button("Close Without Saving", role: .destructive) { confirmDiscard = true }
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
                    Text("Saved to Health").font(.headline)
                    Text(controller.saveStatus == .savedWithoutRoute
                         ? "The workout is saved, but its route is unavailable. You can log wave estimates manually in Peak."
                         : "Review and rate this surf in Peak on your iPhone.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Done") { controller.reset() }
                }
            }
            .multilineTextAlignment(.center)
        }
        .confirmationDialog("Discard this unsaved workout?", isPresented: $confirmDiscard) {
            Button("Discard Workout", role: .destructive) { controller.reset() }
            Button("Keep Workout", role: .cancel) {}
        }
    }
}
