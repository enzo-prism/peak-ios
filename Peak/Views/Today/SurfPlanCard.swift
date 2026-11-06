import SwiftData
import SwiftUI

extension Notification.Name {
    static let peakSurfPlanDidChange = Notification.Name("peakSurfPlanDidChange")
}

struct SurfPlanCard: View {
    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(sort: \Gear.name) private var gear: [Gear]
    @State private var plan: SurfPlan?

    var body: some View {
        // onAppear needs a mounted node even before the stored plan loads.
        VStack(spacing: 0) {
            if let plan {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Your surf plan", systemImage: "sun.horizon")
                            .font(.headline)
                        Text(plan.spotName).font(.title3.weight(.semibold))
                        Text("\(plan.start.formatted(date: .abbreviated, time: .shortened)) – \(plan.end.formatted(date: .omitted, time: .shortened))")
                        Text(plan.summary).font(.subheadline)
                        Text("Checked \(plan.fetchedAt.formatted(date: .abbreviated, time: .shortened)). Forecast snapshot; conditions can change.")
                            .font(.caption).foregroundStyle(Theme.textMuted)
                        if plan.isUsable(at: timeline.date), spots.contains(where: { $0.key == plan.spotKey }) {
                            Button("Log with this setup", systemImage: "plus") {
                                if let draft = SurfPlanStore.draft(for: plan, spots: spots, gear: gear) {
                                    QuickLogCoordinator.shared.requestLog(prefill: draft)
                                }
                            }
                            .glassButtonStyle(prominent: true)
                            .accessibilityIdentifier("plan.log")
                        } else {
                            Text("This plan needs a fresh conditions check.").font(.subheadline)
                        }
                        Button("Remove plan", role: .destructive) {
                            SurfPlanStore.clear(); self.plan = nil
                        }
                    }
                    .padding(Theme.Spacing.l)
                    .glassCard(cornerRadius: Theme.Radius.section, tint: Theme.glassDimTint)
                    .padding(.horizontal)
                }
            }
        }
        .onAppear { plan = SurfPlanStore.load() }
        .onReceive(NotificationCenter.default.publisher(for: .peakSurfPlanDidChange)) { _ in plan = SurfPlanStore.load() }
    }
}
