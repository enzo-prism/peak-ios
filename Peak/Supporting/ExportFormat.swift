import Foundation
import SwiftData

nonisolated struct PeakExport: Codable {
    let schemaVersion: String
    let exportedAt: String
    let sessions: [SessionExport]
    let spots: [SpotExport]
    let gear: [GearExport]
    let buddies: [BuddyExport]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case exportedAt = "exported_at"
        case sessions
        case spots
        case gear
        case buddies
    }
}

nonisolated struct SessionExport: Codable {
    let id: String
    let date: String
    let spotId: String?
    let spotName: String?
    let rating: Int
    let durationMinutes: Int?
    let notes: String
    let buddyIds: [String]
    let gearIds: [String]
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case spotId = "spot_id"
        case spotName = "spot_name"
        case rating
        case durationMinutes = "duration_minutes"
        case notes
        case buddyIds = "buddy_ids"
        case gearIds = "gear_ids"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct SpotExport: Codable {
    let id: String
    let name: String
    let locationName: String?
    let latitude: Double?
    let longitude: Double?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case locationName = "location_name"
        case latitude
        case longitude
        case createdAt = "created_at"
    }
}

nonisolated struct GearExport: Codable {
    let id: String
    let name: String
    let kind: String
    let brand: String?
    let model: String?
    let size: String?
    let volumeLiters: Double?
    let notes: String?
    let photoData: String?
    let isArchived: Bool?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case brand
        case model
        case size
        case volumeLiters = "volume_liters"
        case notes
        case photoData = "photo_data"
        case isArchived = "is_archived"
        case createdAt = "created_at"
    }
}

nonisolated struct BuddyExport: Codable {
    let id: String
    let name: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
    }
}

enum ImportMode {
    case merge
    case replace
}

enum PeakExportManager {
    static let schemaVersion = "peak_export_v1"

    static func makeExport(
        sessions: [SurfSession],
        spots: [Spot],
        gear: [Gear],
        buddies: [Buddy],
        now: Date = Date()
    ) -> PeakExport {
        let exportedAt = ExportDateFormatter.string(from: now)
        let spotExports = spots.sorted { $0.name < $1.name }.map { spot in
            SpotExport(
                id: spot.key,
                name: spot.name,
                locationName: spot.locationName,
                latitude: spot.latitude,
                longitude: spot.longitude,
                createdAt: ExportDateFormatter.string(from: spot.createdAt)
            )
        }
        let gearExports = gear.sorted { $0.name < $1.name }.map { item in
            GearExport(
                id: item.key,
                name: item.name,
                kind: item.kind.rawValue,
                brand: item.brand,
                model: item.model,
                size: item.size,
                volumeLiters: item.volumeLiters,
                notes: item.notes,
                photoData: item.photoData?.base64EncodedString(),
                isArchived: item.isArchived,
                createdAt: ExportDateFormatter.string(from: item.createdAt)
            )
        }
        let buddyExports = buddies.sorted { $0.name < $1.name }.map { buddy in
            BuddyExport(
                id: buddy.key,
                name: buddy.name,
                createdAt: ExportDateFormatter.string(from: buddy.createdAt)
            )
        }
        let sessionExports = sessions.sorted { $0.createdAt < $1.createdAt }.map { session in
            SessionExport(
                id: ExportDateFormatter.string(from: session.createdAt),
                date: ExportDateFormatter.string(from: session.date),
                spotId: session.spot?.key,
                spotName: session.spot?.name,
                rating: session.rating,
                durationMinutes: session.durationMinutes,
                notes: session.notes,
                buddyIds: session.buddies.map(\.key),
                gearIds: session.gear.map(\.key),
                createdAt: ExportDateFormatter.string(from: session.createdAt),
                updatedAt: ExportDateFormatter.string(from: session.updatedAt)
            )
        }

        return PeakExport(
            schemaVersion: schemaVersion,
            exportedAt: exportedAt,
            sessions: sessionExports,
            spots: spotExports,
            gear: gearExports,
            buddies: buddyExports
        )
    }

    nonisolated static func jsonData(from export: PeakExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    nonisolated static func decodeJSON(_ data: Data) throws -> PeakExport {
        let decoder = JSONDecoder()
        return try decoder.decode(PeakExport.self, from: data)
    }

    static func exportJSONFile(
        sessions: [SurfSession],
        spots: [Spot],
        gear: [Gear],
        buddies: [Buddy]
    ) throws -> URL {
        let export = makeExport(sessions: sessions, spots: spots, gear: gear, buddies: buddies)
        return try exportJSONFile(from: export)
    }

    nonisolated static func exportJSONFile(from export: PeakExport) throws -> URL {
        let data = try jsonData(from: export)
        let url = exportURL(prefix: "Peak-Export", fileExtension: "json")
        try data.write(to: url, options: [.atomic])
        return url
    }

    static func exportCSVFile(sessions: [SurfSession]) throws -> URL {
        let csv = sessionsCSV(sessions: sessions)
        let url = exportURL(prefix: "Peak-Sessions", fileExtension: "csv")
        guard let data = csv.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        try data.write(to: url, options: [.atomic])
        return url
    }

    nonisolated static func exportCSVFile(from export: PeakExport) throws -> URL {
        let csv = sessionsCSV(export: export)
        let url = exportURL(prefix: "Peak-Sessions", fileExtension: "csv")
        guard let data = csv.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        try data.write(to: url, options: [.atomic])
        return url
    }

    static func sessionsCSV(sessions: [SurfSession]) -> String {
        var rows = ["id,date,spotName,rating,notes,buddyNames,gearSummary"]
        for session in sessions {
            let id = ExportDateFormatter.string(from: session.createdAt)
            let date = ExportDateFormatter.string(from: session.date)
            let spotName = session.spot?.name ?? ""
            let rating = "\(session.rating)"
            let notes = session.notes
            let buddyNames = session.buddies.map(\.name).joined(separator: ", ")
            let gearSummary = session.gear.map { "\($0.name) (\($0.kind.label))" }.joined(separator: ", ")

            let row = [
                id,
                date,
                spotName,
                rating,
                notes,
                buddyNames,
                gearSummary
            ].map(csvEscape).joined(separator: ",")
            rows.append(row)
        }
        return rows.joined(separator: "\n")
    }

    nonisolated static func sessionsCSV(export: PeakExport) -> String {
        var rows = ["id,date,spotName,rating,notes,buddyNames,gearSummary"]
        let spotLookup = Dictionary(uniqueKeysWithValues: export.spots.map { ($0.id, $0.name) })
        let gearLookup = Dictionary(uniqueKeysWithValues: export.gear.map { ($0.id, $0) })
        let buddyLookup = Dictionary(uniqueKeysWithValues: export.buddies.map { ($0.id, $0.name) })

        for session in export.sessions {
            let spotName = session.spotName ?? (session.spotId.flatMap { spotLookup[$0] } ?? "")
            let buddyNames = session.buddyIds.compactMap { buddyLookup[$0] }.joined(separator: ", ")
            let gearSummary = session.gearIds.compactMap { id -> String? in
                guard let gear = gearLookup[id] else { return nil }
                let kindLabel = GearKind(rawValue: gear.kind)?.label ?? gear.kind
                return "\(gear.name) (\(kindLabel))"
            }.joined(separator: ", ")

            let row = [
                session.id,
                session.date,
                spotName,
                "\(session.rating)",
                session.notes,
                buddyNames,
                gearSummary
            ].map(csvEscape).joined(separator: ",")
            rows.append(row)
        }

        return rows.joined(separator: "\n")
    }

    static func applyImport(
        _ export: PeakExport,
        mode: ImportMode,
        context: ModelContext
    ) throws {
        guard export.schemaVersion == schemaVersion else {
            throw ExportError.unsupportedSchema
        }
        if mode == .replace {
            try context.resetAllData()
        }

        var spotById: [String: Spot] = [:]
        for spotExport in export.spots {
            let createdAt = ExportDateFormatter.date(from: spotExport.createdAt) ?? Date()
            if let existing = context.existingSpot(named: spotExport.name) {
                existing.name = spotExport.name
                existing.key = Spot.makeKey(from: spotExport.name)
                existing.locationName = spotExport.locationName
                existing.latitude = spotExport.latitude
                existing.longitude = spotExport.longitude
                existing.createdAt = createdAt
                spotById[spotExport.id] = existing
            } else {
                let spot = Spot(
                    name: spotExport.name,
                    locationName: spotExport.locationName,
                    latitude: spotExport.latitude,
                    longitude: spotExport.longitude,
                    createdAt: createdAt
                )
                context.insert(spot)
                spotById[spotExport.id] = spot
            }
        }

        var gearById: [String: Gear] = [:]
        for gearExport in export.gear {
            let kind = GearKind(rawValue: gearExport.kind) ?? .other
            let createdAt = ExportDateFormatter.date(from: gearExport.createdAt) ?? Date()
            let photoData = gearExport.photoData.flatMap { Data(base64Encoded: $0) }
            let isArchived = gearExport.isArchived ?? false
            if let existing = context.existingGear(named: gearExport.name, kind: kind) {
                existing.name = gearExport.name
                existing.kind = kind
                existing.key = Gear.makeKey(name: gearExport.name, kind: kind)
                existing.brand = gearExport.brand
                existing.model = gearExport.model
                existing.size = gearExport.size
                existing.volumeLiters = gearExport.volumeLiters
                existing.notes = gearExport.notes
                existing.photoData = photoData
                existing.isArchived = isArchived
                existing.createdAt = createdAt
                gearById[gearExport.id] = existing
            } else {
                let gear = Gear(
                    name: gearExport.name,
                    kind: kind,
                    brand: gearExport.brand,
                    model: gearExport.model,
                    size: gearExport.size,
                    volumeLiters: gearExport.volumeLiters,
                    notes: gearExport.notes,
                    photoData: photoData,
                    isArchived: isArchived,
                    createdAt: createdAt
                )
                context.insert(gear)
                gearById[gearExport.id] = gear
            }
        }

        var buddyById: [String: Buddy] = [:]
        for buddyExport in export.buddies {
            let createdAt = ExportDateFormatter.date(from: buddyExport.createdAt) ?? Date()
            if let existing = context.existingBuddy(named: buddyExport.name) {
                existing.name = buddyExport.name
                existing.key = Buddy.makeKey(from: buddyExport.name)
                existing.createdAt = createdAt
                buddyById[buddyExport.id] = existing
            } else {
                let buddy = Buddy(name: buddyExport.name, createdAt: createdAt)
                context.insert(buddy)
                buddyById[buddyExport.id] = buddy
            }
        }

        for sessionExport in export.sessions {
            guard let createdAt = ExportDateFormatter.date(from: sessionExport.createdAt) else { continue }
            let existingSession = context.existingSession(createdAt: createdAt)
            let session = existingSession ?? SurfSession(
                date: Date(),
                spot: nil,
                createdAt: createdAt,
                updatedAt: createdAt
            )

            session.date = ExportDateFormatter.date(from: sessionExport.date) ?? session.date
            session.rating = sessionExport.rating
            session.durationMinutes = SurfSession.normalizedDuration(sessionExport.durationMinutes)
            session.notes = sessionExport.notes
            session.createdAt = createdAt
            session.updatedAt = ExportDateFormatter.date(from: sessionExport.updatedAt) ?? createdAt

            if let spotId = sessionExport.spotId, let spot = spotById[spotId] {
                session.spot = spot
            } else if let spotName = sessionExport.spotName {
                session.spot = context.upsertSpot(named: spotName)
            }

            session.gear = sessionExport.gearIds.compactMap { gearById[$0] }
            session.buddies = sessionExport.buddyIds.compactMap { buddyById[$0] }

            if existingSession == nil {
                context.insert(session)
            }
        }
    }

    nonisolated private static func exportURL(prefix: String, fileExtension: String) -> URL {
        let timestamp = ExportDateFormatter.fileSafeString(from: Date())
        let filename = "\(prefix)-\(timestamp).\(fileExtension)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    nonisolated private static func csvEscape(_ value: String) -> String {
        let needsEscaping = value.contains(",") || value.contains("\"") || value.contains("\n")
        if needsEscaping {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

enum ExportError: Error {
    case encodingFailed
    case unsupportedSchema
}

enum ExportDateFormatter {
    nonisolated private static func iso8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    nonisolated static func string(from date: Date) -> String {
        iso8601Formatter().string(from: date)
    }

    nonisolated static func date(from string: String) -> Date? {
        iso8601Formatter().date(from: string)
    }

    nonisolated static func fileSafeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
