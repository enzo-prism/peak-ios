import SwiftUI

@available(iOS 26.0, *)
struct VoiceLogSheet: View {
    let spots: [Spot]
    let gear: [Gear]
    let apply: (VoiceLogFields) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = VoiceLogRecorder()
    @State private var startTask: Task<Void, Never>?
    @FocusState private var transcriptFocused: Bool
    @State private var showDiscard = false
    @State private var didApply = false

    private var fields: VoiceLogFields { VoiceLogParser.parse(recorder.transcript, spots: spots, gear: gear) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Say the saved spot and gear names, your time in water, a star rating and any notes. Review the result before adding it to your draft.")
                    Text("Speech is processed on this device. The first use may download Apple's speech model. Audio is deleted when you finish or close this sheet.")
                        .font(.caption).foregroundStyle(.secondary)
                    if recorder.state == .recording {
                        Button("Finish Recording", systemImage: "stop.circle") { recorder.finish() }
                    } else if recorder.state == .transcribing {
                        ProgressView("Transcribing on device…")
                    } else {
                        Button("Record Session", systemImage: "mic") {
                            startTask = Task { await recorder.start() }
                        }
                    }
                    if let error = recorder.errorMessage { Text(error).font(.subheadline) }
                }
                Section("Review transcript") {
                    TextEditor(text: $recorder.transcript).frame(minHeight: 120)
                        .focused($transcriptFocused)
                        .accessibilityLabel("Session transcript")
                        .accessibilityIdentifier("voice.transcript")
                }
                Section("Recognized fields") {
                    LabeledContent("Spot", value: fields.spot?.name ?? "Keep current spot")
                    LabeledContent("Gear", value: fields.gear.isEmpty ? "Keep current setup" : fields.gear.map(\.name).joined(separator: ", "))
                    LabeledContent("Time in water", value: fields.durationMinutes.map { "\($0) minutes" } ?? "Keep current duration")
                    LabeledContent("Rating", value: fields.rating.map { "\($0) stars" } ?? "Keep current rating")
                    Text("The full transcript will be appended to Notes. No conditions are inferred.").font(.caption)
                }
            }
            .navigationTitle("Speak Your Surf")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if recorder.transcript.trimmedNonEmpty != nil || recorder.state != .idle { showDiscard = true }
                        else { dismiss() }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { transcriptFocused = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Transcript") {
                        guard !didApply else { return }
                        didApply = true
                        apply(fields)
                        dismiss()
                    }
                        .disabled(didApply || recorder.transcript.trimmedNonEmpty == nil || recorder.state != .idle)
                }
            }
        }
        .interactiveDismissDisabled(recorder.transcript.trimmedNonEmpty != nil || recorder.state != .idle)
        .confirmationDialog("Discard this transcript?", isPresented: $showDiscard) {
            Button("Discard Transcript", role: .destructive) { dismiss() }
            Button("Keep Reviewing", role: .cancel) {}
        }
        .onChange(of: scenePhase) { _, phase in
            // Permission sheets may briefly make the app inactive. Cancel a
            // pending start only on backgrounding, so a late permission grant
            // cannot begin microphone capture after the surfer has left Peak.
            if phase == .background { startTask?.cancel() }
            if phase != .active, recorder.state == .recording { recorder.finish() }
        }
        .onDisappear { startTask?.cancel(); recorder.cancel() }
    }
}
