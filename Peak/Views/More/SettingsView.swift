import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]
    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(sort: \Gear.name) private var gear: [Gear]
    @Query(sort: \Buddy.name) private var buddies: [Buddy]

    @State private var showImporter = false
    @State private var importPayload: PeakExport?
    @State private var showImportOptions = false
    @State private var showResetConfirm = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var alertMessage: AlertMessage?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            List {
                Section {
                    SettingsRow(title: "Export JSON", systemImage: "square.and.arrow.up") {
                        exportJSON()
                    }
                    SettingsRow(title: "Export CSV", systemImage: "doc.plaintext") {
                        exportCSV()
                    }
                } header: {
                    sectionHeader("Export")
                }

                Section {
                    SettingsRow(title: "Import JSON Backup", systemImage: "square.and.arrow.down") {
                        showImporter = true
                    }
                } header: {
                    sectionHeader("Import / Restore")
                }

                Section {
                    SettingsRow(
                        title: "Reset All Data",
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        showResetConfirm = true
                    }
                } header: {
                    sectionHeader("Reset")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Peak is private by default. Your data stays on your device.")
                            .font(.custom("Avenir Next", size: 13, relativeTo: .caption))
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
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
                            .glassCard(cornerRadius: 16, tint: Theme.glassDimTint, isInteractive: true)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)

                    NavigationLink {
                        DocumentView(title: "Privacy", resourceName: "Privacy", resourceExtension: "md")
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(cornerRadius: 16, tint: Theme.glassDimTint, isInteractive: true)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                } header: {
                    sectionHeader("About & Support")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
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
        .alert(item: $alertMessage) { message in
            Alert(title: Text(message.title), message: Text(message.body), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
            .foregroundStyle(Theme.textMuted)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

    private func exportJSON() {
        do {
            let url = try PeakExportManager.exportJSONFile(
                sessions: sessions,
                spots: spots,
                gear: gear,
                buddies: buddies
            )
            shareItems = [url]
            showShareSheet = true
        } catch {
            alertMessage = errorAlert(title: "Export Failed", error: error)
        }
    }

    private func exportCSV() {
        do {
            let url = try PeakExportManager.exportCSVFile(sessions: sessions)
            shareItems = [url]
            showShareSheet = true
        } catch {
            alertMessage = errorAlert(title: "Export Failed", error: error)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let data = try Data(contentsOf: url)
                importPayload = try PeakExportManager.decodeJSON(data)
                showImportOptions = true
            } catch {
                alertMessage = errorAlert(title: "Import Failed", error: error)
            }
        case .failure(let error):
            alertMessage = errorAlert(title: "Import Failed", error: error)
        }
    }

    private func applyImport(mode: ImportMode) {
        guard let payload = importPayload else { return }
        do {
            try PeakExportManager.applyImport(payload, mode: mode, context: modelContext)
            alertMessage = AlertMessage(title: "Import Complete", body: "Your data has been updated.")
        } catch {
            alertMessage = errorAlert(title: "Import Failed", error: error)
        }
    }

    private func resetAllData() {
        do {
            try modelContext.resetAllData()
            alertMessage = AlertMessage(title: "Reset Complete", body: "All data has been deleted.")
        } catch {
            alertMessage = errorAlert(title: "Reset Failed", error: error)
        }
    }

    private func errorAlert(title: String, error: Error) -> AlertMessage {
        if let exportError = error as? ExportError {
            switch exportError {
            case .encodingFailed:
                return AlertMessage(title: title, body: "Failed to encode the export file.")
            case .unsupportedSchema:
                return AlertMessage(title: title, body: "This backup format is not supported.")
            }
        }
        return AlertMessage(title: title, body: error.localizedDescription)
    }

    private func openSupportEmail() {
        guard let url = URL(string: "mailto:support@prism.app") else { return }
        UIApplication.shared.open(url)
    }
}

private struct SettingsRow: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(role == .destructive ? Color.red : Theme.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 16, tint: Theme.glassDimTint, isInteractive: true)
        }
        .buttonStyle(.plain)
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
