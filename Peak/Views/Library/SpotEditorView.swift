import SwiftUI
import SwiftData

enum SpotEditorMode {
    case new
    case edit(Spot)

    var title: String {
        switch self {
        case .new:
            return "Add Spot"
        case .edit:
            return "Edit Spot"
        }
    }
}

struct SpotEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: SpotEditorMode
    @State private var name: String
    @State private var alertMessage = ""
    @State private var showAlert = false

    init(mode: SpotEditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            _name = State(initialValue: "")
        case .edit(let spot):
            _name = State(initialValue: spot.name)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    TextField("Spot name", text: $name)
                        .textFieldStyle(.plain)
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
        let existing = modelContext.existingSpot(named: trimmed)

        switch mode {
        case .new:
            if existing != nil {
                alertMessage = "Spot already exists."
                showAlert = true
                return
            }
            let spot = Spot(name: trimmed)
            modelContext.insert(spot)
        case .edit(let spot):
            if let existing, existing.persistentModelID != spot.persistentModelID {
                alertMessage = "Another spot already uses this name."
                showAlert = true
                return
            }
            spot.name = trimmed
            spot.key = Spot.makeKey(from: trimmed)
        }
        dismiss()
    }
}

#Preview {
    SpotEditorView(mode: .new)
        .modelContainer(PreviewData.container)
}
