import Foundation
import SwiftData

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
            notes: "Long walk, soft peaks, and a slow paddle out. Plenty of shoulder-high runners."
        )

        let session2 = SurfSession(
            date: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date(),
            spot: trestles,
            gear: [board, wetsuit, fins],
            buddies: [buddyA],
            rating: 5,
            notes: "Clean lines and glassy walls."
        )

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
}
