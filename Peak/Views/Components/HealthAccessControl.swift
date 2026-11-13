import SwiftUI
import HealthKit

/// A preference is not a permission grant. HealthKit intentionally hides read status.
struct HealthAccessControl: View {
    @AppStorage(HealthKitService.healthSyncEnabledKey) private var enabled = false
    @State private var requesting = false
    @State private var errorMessage: String?
    @State private var sharingDenied = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Use Apple Health", isOn: Binding(get: { enabled }, set: { value in
                if value { request() } else { enabled = false; errorMessage = nil }
            }))
            .disabled(requesting)
            .accessibilityIdentifier("health.integration.toggle")
            if requesting { ProgressView("Opening Health permissions…") }
            Text(enabled ? "Health integration is enabled in Peak. Access depends on your choices in Health." : "Import surfing workouts recorded by your Watch or another app, and optionally save Peak sessions to Health.")
                .font(.subheadline)
            Text("The phone timer measures elapsed time only. Record a surfing workout on your Watch, then import it here.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            if enabled {
                Button("Review Health access", action: request)
                    .frame(minHeight: 44)
                    .disabled(requesting)
                if sharingDenied {
                    Text("Saving workouts is not allowed. You can change access in Health → your profile → Apps → Peak. Manual logging still works.")
                        .font(.caption)
                }
                NavigationLink("Import surfing workouts") { HealthImportView() }
                    .frame(minHeight: 44)
            }
            if let errorMessage {
                Text(errorMessage).font(.subheadline)
                    .accessibilityIdentifier("health.integration.error")
            }
        }
        .onAppear { refreshStatus() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshStatus() } }
    }

    private func request() {
        guard !requesting else { return }
        requesting = true
        errorMessage = nil
        Task {
            defer { requesting = false }
            do {
                try await HealthAccessFlow.enable(request: {
                    try await HealthKitService.shared.requestAuthorization()
                }, setEnabled: { enabled = $0 })
                HealthKitService.shared.startObservingUnloggedWorkouts()
                refreshStatus()
            } catch {
                errorMessage = "Health permissions could not be opened. Try again; your manual logbook is unchanged."
            }
        }
    }
    private func refreshStatus() { sharingDenied = HealthKitService.shared.isWorkoutSharingDenied }
}

struct HealthEntryCard: View {
    @State private var showHealth = false
    var body: some View {
        if HealthKitService.isHealthDataAvailable {
            Button {
                showHealth = true
            } label: {
                Label("Import a Watch surf", systemImage: "applewatch")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(Theme.Spacing.l)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .accessibilityIdentifier("log.healthImport")
            .sheet(isPresented: $showHealth) {
                NavigationStack {
                    List { Section { HealthAccessControl() } }
                        .navigationTitle("Apple Health")
                        .toolbar { ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showHealth = false }
                        } }
                }
            }
        }
    }
}
