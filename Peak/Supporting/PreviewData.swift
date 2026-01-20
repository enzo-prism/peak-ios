import Foundation
import SwiftData
import UIKit

enum PreviewData {
    static var container: ModelContainer = {
        let schema = Schema([SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        seed(context: context)
        return container
    }()

    static func seed(context: ModelContext) {
        let trestles = Spot(name: "Trestles")
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
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
            spot: longSpot,
            gear: [longBoard, wetsuit],
            buddies: [longBuddy],
            rating: 4,
            windCondition: .breezy,
            waveHeight: .shoulderHigh,
            notes: "Long walk, soft peaks, and a slow paddle out. Plenty of shoulder-high runners."
        )

        let session2 = SurfSession(
            date: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date(),
            spot: trestles,
            gear: [board, wetsuit, fins],
            buddies: [buddyA],
            rating: 5,
            windCondition: .calm,
            waveHeight: .overhead,
            notes: "Clean lines and glassy walls."
        )

        if let photoMedia = makeSamplePhotoMedia(createdAt: session2.date) {
            context.insert(photoMedia)
            session2.media.append(photoMedia)
        }

        if let videoMedia = makeSampleVideoMedia(createdAt: session2.date) {
            context.insert(videoMedia)
            session2.media.append(videoMedia)
        }

        let session3 = SurfSession(
            date: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            spot: oceanBeach,
            gear: [board, wetsuit],
            buddies: [buddyB],
            rating: 3,
            notes: "Windy but fun lefts."
        )

        let session4 = SurfSession(
            date: Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date(),
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
    }

    private static func makeSamplePhotoMedia(createdAt: Date) -> SessionMedia? {
        guard let photoData = makeSamplePhotoData() else { return nil }
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
        return image.jpegData(compressionQuality: 0.9)
    }

    private static func makeSampleVideoFileName() -> String? {
        let fileName = "preview-\(UUID().uuidString).mov"
        let url = SessionMediaStore.videoURL(for: fileName)
        do {
            try Data().write(to: url)
            return fileName
        } catch {
            return nil
        }
    }
}
