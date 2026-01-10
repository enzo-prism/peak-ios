import SwiftUI
import SwiftData

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
                                    .onChange(of: draft.spotName) { newValue in
                                        if let selected = draft.selectedSpot, selected.name != newValue {
                                            draft.selectedSpot = nil
                                        }
                                    }

                                if !spots.isEmpty {
                                    GlassContainer(spacing: 10) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(spots) { spot in
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
                                            draft.selectedGear = lastSession.gear
                                        }
                                        .frame(maxWidth: .infinity)
                                        .glassButtonStyle(prominent: false)
                                    }
                                }

                                if !gear.isEmpty {
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

    private func sortedGear(for kind: GearKind) -> [Gear] {
        let items = gear.filter { $0.kind == kind }
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
        let spot: Spot
        if let selectedSpot = draft.selectedSpot {
            spot = selectedSpot
        } else if let spotName = draft.spotName.trimmedNonEmpty {
            spot = modelContext.upsertSpot(named: spotName)
        } else {
            return
        }

        switch mode {
        case .new:
            let session = SurfSession(
                date: draft.date,
                spot: spot,
                gear: draft.selectedGear,
                buddies: draft.selectedBuddies,
                rating: draft.rating,
                notes: draft.notes,
                createdAt: Date(),
                updatedAt: Date()
            )
            modelContext.insert(session)
        case .edit(let session):
            session.date = draft.date
            session.spot = spot
            session.gear = draft.selectedGear
            session.buddies = draft.selectedBuddies
            session.rating = draft.rating
            session.notes = draft.notes
            session.updatedAt = Date()
        }
        dismiss()
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
