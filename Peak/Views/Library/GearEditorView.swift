import PhotosUI
import SwiftUI
import SwiftData
import UIKit

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
    @State private var brand: String
    @State private var model: String
    @State private var size: String
    @State private var volumeText: String
    @State private var notes: String
    @State private var photoData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var alertMessage = ""
    @State private var showAlert = false

    init(mode: GearEditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            _name = State(initialValue: "")
            _kind = State(initialValue: .board)
            _brand = State(initialValue: "")
            _model = State(initialValue: "")
            _size = State(initialValue: "")
            _volumeText = State(initialValue: "")
            _notes = State(initialValue: "")
            _photoData = State(initialValue: nil)
        case .edit(let gear):
            _name = State(initialValue: gear.name)
            _kind = State(initialValue: gear.kind)
            _brand = State(initialValue: gear.brand ?? "")
            _model = State(initialValue: gear.model ?? "")
            _size = State(initialValue: gear.size ?? "")
            if let volume = gear.volumeLiters {
                _volumeText = State(initialValue: String(format: "%.1f", volume))
            } else {
                _volumeText = State(initialValue: "")
            }
            _notes = State(initialValue: gear.notes ?? "")
            _photoData = State(initialValue: gear.photoData)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        editorSection("Basics") {
                            TextField("Name", text: $name)
                                .textFieldStyle(.plain)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(12)
                                .glassInput()
                                .accessibilityIdentifier("gear.editor.name")

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
                        }

                        editorSection("Profile") {
                            TextField("Brand", text: $brand)
                                .textFieldStyle(.plain)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(12)
                                .glassInput()
                                .accessibilityIdentifier("gear.editor.brand")

                            TextField("Model", text: $model)
                                .textFieldStyle(.plain)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(12)
                                .glassInput()
                                .accessibilityIdentifier("gear.editor.model")

                            TextField("Size", text: $size)
                                .textFieldStyle(.plain)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(12)
                                .glassInput()
                                .accessibilityIdentifier("gear.editor.size")

                            TextField("Volume (L)", text: $volumeText)
                                .textFieldStyle(.plain)
                                .foregroundStyle(Theme.textPrimary)
                                .keyboardType(.decimalPad)
                                .padding(12)
                                .glassInput()
                                .accessibilityIdentifier("gear.editor.volume")
                        }

                        editorSection("Photo") {
                            if let data = photoData, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 200)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
                            } else {
                                Text("Add a photo to personalize this board, suit, or fin set.")
                                    .font(.custom("Avenir Next", size: 13, relativeTo: .caption))
                                    .foregroundStyle(Theme.textMuted)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
                            }

                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Label(photoData == nil ? "Choose Photo" : "Replace Photo", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .glassButtonStyle(prominent: false)

                            if photoData != nil {
                                Button("Remove Photo") {
                                    photoData = nil
                                    selectedPhotoItem = nil
                                }
                                .frame(maxWidth: .infinity)
                                .glassButtonStyle(prominent: false)
                            }
                        }

                        editorSection("Notes") {
                            TextEditor(text: $notes)
                                .frame(minHeight: 120)
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(12)
                                .glassInput()
                                .accessibilityIdentifier("gear.editor.notes")
                        }
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
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await loadPhoto(from: newValue)
            }
        }
    }

    private func editorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                .foregroundStyle(Theme.textMuted)
            content()
        }
        .padding(16)
        .glassCard(cornerRadius: 22, tint: Theme.glassDimTint, isInteractive: true)
    }

    private func save() {
        guard let trimmed = name.trimmedNonEmpty else { return }
        let existing = modelContext.existingGear(named: trimmed, kind: kind)

        switch mode {
        case .new:
            if let existing {
                if existing.isArchived {
                    applyFields(to: existing)
                    existing.isArchived = false
                    dismiss()
                    return
                }
                alertMessage = "Gear already exists."
                showAlert = true
                return
            }
            let gear = Gear(
                name: trimmed,
                kind: kind,
                brand: brand.trimmedNonEmpty,
                model: model.trimmedNonEmpty,
                size: size.trimmedNonEmpty,
                volumeLiters: parsedVolume,
                notes: notes.trimmedNonEmpty,
                photoData: photoData,
                isArchived: false
            )
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
            applyFields(to: gear)
        }
        dismiss()
    }

    private func applyFields(to gear: Gear) {
        gear.brand = brand.trimmedNonEmpty
        gear.model = model.trimmedNonEmpty
        gear.size = size.trimmedNonEmpty
        gear.volumeLiters = parsedVolume
        gear.notes = notes.trimmedNonEmpty
        gear.photoData = photoData
    }

    private var parsedVolume: Double? {
        let cleaned = volumeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }
        let normalized = cleaned.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        photoData = compressedPhotoData(from: data)
    }

    private func compressedPhotoData(from data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        return image.jpegData(compressionQuality: 0.85) ?? data
    }
}

#Preview {
    GearEditorView(mode: .new)
        .modelContainer(PreviewData.container)
}
