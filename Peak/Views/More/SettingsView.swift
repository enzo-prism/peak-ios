import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showImporter = false
    @State private var importPayload: PeakExport?
    @State private var showImportOptions = false
    @State private var showBackupImporter = false
    @State private var pendingBackupURL: URL?
    @State private var showBackupRestoreOptions = false
    @State private var showResetConfirm = false
    @AppStorage(HealthKitService.healthSyncEnabledKey) private var healthSyncEnabled = false
    @AppStorage(HealthKitService.notifyUnloggedWorkoutsKey) private var notifyUnloggedWorkouts = false
    @AppStorage(TodayWindowService.autoRefreshKey) private var windowAutoRefresh = false
    @AppStorage(MonthlyGoalCalculator.metricKey) private var goalMetricRaw = MonthlyGoalMetric.sessions.rawValue
    @AppStorage(MonthlyGoalCalculator.targetKey) private var goalTarget = MonthlyGoalCalculator.defaultTarget
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var alertMessage: AlertMessage?
    @State private var isWorking = false
    @State private var workingTitle = "Working..."

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            List {
                Section {
                    Picker("Goal", selection: $goalMetricRaw) {
                        ForEach(MonthlyGoalMetric.allCases) { metric in
                            Text(metric.label).tag(metric.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)

                    Stepper(value: $goalTarget, in: 0...MonthlyGoalCalculator.maximumTarget) {
                        Text(goalTarget == 0
                             ? "No goal"
                             : "\(goalTarget) \(goalMetric.unitLabel) per month")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(12)
                    .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: false)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("settings.monthlyGoal.stepper")

                    if goalTarget == 0 {
                        Button("Use suggested target") {
                            goalTarget = goalMetric == .sessions
                                ? MonthlyGoalCalculator.suggestedTarget
                                : MonthlyGoalCalculator.suggestedHoursTarget
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 4)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("settings.monthlyGoal.useSuggested")
                    }

                    Text("A monthly target you can miss a week of and still hit. Set it to zero to hide the goal ring.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 4)
                        .listRowBackground(Color.clear)
                } header: {
                    sectionHeader("Monthly Goal")
                }

                Section {
                    SettingsRow(title: "Export JSON", systemImage: "square.and.arrow.up", isDisabled: isWorking) {
                        exportJSON()
                    }
                    SettingsRow(title: "Export CSV", systemImage: "doc.plaintext", isDisabled: isWorking) {
                        exportCSV()
                    }
                } header: {
                    sectionHeader("Export")
                }

                Section {
                    SettingsRow(title: "Back Up Everything", systemImage: "externaldrive.badge.timemachine", isDisabled: isWorking) {
                        backUpEverything()
                    }
                    SettingsRow(title: "Restore from Backup", systemImage: "arrow.clockwise.icloud", isDisabled: isWorking) {
                        showBackupImporter = true
                    }
                    Text("A full backup (.peakbackup) includes your photos and videos. JSON and CSV exports do not.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 4)
                        .listRowBackground(Color.clear)
                } header: {
                    sectionHeader("Full Backup")
                }

                Section {
                    SettingsRow(title: "Import JSON Backup", systemImage: "square.and.arrow.down", isDisabled: isWorking) {
                        showImporter = true
                    }
                } header: {
                    sectionHeader("Import / Restore")
                }

                Section {
                    Toggle(isOn: $windowAutoRefresh) {
                        Label("Refresh automatically when I open Peak", systemImage: "arrow.clockwise")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.textPrimary)
                    .padding(12)
                    .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: false)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("settings.window.autoRefresh")

                    Text("Off by default. Peak stays offline until you tap Check conditions on the Best Window card.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .listRowBackground(Color.clear)
                } header: {
                    sectionHeader("Best Window Today")
                }

                if HealthKitService.isHealthDataAvailable {
                    Section {
                        Toggle(isOn: $healthSyncEnabled) {
                            Label("Sync with Apple Health", systemImage: "heart.fill")
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .tint(Theme.textPrimary)
                        .padding(12)
                        .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: false)
                        .listRowBackground(Color.clear)
                        .onChange(of: healthSyncEnabled) { _, isOn in
                            guard isOn else { return }
                            Task { try? await HealthKitService.shared.requestAuthorization() }
                        }

                        if healthSyncEnabled {
                            NavigationLink {
                                HealthImportView()
                            } label: {
                                Label("Import from Health", systemImage: "square.and.arrow.down")
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: true)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)

                            SettingsRow(title: "Sync Existing Sessions", systemImage: "arrow.triangle.2.circlepath", isDisabled: isWorking) {
                                syncExistingToHealth()
                            }

                            Toggle(isOn: $notifyUnloggedWorkouts) {
                                Label("Notify when a Watch surf is ready to log", systemImage: "bell")
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .tint(Theme.textPrimary)
                            .padding(12)
                            .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: false)
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("settings.health.notifyUnlogged")
                            .onChange(of: notifyUnloggedWorkouts) { _, isOn in
                                guard isOn else { return }
                                Task { await UnloggedSurfNotification.requestAuthorization() }
                            }
                        }

                        Text("Your surf sessions are saved to Apple Health as surfing workouts. Apple Watch workouts you record surface heart rate and calories on each session.")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                            .padding(.horizontal, 4)
                            .listRowBackground(Color.clear)
                    } header: {
                        sectionHeader("Apple Health")
                    }
                }

                Section {
                    SettingsRow(
                        title: "Reset All Data",
                        systemImage: "trash",
                        role: .destructive,
                        isDisabled: isWorking
                    ) {
                        showResetConfirm = true
                    }
                } header: {
                    sectionHeader("Reset")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Peak is private by default. Your data stays on your device.")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(Theme.Spacing.l)
                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
                    .listRowBackground(Color.clear)

                    SettingsRow(title: "Email Support", systemImage: "envelope") {
                        openSupportEmail()
                    }

                    NavigationLink {
                        DocumentView(title: "Support", resourceName: "Support", resourceExtension: "md")
                    } label: {
                        Label("Support Guide", systemImage: "questionmark.circle")
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: true)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)

                    NavigationLink {
                        DocumentView(title: "Privacy", resourceName: "Privacy", resourceExtension: "md")
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: true)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                } header: {
                    sectionHeader("About & Support")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityHidden(isWorking)

            if isWorking {
                ZStack {
                    Theme.background.opacity(0.6)
                        .ignoresSafeArea()
                    ProgressView(workingTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
                }
                .accessibilityAddTraits(.isModal)
            }
        }
        .navigationTitle("Settings")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.data]) { result in
            handleBackupImport(result)
        }
        .confirmationDialog(
            "Restore backup",
            isPresented: $showBackupRestoreOptions,
            titleVisibility: .visible
        ) {
            Button("Merge") {
                restoreBackup(mode: .merge)
            }
            Button("Replace All Data", role: .destructive) {
                restoreBackup(mode: .replace)
            }
            Button("Cancel", role: .cancel) { pendingBackupURL = nil }
        } message: {
            Text("Replace is recommended for a clean restore. Merge keeps current data but can duplicate photos if you restore the same backup twice.")
        }
        .confirmationDialog(
            "Import backup",
            isPresented: $showImportOptions,
            titleVisibility: .visible
        ) {
            Button("Merge") {
                applyImport(mode: .merge)
            }
            Button("Replace All Data", role: .destructive) {
                applyImport(mode: .replace)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Merge updates existing items and keeps your data. Replace deletes everything first.")
        }
        .confirmationDialog(
            "Reset all data?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                resetAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all sessions, gear, spots, and buddies.")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .alert(
            alertMessage?.title ?? "",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            ),
            presenting: alertMessage
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message.body)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textMuted)
    }

    private var goalMetric: MonthlyGoalMetric {
        MonthlyGoalMetric(rawValue: goalMetricRaw) ?? .sessions
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

    private func exportJSON() {
        runWork("Exporting JSON...", errorTitle: "Export Failed") {
            let export = try makeExportPayload()
            let url = try await Task.detached(priority: .userInitiated) {
                try PeakExportManager.exportJSONFile(from: export)
            }.value
            shareItems = [url]
            showShareSheet = true
        }
    }

    private func exportCSV() {
        runWork("Exporting CSV...", errorTitle: "Export Failed") {
            let export = try makeExportPayload()
            let url = try await Task.detached(priority: .userInitiated) {
                try PeakExportManager.exportCSVFile(from: export)
            }.value
            shareItems = [url]
            showShareSheet = true
        }
    }

    /// Fetches the data sets only when an export is requested, instead of
    /// keeping standing queries alive for the lifetime of the settings screen.
    private func makeExportPayload() throws -> PeakExport {
        PeakExportManager.makeExport(
            sessions: try modelContext.fetch(
                SurfSession.sortedByDateDescending(prefetch: [\.spot, \.gear, \.buddies])
            ),
            spots: try modelContext.fetch(FetchDescriptor<Spot>(sortBy: [SortDescriptor(\.name)])),
            gear: try modelContext.fetch(FetchDescriptor<Gear>(sortBy: [SortDescriptor(\.name)])),
            buddies: try modelContext.fetch(FetchDescriptor<Buddy>(sortBy: [SortDescriptor(\.name)]))
        )
    }

    private func syncExistingToHealth() {
        runWork("Syncing to Health...", errorTitle: "Sync Failed") {
            let all = try modelContext.fetch(SurfSession.sortedByDateDescending())
            let summary = await HealthKitService.shared.syncAllSessions(all)
            alertMessage = AlertMessage(
                title: "Health Sync Complete",
                body: "\(summary.written) saved, \(summary.skipped) skipped, \(summary.failed) failed."
            )
        }
    }

    private func backUpEverything() {
        runWork("Backing Up...", errorTitle: "Backup Failed") {
            let sessions = try modelContext.fetch(
                SurfSession.sortedByDateDescending(prefetch: [\.spot, \.gear, \.buddies, \.media])
            )
            let spots = try modelContext.fetch(FetchDescriptor<Spot>(sortBy: [SortDescriptor(\.name)]))
            let gear = try modelContext.fetch(FetchDescriptor<Gear>(sortBy: [SortDescriptor(\.name)]))
            let buddies = try modelContext.fetch(FetchDescriptor<Buddy>(sortBy: [SortDescriptor(\.name)]))
            let url = try await BackupManager.makeBackupFile(
                sessions: sessions, spots: spots, gear: gear, buddies: buddies
            )
            shareItems = [url]
            showShareSheet = true
        }
    }

    private func handleBackupImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            pendingBackupURL = url
            showBackupRestoreOptions = true
        case .failure(let error):
            alertMessage = errorAlert(title: "Restore Failed", error: error)
        }
    }

    private func restoreBackup(mode: ImportMode) {
        guard let url = pendingBackupURL else { return }
        runWork("Restoring Backup...", errorTitle: "Restore Failed") {
            defer { pendingBackupURL = nil }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            try await BackupManager.restore(from: url, mode: mode, context: modelContext)
            alertMessage = AlertMessage(title: "Restore Complete", body: "Your backup has been restored.")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            runWork("Reading Backup...", errorTitle: "Import Failed") {
                let payload = try await loadImportPayload(from: url)
                importPayload = payload
                showImportOptions = true
            }
        case .failure(let error):
            alertMessage = errorAlert(title: "Import Failed", error: error)
        }
    }

    private func applyImport(mode: ImportMode) {
        guard let payload = importPayload else { return }
        runWork("Importing Backup...", errorTitle: "Import Failed") {
            try PeakExportManager.applyImport(payload, mode: mode, context: modelContext)
            alertMessage = AlertMessage(title: "Import Complete", body: "Your data has been updated.")
        }
    }

    private func resetAllData() {
        runWork("Resetting Data...", errorTitle: "Reset Failed") {
            try modelContext.resetAllData()
            alertMessage = AlertMessage(title: "Reset Complete", body: "All data has been deleted.")
        }
    }

    private func loadImportPayload(from url: URL) async throws -> PeakExport {
        try await Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            return try PeakExportManager.decodeJSON(data)
        }.value
    }

    private func runWork(
        _ title: String,
        errorTitle: String,
        operation: @escaping () async throws -> Void
    ) {
        guard !isWorking else { return }
        Task { @MainActor in
            isWorking = true
            workingTitle = title
            await Task.yield()
            defer { isWorking = false }

            do {
                try await operation()
            } catch {
                alertMessage = errorAlert(title: errorTitle, error: error)
            }
        }
    }

    private func errorAlert(title: String, error: Error) -> AlertMessage {
        if let exportError = error as? ExportError {
            switch exportError {
            case .encodingFailed:
                return AlertMessage(title: title, body: "Failed to encode the export file.")
            case .unsupportedSchema:
                return AlertMessage(title: title, body: "This backup format is not supported.")
            case .invalidSessionIdentity, .ambiguousSessionIdentity:
                return AlertMessage(title: title, body: exportError.localizedDescription)
            }
        }
        return AlertMessage(title: title, body: error.localizedDescription)
    }

    private func openSupportEmail() {
        guard let url = URL(string: "mailto:support@prism.app"),
              UIApplication.shared.canOpenURL(url) else {
            alertMessage = AlertMessage(
                title: "Email Unavailable",
                body: "No mail app is set up on this device. You can reach us at support@prism.app."
            )
            return
        }
        UIApplication.shared.open(url)
    }
}

private struct SettingsRow: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(role == .destructive ? Theme.destructive : Theme.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: Theme.Radius.input, tint: Theme.glassDimTint, isInteractive: true)
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
        .listRowBackground(Color.clear)
    }
}

private struct AlertMessage: Identifiable {
    let title: String
    let body: String

    var id: String { title + body }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
