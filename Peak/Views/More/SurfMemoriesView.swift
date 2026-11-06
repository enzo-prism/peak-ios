import SwiftData
import SwiftUI

struct SurfMemoriesView: View {
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot])) private var sessions: [SurfSession]
    @State private var spotName = ""
    @State private var month: Date?
    private var months: [Date] {
        Set(sessions.compactMap { Calendar.current.dateInterval(of: .month, for: $0.date)?.start }).sorted(by: >)
    }
    private var selected: [SurfSession] {
        sessions.filter { session in
            (spotName.isEmpty || session.spot?.name == spotName)
                && (month == nil || Calendar.current.isDate(session.date, equalTo: month!, toGranularity: .month))
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Your sessions, photos and notes, together. Choose a month or spot to revisit a trip.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                Picker("Month", selection: $month) {
                    Text("All months").tag(nil as Date?)
                    ForEach(months, id: \.self) { Text($0.formatted(.dateTime.month(.wide).year())).tag(Optional($0)) }
                }
                Picker("Spot", selection: $spotName) {
                    Text("All spots").tag("")
                    ForEach(Set(sessions.compactMap { $0.spot?.name }).sorted(), id: \.self) { Text($0).tag($0) }
                }
                if selected.isEmpty {
                    ContentUnavailableView("No memories in this selection", systemImage: "photo.on.rectangle")
                }
                ForEach(selected) { session in
                    Button {
                        PeakNavigationCoordinator.shared.handle(.session(id: SessionIntentQueries.identifier(for: session)))
                    } label: {
                        memory(session).contentShape(Rectangle())
                    }
                    .buttonStyle(PressFeedbackButtonStyle())
                    .accessibilityIdentifier("memories.session.\(session.id)")
                }
            }
            .padding()
            .readableContentWidth()
        }
        .background(Theme.background)
        .navigationTitle("Surf Memories")
        .accessibilityIdentifier("memories.list")
    }

    private func memory(_ session: SurfSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let media = session.media.sorted(by: { $0.sortIndex < $1.sortIndex }).first {
                SessionMediaThumbnailView(imageData: media.thumbnailData ?? media.photoData,
                    isVideo: media.kind == .video, crop: media.cropRect)
                    .frame(height: 200).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .accessibilityHidden(true)
            }
            Text(session.spot?.name ?? "Surf session").font(.headline)
            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(Theme.textSecondary)
            if let note = session.notes.trimmedNonEmpty { Text(note).font(.subheadline).lineLimit(4) }
            if !session.gear.isEmpty { Text(session.gear.map(\.name).sorted().joined(separator: " · ")).font(.caption) }
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.section, tint: Theme.glassDimTint)
    }
}
