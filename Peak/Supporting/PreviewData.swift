import Foundation
import SwiftData
import UIKit

enum PreviewData {
    private static let fallbackPhotoBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII="
    private static let fallbackPhotoData = Data(base64Encoded: fallbackPhotoBase64)
    static var container: ModelContainer = {
        let schema = Schema([SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        seed(context: context, baseDate: TestingDefaults.fixedSeedDate ?? Date())
        return container
    }()

    static func seed(context: ModelContext, baseDate: Date = Date()) {
        let trestles = Spot(
            name: "Trestles",
            locationName: "Trestles, California, United States",
            latitude: 33.3842,
            longitude: -117.592
        )
        let oceanBeach = Spot(name: "Ocean Beach")
        let mexPoint = Spot(name: "Point Break")
        let longSpot = Spot(
            name: "San Onofre State Beach - Old Man's",
            locationName: "San Clemente, California, United States"
        )

        let board = Gear(name: "6'2\" Fish", kind: .board)
        let wetsuit = Gear(name: "3/2 Full", kind: .wetsuit)
        let fins = Gear(name: "Thruster", kind: .fins)
        let longBoard = Gear(
            name: "7'4\" Midlength Performance Egg",
            kind: .board,
            brand: "Pearson Arrow",
            model: "Modern Egg",
            size: "7'4\"",
            volumeLiters: 50.5,
            notes: "Single to double, paddles fast and holds a high line."
        )

        let buddyA = Buddy(name: "Kai")
        let buddyB = Buddy(name: "Nora")
        let longBuddy = Buddy(name: "Christopher \"Big Tuna\" Alvarez")

        context.insert(trestles)
        context.insert(oceanBeach)
        context.insert(mexPoint)
        context.insert(longSpot)
        context.insert(board)
        context.insert(wetsuit)
        context.insert(fins)
        context.insert(longBoard)
        context.insert(buddyA)
        context.insert(buddyB)
        context.insert(longBuddy)

        let session1 = SurfSession(
            date: Calendar.current.date(byAdding: .day, value: -1, to: baseDate) ?? baseDate,
            spot: longSpot,
            gear: [longBoard, wetsuit],
            buddies: [longBuddy],
            rating: 4,
            windCondition: .breezy,
            waveHeight: .shoulderHigh,
            notes: "Long walk, soft peaks, and a slow paddle out. Plenty of shoulder-high runners."
        )

        let session2 = SurfSession(
            date: Calendar.current.date(byAdding: .day, value: -2, to: baseDate) ?? baseDate,
            spot: trestles,
            gear: [board, wetsuit, fins],
            buddies: [buddyA],
            rating: 5,
            windCondition: .calm,
            waveHeight: .overhead,
            notes: "Clean lines and glassy walls."
        )
        session2.windSpeedKph = 8
        session2.windDirectionDegrees = 280
        session2.waveHeightMeters = 1.7
        session2.swellWaveHeightMeters = 1.2
        session2.swellWavePeriodSeconds = 12
        session2.swellWaveDirectionDegrees = 265
        session2.windWaveHeightMeters = 0.6
        session2.windWavePeriodSeconds = 6
        session2.windWaveDirectionDegrees = 300
        session2.seaSurfaceTemperatureC = 17.5
        session2.conditionsSource = "Open-Meteo"
        session2.conditionsFetchedAt = baseDate

        if let photoMedia = makeSamplePhotoMedia(createdAt: session2.date) {
            photoMedia.sortIndex = 0
            context.insert(photoMedia)
            session2.media.append(photoMedia)
        }

        if let videoMedia = makeSampleVideoMedia(createdAt: session2.date) {
            videoMedia.sortIndex = 1
            context.insert(videoMedia)
            session2.media.append(videoMedia)
        }

        let session3 = SurfSession(
            date: Calendar.current.date(byAdding: .day, value: -7, to: baseDate) ?? baseDate,
            spot: oceanBeach,
            gear: [board, wetsuit],
            buddies: [buddyB],
            rating: 3,
            notes: "Windy but fun lefts."
        )

        let session4 = SurfSession(
            date: Calendar.current.date(byAdding: .day, value: -14, to: baseDate) ?? baseDate,
            spot: mexPoint,
            gear: [board, fins],
            buddies: [buddyA, buddyB],
            rating: 4,
            notes: "Long paddle, worth it."
        )

        context.insert(session1)
        context.insert(session2)
        context.insert(session3)
        context.insert(session4)

        // Gated on the UI-test scenario so it never costs a real launch anything:
        // the Best Window card needs a real logbook before it can honestly say
        // anything, and the default four sessions are (correctly) not enough.
        if TestingDefaults.windowScenario?.lowercased() == "confident" {
            for session in windowHistory(at: trestles, baseDate: baseDate) {
                context.insert(session)
            }
        }
    }

    /// A believable logbook at one spot: dawn glass rated well, blown-out
    /// afternoons rated poorly, with the same swell running through both.
    ///
    /// Shared with `TodayWindowServiceTests`, which runs this exact history against
    /// the exact mock forecast the UI test sees and asserts the pair really does
    /// clear the confidence gate. Without that, a UI test asserting "a window
    /// appears" could quietly become a test of nothing.
    static func windowHistory(at spot: Spot, baseDate: Date) -> [SurfSession] {
        // Deterministic pseudo-random jitter: a fixed table, not a RNG, so the
        // seeded store is byte-identical on every launch.
        let jitter: [Double] = [0.00, 0.07, -0.05, 0.03, -0.08, 0.05, -0.02, 0.09]

        return (0..<32).map { index in
            let isClean = index % 2 == 0
            let wobble = jitter[index % jitter.count]
            let session = SurfSession(
                date: Calendar.current.date(byAdding: .day, value: -(index + 3) * 4, to: baseDate) ?? baseDate,
                spot: spot,
                // Ratings must vary, or the history carries no signal at all and
                // confidence is zero however many sessions there are.
                rating: isClean ? (index % 4 == 0 ? 5 : 4) : (index % 4 == 1 ? 1 : 2)
            )
            session.swellWaveHeightMeters = 1.2 + wobble
            session.swellWavePeriodSeconds = 12 + wobble * 4
            session.swellWaveDirectionDegrees = 268 + wobble * 10
            session.waveHeightMeters = 1.25 + wobble
            session.seaSurfaceTemperatureC = 17.5 + wobble
            session.seaLevelHeightM = isClean ? 0.35 + wobble : -0.4 + wobble
            session.tide = isClean ? .falling : .rising
            if isClean {
                session.windSpeedKph = 5 + wobble * 6
                session.windDirectionDegrees = 42 + wobble * 20
                session.windWaveHeightMeters = 0.12 + wobble * 0.2
            } else {
                session.windSpeedKph = 27 + wobble * 8
                session.windDirectionDegrees = 215 + wobble * 20
                session.windWaveHeightMeters = 0.55 + wobble * 0.3
            }
            session.conditionsSource = "Open-Meteo"
            session.conditionsFetchedAt = session.date
            return session
        }
    }

    private static func makeSamplePhotoMedia(createdAt: Date) -> SessionMedia? {
        let photoData = makeSamplePhotoData()
            ?? fallbackPhotoData
            ?? UIImage(systemName: "photo")?.pngData()
            ?? Data()
        let thumbnailData = SessionMediaStore.thumbnailData(from: photoData)
        return SessionMedia(
            kind: .photo,
            photoData: photoData,
            thumbnailData: thumbnailData,
            createdAt: createdAt
        )
    }

    private static func makeSampleVideoMedia(createdAt: Date) -> SessionMedia? {
        guard let fileName = makeSampleVideoFileName() else { return nil }
        let thumbnailData = makeSamplePhotoData().flatMap { SessionMediaStore.thumbnailData(from: $0) }
        return SessionMedia(
            kind: .video,
            thumbnailData: thumbnailData,
            videoFileName: fileName,
            createdAt: createdAt
        )
    }

    private static func makeSamplePhotoData() -> Data? {
        // UI tests use the cheap blank fallback for speed/determinism, except during
        // marketing screenshot capture, where we want real sample imagery on screen.
        if TestingDefaults.isUITest && !TestingDefaults.isScreenshotCapture {
            return fallbackPhotoData
        }
        let size = CGSize(width: 1200, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let colors = [
                UIColor(red: 0.04, green: 0.1, blue: 0.18, alpha: 1).cgColor,
                UIColor(red: 0.12, green: 0.62, blue: 0.46, alpha: 1).cgColor
            ]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            )
            if let gradient {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            context.cgContext.setStrokeColor(UIColor(white: 1, alpha: 0.28).cgColor)
            context.cgContext.setLineWidth(10)
            context.cgContext.move(to: CGPoint(x: 0, y: size.height * 0.62))
            context.cgContext.addCurve(
                to: CGPoint(x: size.width, y: size.height * 0.42),
                control1: CGPoint(x: size.width * 0.25, y: size.height * 0.48),
                control2: CGPoint(x: size.width * 0.75, y: size.height * 0.76)
            )
            context.cgContext.strokePath()
        }
        if let data = image.jpegData(compressionQuality: 0.9) {
            return data
        }
        return fallbackPhotoData ?? UIImage(systemName: "photo")?.pngData()
    }

    private static func makeSampleVideoFileName() -> String? {
        let fileName = "preview-\(UUID().uuidString).mov"
        let url = SessionMediaStore.videoURL(for: fileName)
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let data = Data([0x0, 0x0, 0x0, 0x0])
        do {
            try data.write(to: url, options: .atomic)
            return fileName
        } catch {
            if FileManager.default.createFile(atPath: url.path, contents: data) {
                return fileName
            }
            return nil
        }
    }
}
