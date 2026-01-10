import Foundation
import SwiftData

enum PreviewData {
    static var container: ModelContainer = {
        let schema = Schema([SurfSession.self, Spot.self, Gear.self, Buddy.self])
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

        let board = Gear(name: "6'2\" Fish", kind: .board)
        let wetsuit = Gear(name: "3/2 Full", kind: .wetsuit)
        let fins = Gear(name: "Thruster", kind: .fins)

        let buddyA = Buddy(name: "Kai")
        let buddyB = Buddy(name: "Nora")

        context.insert(trestles)
        context.insert(oceanBeach)
        context.insert(mexPoint)
        context.insert(board)
        context.insert(wetsuit)
        context.insert(fins)
        context.insert(buddyA)
        context.insert(buddyB)

        let session1 = SurfSession(
            date: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date(),
            spot: trestles,
            gear: [board, wetsuit, fins],
            buddies: [buddyA],
            rating: 5,
            notes: "Clean lines and glassy walls."
        )

        let session2 = SurfSession(
            date: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            spot: oceanBeach,
            gear: [board, wetsuit],
            buddies: [buddyB],
            rating: 3,
            notes: "Windy but fun lefts."
        )

        let session3 = SurfSession(
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
    }
}
