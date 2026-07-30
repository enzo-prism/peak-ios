import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A compact, branded card summarizing one surf session, sized for sharing to
/// Messages / social. Rendered off-screen to a bitmap via `ImageRenderer`
/// (see `SessionShareCardRenderer`), so it uses only solid Theme tokens (no
/// Liquid Glass, which does not rasterize off-screen) and is pinned to the dark
/// scheme for a deterministic, premium look regardless of the user's appearance.
struct SessionShareCard: View {
    let session: SurfSession
    /// Pre-decoded first photo (decoded off the main thread by the renderer).
    let photo: UIImage?

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
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.width, height: 210)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.clear, Theme.oceanDeep.opacity(0.85)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
            } else {
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
            }

            VStack(alignment: .leading, spacing: 6) {
                if session.rating > 0 {
                    ratingStars(session.rating)
                }
                Text(session.spot?.name ?? "Unknown spot")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.foam)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(session.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.foam.opacity(0.75))
            }
            .padding(20)
        }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let wave = waveHeightText {
                HStack(spacing: 10) {
                    Image(systemName: "water.waves")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.surfGreen)
                    Text(wave)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.foam)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
            }

            if !conditionChips.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(conditionChips.indices, id: \.self) { index in
                        chip(conditionChips[index])
                    }
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

    private func chip(_ item: ConditionChip) -> some View {
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

    private func ratingStars(_ rating: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(value <= rating ? Theme.surfGreen : Theme.foam.opacity(0.35))
            }
        }
    }

    // MARK: Derived content

    private var waveHeightText: String? {
        let category = session.waveHeight?.label
        let precise = session.waveHeightMeters.map { SurfConditionsFormatter.meters($0) }
        switch (category, precise) {
        case let (cat?, m?): return "\(cat) · \(m)"
        case let (cat?, nil): return cat
        case let (nil, m?): return m
        default: return nil
        }
    }

    private struct ConditionChip {
        let icon: String
        let title: String
        let value: String
    }

    private var conditionChips: [ConditionChip] {
        var chips: [ConditionChip] = []
        if let duration = session.durationMinutes {
            chips.append(ConditionChip(icon: "timer", title: "Duration", value: SessionDurationFormatter.string(from: duration)))
        }
        if let wind = session.windCondition?.label {
            chips.append(ConditionChip(icon: "wind", title: "Wind", value: wind))
        } else if let windSpeed = session.windSpeedKph {
            chips.append(ConditionChip(icon: "wind", title: "Wind", value: SurfConditionsFormatter.speed(windSpeed)))
        }
        // Waves rank above water temperature: it is the number the surfer is
        // actually sharing. Estimated or not, it is their own logged figure by
        // the time a card is generated.
        if let waves = session.waveCount {
            chips.append(ConditionChip(icon: "water.waves", title: "Waves", value: "\(waves)"))
        }
        if let temp = session.seaSurfaceTemperatureC {
            chips.append(ConditionChip(icon: "thermometer.medium", title: "Water", value: SurfConditionsFormatter.temperature(temp)))
        }
        if let period = session.swellWavePeriodSeconds {
            chips.append(ConditionChip(icon: "timelapse", title: "Swell period", value: SurfConditionsFormatter.period(period)))
        }
        return Array(chips.prefix(4))
    }

    /// One-line caption shared alongside the image.
    var caption: String {
        let spot = session.spot?.name ?? "a surf session"
        let date = session.date.formatted(.dateTime.month(.abbreviated).day().year())
        if let wave = waveHeightText {
            return "\(spot) — \(date) · \(wave). Logged with Peak."
        }
        return "\(spot) — \(date). Logged with Peak."
    }
}

/// The payload a `ShareLink` exports: the rendered card as a PNG plus a
/// one-line text caption, so image-first targets (Photos, Instagram) get the
/// bitmap and text-first targets (Messages, Notes) get the caption.
struct SessionShareContent: Transferable {
    let image: UIImage
    let caption: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { content in
            content.image.pngData() ?? Data()
        }
        .suggestedFileName("peak-session.png")

        ProxyRepresentation(exporting: \.caption)
    }
}

/// Renders `SessionShareCard` to a shareable payload. Photo decode happens off
/// the main thread; the `ImageRenderer` pass runs on the main actor at scale 3.
enum SessionShareCardRenderer {
    @MainActor
    static func makeContent(for session: SurfSession) async -> SessionShareContent? {
        let firstMediaData = session.media
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
            .first
            .flatMap { $0.photoData ?? $0.thumbnailData }

        let photo: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let firstMediaData, let image = UIImage(data: firstMediaData) else { return nil }
            return image.preparingForDisplay() ?? image
        }.value

        let card = SessionShareCard(session: session, photo: photo)

        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .large))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return SessionShareContent(image: uiImage, caption: card.caption)
    }
}

#Preview {
    SessionShareCard(
        session: SurfSession(
            date: Date(),
            spot: Spot(name: "Trestles"),
            rating: 4,
            durationMinutes: 90,
            windCondition: .breezy,
            waveHeight: .shoulderHigh,
            waveHeightMeters: 1.2,
            seaSurfaceTemperatureC: 17,
            notes: "Fun peaks."
        ),
        photo: nil
    )
    .padding()
    .background(Theme.background)
}
