import SwiftData
import SwiftUI

extension Notification.Name {
    static let peakDraftDidChange = Notification.Name("peakDraftDidChange")
}

struct DraftRecoveryCard: View {
    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(sort: \Gear.name) private var gear: [Gear]
    @Query(sort: \Buddy.name) private var buddies: [Buddy]
    @State private var snapshot: SavedSessionDraft?
    @State private var message: String?
    @State private var showDiscard = false
    @State private var isResuming = false
    @State private var resumeTask: Task<Void, Never>?

    var body: some View {
        // Keep a concrete container mounted even before a snapshot is loaded.
        // An empty Group has no lifecycle node for the cold-start .task.
        VStack(spacing: 0) {
            if let snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Finish your saved draft", systemImage: "square.and.pencil").font(.headline)
                    Text(snapshot.spotName.trimmedNonEmpty ?? "Unfinished session")
                    Text("Kept \(snapshot.savedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(Theme.textMuted)
                    Button(isResuming ? "Opening Draft…" : "Resume Draft") {
                        guard !isResuming, !QuickLogCoordinator.shared.showNewSession else { return }
                        isResuming = true
                        resumeTask = Task {
                            var copies: [UUID: URL] = [:]
                            defer {
                                SessionMediaStore.deleteTemporaryFiles(Array(copies.values))
                                isResuming = false
                            }
                            do {
                                let directory = SessionDraftStore.shared.directory
                                copies = try await snapshot.prepareVideoCopies(in: directory)
                                try Task.checkCancellation()
                                let draft = try snapshot.restore(spots: spots, gear: gear, buddies: buddies, videoCopies: copies)
                                QuickLogCoordinator.shared.requestLog(prefill: draft)
                                copies = [:] // The editor now owns the temporary files.
                            } catch is CancellationError {
                            } catch { message = "This draft could not be opened. Its recovery copy was kept. Check device storage and try again." }
                        }
                    }
                    .disabled(isResuming)
                    .glassButtonStyle(prominent: true)
                    .accessibilityIdentifier("draft.resume")
                    Button("Discard Draft", role: .destructive) { showDiscard = true }.disabled(isResuming)
                }
                .padding(Theme.Spacing.l)
                .glassCard(cornerRadius: Theme.Radius.section, tint: Theme.glassDimTint)
                .padding(.horizontal)
            }
        }
        .task { await load() }
        .onDisappear { resumeTask?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .peakDraftDidChange)) { _ in Task { await load() } }
        .confirmationDialog("Discard the saved draft and its attachments?", isPresented: $showDiscard) {
            Button("Discard Draft", role: .destructive) {
                Task {
                    do {
                        guard let discarded = snapshot else { return }
                        try await SessionDraftStore.shared.clear(matching: discarded.draftID ?? UUID(), allowLegacy: discarded.draftID == nil)
                        await load()
                    }
                    catch { message = "The draft could not be removed. Try again." }
                }
            }
        }
        .alert("Saved Draft", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func load() async {
        guard TestingDefaults.canPersistSessionDrafts else { return }
        do { snapshot = try await SessionDraftStore.shared.load() }
        catch { message = "A saved draft needs recovery. Its files were kept on this device." }
    }
}
