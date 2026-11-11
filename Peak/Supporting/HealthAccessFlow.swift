import Foundation

enum HealthAccessFlow {
    /// A failed request preserves the old preference. Success means the sheet was
    /// completed, never that read access was granted.
    @MainActor static func enable(request: () async throws -> Void,
                                 setEnabled: (Bool) -> Void) async throws {
        try await request()
        setEnabled(true)
    }
}
