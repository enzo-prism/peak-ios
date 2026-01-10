import SwiftUI
import SwiftData

enum GearEditorMode {
    case new
    case edit(Gear)

    var title: String {
        switch self {
        case .new:
            return "Add Gear"
        case .edit:
            return "Edit Gear"
        }
    }
}

struct GearEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: GearEditorMode
    @State private var name: String
    @State private var kind: GearKind
    @State private var alertMessage = ""
    @State private var showAlert = false

    init(mode: GearEditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            _name = State(initialValue: "")
            _kind = State(initialValue: .board)
        case .edit(let gear):
            _name = State(initialValue: gear.name)
            _kind = State(initialValue: gear.kind)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(12)
                        .glassInput()

                    Picker("Type", selection: $kind) {
                        ForEach(GearKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.textPrimary)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(12)
                    .glassInput()

                    Spacer()
                }
                .padding()
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmedNonEmpty == nil)
                }
            }
        }
        .alert("Cannot Save", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func save() {
        guard let trimmed = name.trimmedNonEmpty else { return }
        let existing = modelContext.existingGear(named: trimmed, kind: kind)

        switch mode {
        case .new:
            if existing != nil {
                alertMessage = "Gear already exists."
                showAlert = true
                return
            }
            let gear = Gear(name: trimmed, kind: kind)
            modelContext.insert(gear)
        case .edit(let gear):
            if let existing, existing.persistentModelID != gear.persistentModelID {
                alertMessage = "Another gear item already uses this name and kind."
                showAlert = true
                return
            }
            gear.name = trimmed
            gear.kind = kind
            gear.key = Gear.makeKey(name: trimmed, kind: kind)
        }
        dismiss()
    }
}

#Preview {
    GearEditorView(mode: .new)
        .modelContainer(PreviewData.container)
}
