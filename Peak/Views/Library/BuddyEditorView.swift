import SwiftUI
import SwiftData

enum BuddyEditorMode {
    case new
    case edit(Buddy)

    var title: String {
        switch self {
        case .new:
            return "Add Buddy"
        case .edit:
            return "Edit Buddy"
        }
    }
}

struct BuddyEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: BuddyEditorMode
    @State private var name: String
    @State private var alertMessage = ""
    @State private var showAlert = false

    init(mode: BuddyEditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            _name = State(initialValue: "")
        case .edit(let buddy):
            _name = State(initialValue: buddy.name)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Buddy name", text: $name)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(12)
                            .glassInput()
                            .accessibilityIdentifier("buddy.editor.name")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .keyboardSafeAreaInset()
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
        let existing = modelContext.existingBuddy(named: trimmed)

        switch mode {
        case .new:
            if existing != nil {
                alertMessage = "Buddy already exists."
                showAlert = true
                return
            }
            let buddy = Buddy(name: trimmed)
            modelContext.insert(buddy)
        case .edit(let buddy):
            if let existing, existing.persistentModelID != buddy.persistentModelID {
                alertMessage = "Another buddy already uses this name."
                showAlert = true
                return
            }
            buddy.name = trimmed
            buddy.key = Buddy.makeKey(from: trimmed)
        }
        dismiss()
    }
}

#Preview {
    BuddyEditorView(mode: .new)
        .modelContainer(PreviewData.container)
}
