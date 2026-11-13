import SwiftUI

enum BackupProtection {
    static func shouldOffer(sessionCount: Int) -> Bool { sessionCount >= 5 }
    static func changedCount(dates: [Date], since lastBackup: Date?) -> Int {
        guard let lastBackup else { return dates.count }
        return dates.filter { $0 > lastBackup }.count
    }
}

struct BackupProtectionCard: View {
    let sessions: [SurfSession]
    @AppStorage("peak.backup.lastSaved") private var lastSaved = 0.0
    var body: some View {
        if BackupProtection.shouldOffer(sessionCount: sessions.count) {
            NavigationLink { SettingsView() } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label(lastSaved > 0 ? "Your logbook backup" : "Protect your surf history", systemImage: "externaldrive.badge.timemachine")
                        .font(.headline)
                    if lastSaved > 0 {
                        Text("Last verified Files backup: \(Date(timeIntervalSince1970: lastSaved).formatted(date: .abbreviated, time: .shortened)).")
                        let changed = BackupProtection.changedCount(dates: sessions.map(\.updatedAt), since: Date(timeIntervalSince1970: lastSaved))
                        Text("\(changed) current sessions added or edited since that backup.")
                        Text("Back up again after edits or new media. Keep a copy outside this device.")
                    } else {
                        Text("No verified full backup saved yet. Save sessions, photos and videos to Files.")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(Theme.Spacing.l)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .accessibilityIdentifier("log.backupProtection")
        }
    }
}
