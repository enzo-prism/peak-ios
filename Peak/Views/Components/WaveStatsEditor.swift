import SwiftUI

/// Editable "Wave stats" rows for `SessionEditorView`'s Details section.
///
/// Two product rules drive every decision in here:
///
/// 1. **Nothing is presented as fact.** Whenever the values came from the
///    analyzer, the footer says so in plain language and points at the fix. A
///    wrong wave count that the app insists on is the single most complained-about
///    behaviour in this category of app; a wrong one the app openly invites you to
///    correct is a minor annoyance.
/// 2. **It works with no workout at all.** Every field is editable from empty, so
///    a surfer who has never worn a watch can still log "6 waves, best one about
///    15 seconds" by hand. That path stamps `.manual` and behaves identically
///    everywhere else in the app.
///
/// Values are stored metric (km/h, metres, seconds) and edited in the user's
/// locale units, converted at this boundary only.
struct WaveStatsEditor: View {
    @Binding var draft: SessionDraft

    private let locale = Locale.autoupdatingCurrent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            waveCountRow

            numericRow(
                label: "Top speed",
                unit: speedUnit.symbol,
                identifier: "session.editor.topSpeed",
                value: speedBinding
            )
            numericRow(
                label: "Longest ride",
                unit: "s",
                identifier: "session.editor.longestRideSeconds",
                value: plainBinding(\.longestRideSeconds)
            )
            numericRow(
                label: "Ride distance",
                unit: lengthUnitLabel,
                identifier: "session.editor.longestRideMeters",
                value: lengthBinding(\.longestRideMeters)
            )
            numericRow(
                label: "Paddle distance",
                unit: lengthUnitLabel,
                identifier: "session.editor.paddleDistance",
                value: lengthBinding(\.paddleDistanceMeters)
            )

            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("session.editor.waveStats.caption")

            if draft.hasWaveStats {
                Button(role: .destructive) {
                    draft.clearWaveStats()
                } label: {
                    Text("Clear wave stats")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle(prominent: false)
                .foregroundStyle(Theme.destructive)
                .accessibilityIdentifier("session.editor.waveStats.clear")
            }
        }
    }

    // MARK: Rows

    /// Wave count gets +/- buttons rather than a keyboard: it is the number people
    /// most often correct, it is always a small integer, and "+1 because the app
    /// missed one" is the exact gesture users want.
    ///
    /// These are explicit buttons rather than a `Stepper` for two reasons. A stock
    /// stepper's segments are about 30pt wide, under the 44pt minimum and fiddly
    /// with cold wet hands. And this row is styled with *interactive* Liquid Glass,
    /// which makes the glass surface itself the touch responder — a compound
    /// control sitting on it never receives the tap at all.
    private var waveCountRow: some View {
        HStack(spacing: 8) {
            Text("Waves")
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            Text(draft.waveCount.map { WaveStatsFormatter.waveCountValue($0) } ?? "Not set")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(draft.waveCount == nil ? Theme.textMuted : Theme.textPrimary)
                .monospacedDigit()
                .accessibilityIdentifier("session.editor.waveCount.value")

            waveCountButton(
                systemName: "minus",
                identifier: "session.editor.waveCount.decrement",
                label: "Remove a wave",
                isEnabled: (draft.waveCount ?? 0) > 0
            ) {
                waveCountBinding.wrappedValue = max(0, (draft.waveCount ?? 0) - 1)
            }

            waveCountButton(
                systemName: "plus",
                identifier: "session.editor.waveCount.increment",
                label: "Add a wave",
                isEnabled: (draft.waveCount ?? 0) < Self.maxWaveCount
            ) {
                waveCountBinding.wrappedValue = (draft.waveCount ?? 0) + 1
            }
        }
        .padding(12)
        .frame(minHeight: 44)
        .glassInput()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Waves"))
        .accessibilityValue(Text(draft.waveCount.map { WaveStatsFormatter.waveCount($0) } ?? "Not set"))
    }

    private func waveCountButton(
        systemName: String,
        identifier: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textMuted)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(label))
    }

    private func numericRow(
        label: String,
        unit: String,
        identifier: String,
        value: Binding<String>
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            TextField("—", text: value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 90)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(Text(label))
            Text(unit)
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(12)
        // A 44pt row keeps the tap target legal even at the smallest text size.
        .frame(minHeight: 44)
        .glassInput()
    }

    // MARK: Copy

    private var caption: String {
        switch draft.waveStatsSource {
        case .auto: return WaveStatsFormatter.estimateCaption
        case .edited: return WaveStatsSource.edited.caption
        case .manual: return WaveStatsSource.manual.caption
        case .none:
            return draft.linkedWorkoutID == nil
                ? WaveStatsFormatter.manualCaption
                : WaveStatsFormatter.estimateCaption
        }
    }

    // MARK: Bindings

    /// Guards against a fat-fingered stepper hold producing an absurd count; also
    /// keeps the value inside anything a share card or widget will render.
    private static let maxWaveCount = 300

    private var waveCountBinding: Binding<Int> {
        Binding(
            get: { draft.waveCount ?? 0 },
            set: {
                draft.waveCount = max(0, min(Self.maxWaveCount, $0))
                draft.markWaveStatsEdited()
            }
        )
    }

    /// Seconds: stored and edited in the same unit, so no conversion.
    private func plainBinding(_ keyPath: WritableKeyPath<SessionDraft, Double?>) -> Binding<String> {
        Binding(
            get: { Self.text(for: draft[keyPath: keyPath]) },
            set: { newText in
                draft[keyPath: keyPath] = Self.value(from: newText)
                draft.markWaveStatsEdited()
            }
        )
    }

    /// Metres in the model, metres or feet in the field.
    private func lengthBinding(_ keyPath: WritableKeyPath<SessionDraft, Double?>) -> Binding<String> {
        Binding(
            get: {
                let converted = draft[keyPath: keyPath].map {
                    Measurement(value: $0, unit: UnitLength.meters).converted(to: lengthUnit).value
                }
                return Self.text(for: converted)
            },
            set: { newText in
                draft[keyPath: keyPath] = Self.value(from: newText).map {
                    Measurement(value: $0, unit: lengthUnit).converted(to: UnitLength.meters).value
                }
                draft.markWaveStatsEdited()
            }
        )
    }

    /// km/h in the model, km/h or mph in the field.
    private var speedBinding: Binding<String> {
        Binding(
            get: {
                let converted = draft.topSpeedKph.map {
                    Measurement(value: $0, unit: UnitSpeed.kilometersPerHour).converted(to: speedUnit).value
                }
                return Self.text(for: converted)
            },
            set: { newText in
                draft.topSpeedKph = Self.value(from: newText).map {
                    Measurement(value: $0, unit: speedUnit).converted(to: UnitSpeed.kilometersPerHour).value
                }
                draft.markWaveStatsEdited()
            }
        )
    }

    // MARK: Units

    private var lengthUnit: UnitLength {
        locale.measurementSystem == .metric ? .meters : .feet
    }

    private var lengthUnitLabel: String {
        lengthUnit == .meters ? "m" : "ft"
    }

    private var speedUnit: UnitSpeed {
        UnitSpeed(forLocale: locale, usage: .wind)
    }

    // MARK: Text <-> value

    /// An empty field means "not recorded", which is a different thing from zero —
    /// so the round trip has to preserve emptiness rather than coerce it to 0.
    private static func text(for value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    private static func value(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Accept both decimal separators: the decimal pad shows whichever the
        // locale uses, but a paste or a hardware keyboard can produce either.
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return value
    }
}
