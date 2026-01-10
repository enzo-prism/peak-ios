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

                VStack(alignment: .leading, spacing: 16) {
                    TextField("Spot name", text: $name)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(12)
                        .glassInput()

                    TextField("Location (city or region)", text: $locationName)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(12)
                        .glassInput()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PIN LOCATION")
                            .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                            .foregroundStyle(Theme.textMuted)

                        mapPicker

                        if selectedCoordinate == nil {
                            Text("Drop a pin to save this surf break.")
                                .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }

                    if isLimitReached {
                        Text("You can save up to \(Spot.maxCount) surf breaks.")
                            .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                            .foregroundStyle(Theme.textMuted)
                    }

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
                        .disabled(!canSave)
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
        guard let location = locationName.trimmedNonEmpty else {
            alertMessage = "Add a location for this surf break."
            showAlert = true
            return
        }
        guard let coordinate = selectedCoordinate else {
            alertMessage = "Drop a pin on the map to save."
            showAlert = true
            return
        }
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
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
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
            spot.latitude = coordinate.latitude
            spot.longitude = coordinate.longitude
            onSave?(spot)
        }
        dismiss()
    }

    private var canSave: Bool {
        guard name.trimmedNonEmpty != nil else { return false }
        guard locationName.trimmedNonEmpty != nil else { return false }
        guard selectedCoordinate != nil else { return false }
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
                    .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                    .padding(10)
                    .allowsHitTesting(false)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)
            .accessibilityLabel("Surf break map")
            .accessibilityHint("Double tap to drop a pin")
        }
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
