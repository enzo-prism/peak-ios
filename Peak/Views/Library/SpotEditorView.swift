import MapKit
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

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }
}

struct SpotEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Spot.name) private var spots: [Spot]

    let mode: SpotEditorMode
    let onSave: ((Spot) -> Void)?
    @State private var name: String
    @State private var locationName: String
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var cameraPosition: MapCameraPosition
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var suggestions: [SurfBreak] = []
    @State private var appliedName: String?
    @State private var locationService = LocationService()
    @State private var isLocating = false
    @State private var showLocationUnavailable = false
    @FocusState private var nameFieldFocused: Bool

    init(mode: SpotEditorMode, suggestedName: String? = nil, onSave: ((Spot) -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .new:
            let trimmed = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            _name = State(initialValue: trimmed)
            _locationName = State(initialValue: "")
            _selectedCoordinate = State(initialValue: nil)
            _cameraPosition = State(initialValue: Self.cameraPosition(for: nil))
        case .edit(let spot):
            _name = State(initialValue: spot.name)
            _locationName = State(initialValue: spot.locationName ?? "")
            let coordinate = spot.coordinate
            _selectedCoordinate = State(initialValue: coordinate)
            _cameraPosition = State(initialValue: Self.cameraPosition(for: coordinate))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Spot name", text: $name)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .foregroundStyle(Theme.textPrimary)
                            .padding(12)
                            .glassInput()
                            .focused($nameFieldFocused)
                            .accessibilityIdentifier("spot.editor.name")
                            .onChange(of: name) { _, newValue in
                                updateSuggestions(for: newValue)
                            }

                        if nameFieldFocused && !suggestions.isEmpty {
                            suggestionList
                        }

                        TextField("Location (city or region)", text: $locationName)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(12)
                            .glassInput()
                            .accessibilityIdentifier("spot.editor.location")

                        VStack(alignment: .leading, spacing: 8) {
                            Text("PIN LOCATION — OPTIONAL")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textMuted)

                            mapPicker

                            if selectedCoordinate == nil {
                                Text("Add a pin to unlock maps and one-tap conditions. You can do this later.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }

                        if isLimitReached {
                            Text("You can save up to \(Spot.maxCount) surf breaks.")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .padding()
                    .readableContentWidth()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .tint(Theme.textPrimary)
        .alert("Cannot Save", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("Location Unavailable", isPresented: $showLocationUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Peak couldn't read your location. You can allow location access in Settings, or tap the map to drop a pin.")
        }
        .task { await applyDefaultRegion() }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                Button {
                    apply(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin")
                            .foregroundStyle(Theme.textMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(item.locationLabel)
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.left")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressFeedbackButtonStyle())
                .accessibilityIdentifier("spot.editor.suggestion.\(item.id)")

                if index < suggestions.count - 1 {
                    Divider().overlay(Theme.glassStroke)
                }
            }
        }
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        .accessibilityIdentifier("spot.editor.suggestions")
    }

    private func updateSuggestions(for query: String) {
        // The name onChange fires after apply() sets the name; don't re-surface the spot we just
        // filled (it isn't saved yet, so it wouldn't be excluded by key).
        if query == appliedName {
            appliedName = nil
            suggestions = []
            return
        }
        let existingKeys = Set(spots.map { $0.key })
        suggestions = SurfBreakCatalog.shared.search(query, excludingKeys: existingKeys)
    }

    /// Fill the form from a tapped popular break: name + location + pin + recenter the map.
    private func apply(_ surfBreak: SurfBreak) {
        appliedName = surfBreak.name
        name = surfBreak.name
        locationName = surfBreak.locationLabel
        let coordinate = surfBreak.coordinate
        selectedCoordinate = coordinate
        cameraPosition = Self.cameraPosition(for: coordinate)
        suggestions = []
        nameFieldFocused = false
    }

    private func save() {
        guard let trimmed = name.trimmedNonEmpty else { return }
        // Location and pin are optional: a first-time surfer can save a break
        // with just a name and add coordinates later. Conditions auto-fill only
        // needs a pin, so it stays a progressive enhancement, never a gate.
        let location = locationName.trimmedNonEmpty
        let coordinate = selectedCoordinate
        let existing = modelContext.existingSpot(named: trimmed)

        switch mode {
        case .new:
            if isLimitReached {
                alertMessage = "You can save up to \(Spot.maxCount) surf breaks."
                showAlert = true
                return
            }
            if existing != nil {
                alertMessage = "Spot already exists."
                showAlert = true
                return
            }
            do {
                let spot = try modelContext.createSpot(
                    name: trimmed,
                    locationName: location,
                    latitude: coordinate?.latitude,
                    longitude: coordinate?.longitude
                )
                onSave?(spot)
            } catch {
                alertMessage = error.localizedDescription
                showAlert = true
                return
            }
        case .edit(let spot):
            if let existing, existing.persistentModelID != spot.persistentModelID {
                alertMessage = "Another spot already uses this name."
                showAlert = true
                return
            }
            spot.name = trimmed
            spot.key = Spot.makeKey(from: trimmed)
            spot.locationName = location
            spot.latitude = coordinate?.latitude
            spot.longitude = coordinate?.longitude
            onSave?(spot)
        }
        dismiss()
    }

    private var canSave: Bool {
        guard name.trimmedNonEmpty != nil else { return false }
        if isLimitReached { return false }
        return true
    }

    private var isLimitReached: Bool {
        mode.isNew && spots.count >= Spot.maxCount
    }

    private var mapPicker: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if let coordinate = selectedCoordinate {
                    Marker(name.trimmedNonEmpty ?? "Surf break", coordinate: coordinate)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .gesture(
                SpatialTapGesture().onEnded { value in
                    if let coordinate = proxy.convert(value.location, from: .local) {
                        selectedCoordinate = coordinate
                        cameraPosition = Self.cameraPosition(for: coordinate)
                    }
                }
            )
            .overlay(alignment: .topLeading) {
                Label("Tap to drop a pin", systemImage: "mappin")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                    .padding(10)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                useMyLocationButton
                    .padding(10)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)
            .accessibilityLabel("Surf break map")
            .accessibilityHint("Double tap to drop a pin")
            .accessibilityIdentifier("spot.editor.map")
        }
    }

    @ViewBuilder
    private var useMyLocationButton: some View {
        Button {
            Task { await useMyLocation() }
        } label: {
            HStack(spacing: 6) {
                if isLocating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "location.fill")
                }
                Text("My Location")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .glassCapsule(tint: Theme.glassDimTint, isInteractive: true)
        }
        .disabled(isLocating)
        .accessibilityIdentifier("spot.editor.useMyLocation")
    }

    /// Frames the map on first appearance without overriding an existing pin:
    /// the spot's own coordinate, else the user's location (only if already
    /// authorized — never prompts on appear), else a region fitted to the
    /// user's other pinned spots, else a wide default. Never lands on 0,0.
    private func applyDefaultRegion() async {
        guard selectedCoordinate == nil else { return }
        let userCoordinate = locationService.isAuthorized ? await locationService.currentLocation() : nil
        let region = SpotMapRegion.defaultRegion(
            spotCoordinate: selectedCoordinate,
            userCoordinate: userCoordinate,
            pinnedSpotCoordinates: spots.compactMap(\.coordinate)
        )
        cameraPosition = .region(region)
    }

    /// Drops a pin at the user's current location (requesting permission if
    /// needed) and reverse-geocodes a city/region label when one isn't set.
    private func useMyLocation() async {
        isLocating = true
        defer { isLocating = false }
        guard let coordinate = await locationService.currentLocation() else {
            showLocationUnavailable = true
            return
        }
        selectedCoordinate = coordinate
        cameraPosition = Self.cameraPosition(for: coordinate)
        if locationName.trimmedNonEmpty == nil,
           let label = await Self.reverseGeocode(coordinate) {
            locationName = label
        }
    }

    nonisolated private static func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let parts = [placemark.locality, placemark.administrativeArea].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func cameraPosition(for coordinate: CLLocationCoordinate2D?) -> MapCameraPosition {
        if let coordinate {
            return .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
                )
            )
        }
        return .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
            )
        )
    }
}

#Preview {
    SpotEditorView(mode: .new)
        .modelContainer(PreviewData.container)
}
