import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A branded year-in-review card sized for sharing. Same rendering contract as
/// `SessionShareCard`: solid Theme tokens only (Liquid Glass does not rasterize
/// off-screen) and pinned to the dark scheme so the export looks identical
/// whatever appearance the surfer runs.
struct RecapShareCard: View {
    let review: YearInReview
    /// Pre-decoded highlight photos (decoded off the main thread by the renderer).
    let photos: [UIImage]

    /// Fixed layout width in points; the bitmap is this ×3 (Retina).
    static let width: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            details
        }
        .frame(width: Self.width, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.oceanMid, Theme.oceanDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            if photos.isEmpty {
                LinearGradient(
                    colors: [Theme.surfGreen.opacity(0.55), Theme.oceanDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: Self.width, height: 150)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 64, weight: .regular))
                        .foregroundStyle(Theme.foam.opacity(0.18))
                        .padding(20)
                }
            } else {
                photoStrip
                    .overlay(
                        LinearGradient(
                            colors: [.clear, Theme.oceanDeep.opacity(0.9)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(String(review.year)) in review")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.foam)
                Text("\(review.sessionCount) session\(review.sessionCount == 1 ? "" : "s") · \(hoursText)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.foam.opacity(0.75))
            }
            .padding(20)
        }
    }

    private var photoStrip: some View {
        HStack(spacing: 2) {
            ForEach(photos.prefix(3).indices, id: \.self) { index in
                Image(uiImage: photos[index])
                    .resizable()
                    .scaledToFill()
                    .frame(width: (Self.width - 4) / CGFloat(min(photos.count, 3)), height: 190)
                    .clipped()
            }
        }
        .frame(width: Self.width, height: 190)
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(statChips.indices, id: \.self) { index in
                    chip(statChips[index])
                }
            }

            footer
        }
        .padding(20)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.surfing")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.surfGreen)
            Text("PEAK")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Theme.foam)
                .tracking(2)
            Text("surf log")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.foam.opacity(0.6))
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func chip(_ item: RecapChip) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.foam.opacity(0.85))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.foam.opacity(0.55))
                Text(item.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.foam)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.foam.opacity(0.08))
        )
    }

    // MARK: Derived content

    private struct RecapChip {
        let icon: String
        let title: String
        let value: String
    }

    private var hoursText: String {
        review.totalMinutes > 0 ? StatsFormat.duration(review.totalMinutes) : "no time logged"
    }

    /// Only chips that have something true to say — a sparse year should read
    /// short, not padded out with dashes.
    private var statChips: [RecapChip] {
        var chips: [RecapChip] = []
        chips.append(RecapChip(icon: "calendar", title: "Surf days", value: "\(review.surfDays)"))
        if review.totalMinutes > 0 {
            chips.append(RecapChip(icon: "timer", title: "In water", value: StatsFormat.duration(review.totalMinutes)))
        }
        if let spot = review.topSpot {
            chips.append(RecapChip(icon: "mappin.and.ellipse", title: "Top spot", value: spot.name))
        }
        if let month = review.bestMonth {
            chips.append(RecapChip(
                icon: "chart.bar.fill",
                title: "Best month",
                value: month.month.formatted(.dateTime.month(.wide))
            ))
        }
        if let rating = review.averageRating {
            chips.append(RecapChip(icon: "star.fill", title: "Avg rating", value: "\(StatsFormat.rating(rating))★"))
        }
        if review.longestWeekStreak > 0 {
            chips.append(RecapChip(
                icon: "flame.fill",
                title: "Longest streak",
                value: StatsFormat.spokenWeeks(review.longestWeekStreak)
            ))
        }
        return Array(chips.prefix(6))
    }

    /// One-line caption shared alongside the image.
    var caption: String {
        let sessions = "\(review.sessionCount) session\(review.sessionCount == 1 ? "" : "s")"
        if review.totalMinutes > 0 {
            return "My \(String(review.year)) in the water: \(sessions), \(StatsFormat.duration(review.totalMinutes)). Logged with Peak."
        }
        return "My \(String(review.year)) in the water: \(sessions). Logged with Peak."
    }
}

/// The payload a recap `ShareLink` exports: PNG plus a text caption, mirroring
/// `SessionShareContent`.
struct RecapShareContent: Transferable {
    let image: UIImage
    let caption: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { content in
            content.image.pngData() ?? Data()
        }
        .suggestedFileName("peak-year-in-review.png")

        ProxyRepresentation(exporting: \.caption)
    }
}

/// Renders `RecapShareCard` to a shareable payload. Photo decode happens off
/// the main thread; the `ImageRenderer` pass runs on the main actor at scale 3.
enum RecapShareCardRenderer {
    @MainActor
    static func makeContent(review: YearInReview, media: [SessionMedia]) async -> RecapShareContent? {
        let photoData = media
            .prefix(3)
            .compactMap { $0.photoData ?? $0.thumbnailData }

        let photos: [UIImage] = await Task.detached(priority: .userInitiated) {
            photoData.compactMap { data in
                guard let image = UIImage(data: data) else { return nil }
                return image.preparingForDisplay() ?? image
            }
        }.value

        let card = RecapShareCard(review: review, photos: photos)

        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .large))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return RecapShareContent(image: uiImage, caption: card.caption)
    }
}

#Preview {
    RecapShareCard(
        review: YearInReview(
            year: 2026,
            sessionCount: 48,
            surfDays: 41,
            totalMinutes: 4_320,
            averageRating: 3.9,
            topSpot: YearInReviewLeader(name: "Trestles", count: 14),
            topGear: YearInReviewLeader(name: "6'2\" Fish", count: 22),
            bestMonth: YearInReviewMonth(month: Date(), count: 9),
            longestWeekStreak: 7,
            waveHeightDistribution: []
        ),
        photos: []
    )
    .padding()
    .background(Theme.background)
}
