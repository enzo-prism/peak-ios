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
    @State private var backupInspection: BackupManager.Inspection?
    @AppStorage("peak.backup.lastVerifiedExport") private var lastVerifiedExport = 0.0
    @AppStorage("peak.backup.lastSaved") private var lastSavedBackup = 0.0
    @State private var backupExportURL: URL?
    @State private var showBackupExporter = false
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
    @State private var workTask: Task<Void, Never>?
    @State private var canCancelWork = false

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
                    Text("A full backup includes saved sessions and their photos and videos. Save unfinished drafts first. New backups stream videos and verify file checksums. Keep a copy outside this device; JSON and CSV exports do not include session media.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 4)
                        .listRowBackground(Color.clear)
                    if lastSavedBackup > 0 {
                        Text("Last backup saved to Files and verified: \(Date(timeIntervalSince1970: lastSavedBackup).formatted(date: .abbreviated, time: .shortened)). Keep a copy outside this device to protect against losing it.")
                            .font(.caption).foregroundStyle(Theme.textMuted)
                    } else if lastVerifiedExport > 0 {
                        Text("Last verified export prepared: \(Date(timeIntervalSince1970: lastVerifiedExport).formatted(date: .abbreviated, time: .shortened)). Save it to Files to keep a copy.")
                            .font(.caption).foregroundStyle(Theme.textMuted)
                    }
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
                        HealthAccessControl()
                            .listRowBackground(Color.clear)

                        if healthSyncEnabled {
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

                        Text("Peak saves surfing workouts only when workout-write access is allowed. Imported workouts can include heart rate and calories when readable.")
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
                    VStack(spacing: 12) {
                        ProgressView(workingTitle)
                        if canCancelWork {
                            Button("Cancel") {
                                canCancelWork = false
                                workingTitle = "Cancelling…"
                                workTask?.cancel()
                            }
                            .frame(minHeight: 44)
                        }
                    }
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
        .sheet(isPresented: $showBackupExporter, onDismiss: {
            if !isWorking { cleanPreparedBackup() }
        }) {
            if let url = backupExportURL {
                BackupFileExporter(url: url) { result in
                    showBackupExporter = false
                    finishBackupExport(result)
                } cancellation: {
                    showBackupExporter = false
                    cleanPreparedBackup()
                }
            }
        }
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
            Text(backupInspection?.summary ?? "Choose a verified backup before restoring.")
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
        runWork("Backing Up...", errorTitle: "Backup Failed", cancellable: true) {
            let sessions = try modelContext.fetch(
                SurfSession.sortedByDateDescending(prefetch: [\.spot, \.gear, \.buddies, \.media])
            )
            let spots = try modelContext.fetch(FetchDescriptor<Spot>(sortBy: [SortDescriptor(\.name)]))
            let gear = try modelContext.fetch(FetchDescriptor<Gear>(sortBy: [SortDescriptor(\.name)]))
            let buddies = try modelContext.fetch(FetchDescriptor<Buddy>(sortBy: [SortDescriptor(\.name)]))
            let url = try await BackupManager.makeBackupFile(
                sessions: sessions, spots: spots, gear: gear, buddies: buddies,
                progress: { completed, total in
                    workingTitle = completed == total ? "Verifying Backup…" : "Backing Up Media: \(completed) of \(total)"
                }
            )
            lastVerifiedExport = Date().timeIntervalSince1970
            backupExportURL = url
            showBackupExporter = true
        }
    }

    private func cleanPreparedBackup() {
        if let url = backupExportURL { try? FileManager.default.removeItem(at: url) }
        backupExportURL = nil
    }

    private func finishBackupExport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let destination):
            runWork("Verifying Saved Backup…", errorTitle: "Backup Verification Failed") {
                defer { cleanPreparedBackup() }
                let access = destination.startAccessingSecurityScopedResource()
                defer { if access { destination.stopAccessingSecurityScopedResource() } }
                _ = try await BackupManager.inspect(destination)
                lastSavedBackup = Date().timeIntervalSince1970
                // This is a newly exported synthetic fixture, never an input
                // file or a user's backup. Retire it after exercising Files.
                if TestingDefaults.isUITest { try? FileManager.default.removeItem(at: destination) }
                alertMessage = AlertMessage(title: "Backup Saved", body: "Your saved file passed its integrity checks. Keep a copy outside this device to protect your logbook if the device is lost.")
            }
        case .failure(let error):
            cleanPreparedBackup()
            alertMessage = errorAlert(title: "Backup Save Failed", error: error)
        }
    }

    private func handleBackupImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            runWork("Verifying Backup...", errorTitle: "Restore Failed", cancellable: true) {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                let inspection = try await BackupManager.inspect(url)
                pendingBackupURL = url
                backupInspection = inspection
                showBackupRestoreOptions = true
            }
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
        }
    }

    private func resetAllData() {
        runWork("Resetting Data...", errorTitle: "Reset Failed") {
            try SessionPersistence.resetLibrary(from: modelContext)
            var resetMessage = "Your session library, draft, plan and surf timer have been cleared. Exported copies in Files remain where you saved them."
            if !TestingDefaults.isRunningTests {
                do { try await SessionDraftStore.shared.clear() }
                catch { resetMessage = "Your session library was cleared, but a saved draft could not be removed. Reopen Settings and retry Reset All Data to finish removing it." }
            }
            PeakNavigationCoordinator.shared.clearLibraryNavigation()
            SurfPlanStore.clear()
            SessionActivityController.discard()
            ActiveSessionStore.clearPendingLog()
            lastSavedBackup = 0
            lastVerifiedExport = 0
            cleanPreparedBackup()
            NotificationCenter.default.post(name: .peakLibraryDidChange, object: modelContext.container,
                                            userInfo: ["resetMessage": resetMessage])
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
        cancellable: Bool = false,
        operation: @escaping () async throws -> Void
    ) {
        guard !isWorking else { return }
        isWorking = true
        workingTitle = title
        canCancelWork = cancellable
        workTask = Task { @MainActor in
            await Task.yield()
            defer { isWorking = false; canCancelWork = false; workTask = nil }
            do {
                try Task.checkCancellation()
                try await operation()
            } catch is CancellationError {
                // A cancelled export/inspection never changes the logbook.
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
