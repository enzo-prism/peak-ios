import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen card and Dynamic Island presentation for a session in progress.
///
/// Every elapsed-time readout is a `Text(timerInterval:)`, so the system ticks
/// the clock itself: Peak never sends a push, never holds a push token, and the
/// activity stays correct even with the phone in a drybag on the beach.
struct PeakSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PeakSessionActivityAttributes.self) { context in
            lockScreenCard(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.spotName ?? "Surfing")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "figure.surfing")
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsed(from: context.state.startDate)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Button(intent: EndSessionIntent()) {
                        Label("End Session", systemImage: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            } compactLeading: {
                Image(systemName: "figure.surfing")
            } compactTrailing: {
                elapsed(from: context.state.startDate)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "figure.surfing")
            }
            .widgetURL(peakLogSessionURL)
        }
    }

    private func lockScreenCard(
        context: ActivityViewContext<PeakSessionActivityAttributes>
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SESSION IN PROGRESS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(context.attributes.spotName ?? "Surfing")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                elapsed(from: context.state.startDate)
                    .font(.title2.monospacedDigit().weight(.semibold))
            }

            Spacer(minLength: 0)

            Button(intent: EndSessionIntent()) {
                Label("End", systemImage: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(16)
    }

    /// Counting up from the paddle-out, no end in sight — the surfer decides
    /// when it stops.
    private func elapsed(from startDate: Date) -> Text {
        Text(timerInterval: startDate...Date.distantFuture, countsDown: false)
    }
}
