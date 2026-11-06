import Foundation
import WatchConnectivity

/// Fallback delivery of end-of-session facts to the iPhone.
///
/// `transferFile` is chosen over `sendMessage` and `updateApplicationContext`
/// deliberately:
///
/// - `sendMessage` requires the counterpart app to be reachable *right now*.
///   The surfer's phone is in a car, a locker, or a dry bag; reachable is the
///   exception, not the rule.
/// - `updateApplicationContext` keeps only the latest value, so two sessions
///   surfed back to back before the phone reconnects would collapse into one.
/// - `transferFile` is queued, persisted across launches, and retried by the
///   system until it lands. Sessions are rare and small; latency is irrelevant
///   and reliability is everything.
///
/// Nothing here is load-bearing. If every transfer fails forever, the surfer
/// still has the workout in HealthKit, which is the path the phone actually
/// mines for wave stats. This carries a small hint after a mirror interruption.
@MainActor
final class WatchConnectivityRelay: NSObject {
    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    override init() {
        super.init()
        activate()
    }

    private func activate() {
        guard let session else { return }
        session.delegate = self
        // Activating repeatedly is harmless and simpler than tracking state:
        // WCSession ignores the call once it is already activated.
        session.activate()
    }

    /// Writes the payload to a temporary file and queues it for transfer.
    ///
    /// The file is not cleaned up here — WatchConnectivity owns it until the
    /// transfer completes. The completion delegate removes it after delivery.
    func send(_ handoff: SurfSessionHandoff) {
        guard let session else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(handoff) else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(handoff.transferFileName)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }

        session.transferFile(
            url,
            metadata: [SurfSessionHandoff.metadataKindKey: SurfSessionHandoff.metadataKind]
        )
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityRelay: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        // Failed transfers can be retried from Health import; retain no stale payload.
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Nothing to do: transfers queued before activation completes are held
        // by the system and sent once the session is live.
    }
}
