import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum SessionEditorMode {
    case new
    case edit(SurfSession)

    var title: String {
        switch self {
        case .new:
            return "Log Session"
        case .edit:
            return "Edit Session"
        }
    }
}

struct SessionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(sort: \Gear.name) private var gear: [Gear]
    @Query(sort: \Buddy.name) private var buddies: [Buddy]
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]

    let mode: SessionEditorMode
    @State private var draft: SessionDraft
    @State private var newGearName = ""
    @State private var newGearKind: GearKind = .board
    @State private var newBuddyName = ""
    @State private var showSpotEditor = false
    @State private var showSpotAlert = false
    @State private var spotAlertMessage = ""
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var showMediaAlert = false
    @State private var mediaAlertMessage = ""
    @State private var didSave = false
    @State private var dismissAfterMediaAlert = false

    init(mode: SessionEditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            _draft = State(initialValue: SessionDraft())
        case .edit(let session):
            _draft = State(initialValue: SessionDraft(session: session))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    GlassContainer(spacing: 16) {
                        VStack(alignment: .leading, spacing: 16) {
                            EditorSection("Session") {
                                DatePicker("Date", selection: $draft.date, displayedComponents: [.date])
                                    .datePickerStyle(.compact)
                                    .tint(Theme.textPrimary)
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(12)
                                    .glassInput()
                                    .accessibilityIdentifier("session.editor.date")

                                DatePicker("Start time", selection: $draft.date, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .tint(Theme.textPrimary)
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(12)
                                    .glassInput()
                                    .accessibilityIdentifier("session.editor.startTime")

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Duration")
                                            .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline))
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Text(durationLabel)
                                            .font(.custom("Avenir Next", size: 13, relativeTo: .caption))
                                            .foregroundStyle(Theme.textMuted)
                                    }
                                    Slider(value: durationBinding, in: 0...180, step: 15)
                                        .tint(Theme.textPrimary)
                                        .accessibilityIdentifier("session.editor.duration")
                                        .accessibilityValue(durationLabel)
                                }
                                .padding(12)
                                .glassInput()

                                TextField(
                                    "Spot",
                                    text: $draft.spotName,
                                    prompt: Text("Spot").foregroundStyle(Theme.textMuted)
                                )
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(12)
                                    .glassInput()
                                    .accessibilityIdentifier("session.editor.spot")
                                    .onChange(of: draft.spotName) { _, newValue in
                                        if let selected = draft.selectedSpot, selected.name != newValue {
                                            draft.selectedSpot = nil
                                        }
                                    }

                                if !filteredSpots.isEmpty {
                                    GlassContainer(spacing: 10) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(filteredSpots) { spot in
                                                    SelectableChip(
                                                        label: spot.name,
                                                        systemImage: "mappin",
                                                        isSelected: draft.selectedSpot?.persistentModelID == spot.persistentModelID
                                                    ) {
                                                        draft.selectSpot(spot)
                                                    }
                                                }
                                            }
                                            .padding(.vertical, 4)
                                        }
                                    }
                                } else if !spots.isEmpty {
                                    Text("No matching spots. Add a surf break.")
                                        .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                                        .foregroundStyle(Theme.textMuted)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
                                } else {
                                    Text("No spots saved yet. Add your first surf break.")
                                        .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                                        .foregroundStyle(Theme.textMuted)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
                                }

                                Button {
                                    addSpotTapped()
                                } label: {
                                    Label("Add Surf Break", systemImage: "mappin.and.ellipse")
                                        .frame(maxWidth: .infinity)
                                }
                                .glassButtonStyle(prominent: false)
                                .disabled(isSpotLimitReached)

                                if isSpotLimitReached {
                                    Text("You can save up to \(Spot.maxCount) surf breaks.")
                                        .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }

                            EditorSection("Gear") {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 12) {
                                        TextField(
                                            "Add gear",
                                            text: $newGearName,
                                            prompt: Text("Add gear").foregroundStyle(Theme.textMuted)
                                        )
                                            .textFieldStyle(.plain)
                                            .foregroundStyle(Theme.textPrimary)
                                            .accessibilityIdentifier("session.editor.gear")
                                        Picker("Type", selection: $newGearKind) {
                                            ForEach(GearKind.allCases) { kind in
                                                Text(kind.label).tag(kind)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .tint(Theme.textPrimary)
                                        .foregroundStyle(Theme.textPrimary)
                                    }
                                    .padding(12)
                                    .glassInput()

                                    Button("Add Gear") {
                                        addGear()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .glassButtonStyle(prominent: false)
                                    .disabled(newGearName.trimmedNonEmpty == nil)

                                    if let lastSession = sessions.first, !lastSession.gear.isEmpty {
                                        Button("Use last gear setup") {
                                            draft.selectedGear = lastSession.gear.filter { !$0.isArchived }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .glassButtonStyle(prominent: false)
                                    }
                                }

                                if !availableGear.isEmpty {
                                    GlassContainer(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            ForEach(GearKind.allCases) { kind in
                                                let items = sortedGear(for: kind)
                                                if !items.isEmpty {
                                                    VStack(alignment: .leading, spacing: 8) {
                                                        Text(kind.label.uppercased())
                                                            .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                                                            .foregroundStyle(Theme.textMuted)
                                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                                                            ForEach(items) { item in
                                                                SelectableChip(
                                                                    label: item.name,
                                                                    systemImage: item.kind.systemImage,
                                                                    isSelected: draft.selectedGear.contains(where: { $0.persistentModelID == item.persistentModelID })
                                                                ) {
                                                                    draft.toggleGear(item)
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }

                            EditorSection("Buddies") {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 12) {
                                        TextField(
                                            "Add buddy",
                                            text: $newBuddyName,
                                            prompt: Text("Add buddy").foregroundStyle(Theme.textMuted)
                                        )
                                            .textFieldStyle(.plain)
                                            .foregroundStyle(Theme.textPrimary)
                                            .accessibilityIdentifier("session.editor.buddy")
                                        Button("Add") {
                                            addBuddy()
                                        }
                                        .glassButtonStyle(prominent: true)
                                        .disabled(newBuddyName.trimmedNonEmpty == nil)
                                    }
                                    .padding(12)
                                    .glassInput()
                                }

                                if !buddies.isEmpty {
                                    GlassContainer(spacing: 10) {
                                        let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]
                                        LazyVGrid(columns: columns, spacing: 8) {
                                            ForEach(sortedBuddies) { buddy in
                                                SelectableChip(
                                                    label: buddy.name,
                                                    systemImage: "person",
                                                    isSelected: draft.selectedBuddies.contains(where: { $0.persistentModelID == buddy.persistentModelID })
                                                ) {
                                                    draft.toggleBuddy(buddy)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }

                            EditorSection("Rating") {
                                RatingPickerView(rating: $draft.rating)
                                    .accessibilityIdentifier("session.editor.rating")
                            }

                            EditorSection("Media") {
                                if draft.mediaItems.isEmpty {
                                    Text("Add photos or videos from your library.")
                                        .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                                        .foregroundStyle(Theme.textMuted)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
                                } else {
                                    let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
                                    LazyVGrid(columns: columns, spacing: 12) {
                                        ForEach(draft.mediaItems) { item in
                                            ZStack(alignment: .topTrailing) {
                                                SessionMediaThumbnailView(
                                                    imageData: item.thumbnailData ?? item.photoData,
                                                    isVideo: item.kind == .video
                                                )
                                                .frame(height: 110)
                                                .frame(maxWidth: .infinity)
                                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                                .glassCard(cornerRadius: 16, tint: Theme.glassDimTint, isInteractive: false)

                                                Button {
                                                    removeMediaItem(item)
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.system(size: 18, weight: .semibold))
                                                        .foregroundStyle(Theme.textPrimary)
                                                        .padding(6)
                                                }
                                                .buttonStyle(PressFeedbackButtonStyle())
                                                .accessibilityLabel("Remove media")
                                            }
                                        }
                                    }
                                }

                                PhotosPicker(
                                    selection: $selectedMediaItems,
                                    matching: .any(of: [.images, .videos])
                                ) {
                                    Label("Add Photos or Videos", systemImage: "photo.on.rectangle.angled")
                                        .frame(maxWidth: .infinity)
                                }
                                .glassButtonStyle(prominent: false)
                            }

                            EditorSection("Notes") {
                                ZStack(alignment: .topLeading) {
                                    TextEditor(text: $draft.notes)
                                        .frame(minHeight: 120)
                                        .scrollContentBackground(.hidden)
                                        .foregroundStyle(Theme.textPrimary)
                                        .accessibilityIdentifier("session.editor.notes")
                                    if draft.notes.isEmpty {
                                        Text("Add any conditions, swell, or quick thoughts.")
                                            .foregroundStyle(Theme.textMuted)
                                            .padding(.top, 8)
                                            .padding(.leading, 5)
                                    }
                                }
                                .padding(12)
                                .glassInput()
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .keyboardSafeAreaInset()
                }
            }
        .navigationTitle(mode.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSession()
                    }
                    .disabled(!draft.isReadyToSave)
                }
            }
        }
        .tint(Theme.textPrimary)
        .sheet(isPresented: $showSpotEditor) {
            SpotEditorView(
                mode: .new,
                suggestedName: draft.spotName
            ) { spot in
                draft.selectSpot(spot)
            }
        }
        .alert("Spot", isPresented: $showSpotAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(spotAlertMessage)
        }
        .alert("Media", isPresented: $showMediaAlert) {
            Button("OK", role: .cancel) {
                if dismissAfterMediaAlert {
                    dismissAfterMediaAlert = false
                    dismiss()
                }
            }
        } message: {
            Text(mediaAlertMessage)
        }
        .onChange(of: selectedMediaItems) { _, newValue in
            handleMediaSelection(newValue)
        }
        .onDisappear {
            if !didSave {
                cleanupPendingMedia()
            }
        }
    }

    private var sortedBuddies: [Buddy] {
        return buddies.sorted { lhs, rhs in
            let lhsDate = buddySnapshots[lhs.key]?.lastUsed ?? .distantPast
            let rhsDate = buddySnapshots[rhs.key]?.lastUsed ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.name < rhs.name
            }
            return lhsDate > rhsDate
        }
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { Double(draft.durationMinutes) },
            set: { newValue in
                draft.durationMinutes = Int(newValue.rounded())
            }
        )
    }

    private var durationLabel: String {
        SessionDurationFormatter.string(from: draft.durationMinutes > 0 ? draft.durationMinutes : nil)
    }

    private func sortedGear(for kind: GearKind) -> [Gear] {
        let items = availableGear.filter { $0.kind == kind }
        return items.sorted { lhs, rhs in
            let lhsDate = gearSnapshots[lhs.key]?.lastUsed ?? .distantPast
            let rhsDate = gearSnapshots[rhs.key]?.lastUsed ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.name < rhs.name
            }
            return lhsDate > rhsDate
        }
    }

    private var gearSnapshots: [String: UsageSnapshot] {
        UsageMetricsCalculator.gearSnapshots(sessions: sessions)
    }

    private var availableGear: [Gear] {
        let selectedKeys = Set(draft.selectedGear.map(\.key))
        return gear.filter { !$0.isArchived || selectedKeys.contains($0.key) }
    }

    private var buddySnapshots: [String: UsageSnapshot] {
        UsageMetricsCalculator.buddySnapshots(sessions: sessions)
    }

    private func addGear() {
        guard let name = newGearName.trimmedNonEmpty else { return }
        let stored = modelContext.upsertGear(named: name, kind: newGearKind)
        if !draft.selectedGear.contains(where: { $0.persistentModelID == stored.persistentModelID }) {
            draft.selectedGear.append(stored)
        }
        newGearName = ""
    }

    private func addBuddy() {
        guard let name = newBuddyName.trimmedNonEmpty else { return }
        let stored = modelContext.upsertBuddy(named: name)
        if !draft.selectedBuddies.contains(where: { $0.persistentModelID == stored.persistentModelID }) {
            draft.selectedBuddies.append(stored)
        }
        newBuddyName = ""
    }

    private func saveSession() {
        guard let spot = draft.selectedSpot else {
            spotAlertMessage = "Select a surf break to save this session."
            showSpotAlert = true
            return
        }
        let durationMinutes = SurfSession.normalizedDuration(draft.durationMinutes > 0 ? draft.durationMinutes : nil)

        var mediaFailures = 0

        switch mode {
        case .new:
            let session = SurfSession(
                date: draft.date,
                spot: spot,
                gear: draft.selectedGear,
                buddies: draft.selectedBuddies,
                rating: draft.rating,
                durationMinutes: durationMinutes,
                notes: draft.notes,
                createdAt: Date(),
                updatedAt: Date()
            )
            modelContext.insert(session)
            mediaFailures = applyMedia(to: session)
        case .edit(let session):
            session.date = draft.date
            session.spot = spot
            session.gear = draft.selectedGear
            session.buddies = draft.selectedBuddies
            session.rating = draft.rating
            session.durationMinutes = durationMinutes
            session.notes = draft.notes
            session.updatedAt = Date()
            mediaFailures = applyMedia(to: session)
        }

        didSave = true

        if mediaFailures > 0 {
            mediaAlertMessage = mediaFailures == 1
                ? "One media item could not be saved."
                : "\(mediaFailures) media items could not be saved."
            showMediaAlert = true
            dismissAfterMediaAlert = true
        } else {
            dismissAfterMediaAlert = false
            dismiss()
        }
    }

    private var filteredSpots: [Spot] {
        guard let query = draft.spotName.trimmedNonEmpty else { return spots }
        return spots.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var isSpotLimitReached: Bool {
        spots.count >= Spot.maxCount
    }

    private func addSpotTapped() {
        if isSpotLimitReached {
            spotAlertMessage = "You can save up to \(Spot.maxCount) surf breaks."
            showSpotAlert = true
        } else {
            showSpotEditor = true
        }
    }

    private func handleMediaSelection(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                await addMediaItem(item)
            }
            await MainActor.run {
                selectedMediaItems = []
            }
        }
    }

    private func addMediaItem(_ item: PhotosPickerItem) async {
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isVideo {
            guard let url = try? await item.loadTransferable(type: URL.self) else { return }
            let thumbnailData = SessionMediaStore.videoThumbnailData(from: url)
            await MainActor.run {
                draft.mediaItems.append(.newVideo(temporaryURL: url, thumbnailData: thumbnailData))
            }
        } else {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let photoData = SessionMediaStore.compressedPhotoData(from: data)
            let thumbnailData = SessionMediaStore.thumbnailData(from: photoData)
            await MainActor.run {
                draft.mediaItems.append(.newPhoto(photoData: photoData, thumbnailData: thumbnailData))
            }
        }
    }

    private func cleanupPendingMedia() {
        let pendingURLs = draft.mediaItems.compactMap { $0.temporaryVideoURL }
        SessionMediaStore.deleteTemporaryFiles(pendingURLs)
    }

    private func removeMediaItem(_ item: SessionMediaDraftItem) {
        if let url = item.temporaryVideoURL {
            SessionMediaStore.deleteTemporaryFiles([url])
        }
        draft.removeMediaItem(item)
    }

    private func applyMedia(to session: SurfSession) -> Int {
        let keptExisting = draft.mediaItems.compactMap { $0.existingMedia }
        let keptIds = Set(keptExisting.map(\.persistentModelID))
        let removed = session.media.filter { !keptIds.contains($0.persistentModelID) }
        SessionMediaStore.deleteStoredMedia(for: removed)
        for media in removed {
            modelContext.delete(media)
        }

        var updatedMedia: [SessionMedia] = []
        updatedMedia.reserveCapacity(draft.mediaItems.count)
        var failures = 0

        for item in draft.mediaItems {
            switch item.source {
            case .existing(let media):
                updatedMedia.append(media)
            case .newPhoto(let photoData, let thumbnailData):
                let media = SessionMedia(
                    kind: .photo,
                    photoData: photoData,
                    thumbnailData: thumbnailData,
                    createdAt: item.createdAt
                )
                modelContext.insert(media)
                updatedMedia.append(media)
            case .newVideo(let temporaryURL, let thumbnailData):
                do {
                    let stored = try SessionMediaStore.storeVideo(from: temporaryURL, thumbnailData: thumbnailData)
                    let media = SessionMedia(
                        kind: .video,
                        thumbnailData: stored.thumbnailData,
                        videoFileName: stored.fileName,
                        createdAt: item.createdAt
                    )
                    modelContext.insert(media)
                    updatedMedia.append(media)
                } catch {
                    failures += 1
                    SessionMediaStore.deleteTemporaryFiles([temporaryURL])
                }
            }
        }

        session.media = updatedMedia
        return failures
    }
}

private struct EditorSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                .foregroundStyle(Theme.textMuted)
            content
        }
        .padding(16)
        .glassCard(cornerRadius: 24, tint: Theme.glassDimTint, isInteractive: true)
    }
}

#Preview {
    SessionEditorView(mode: .new)
        .modelContainer(PreviewData.container)
}
