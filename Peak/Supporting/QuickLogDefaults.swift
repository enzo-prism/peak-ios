import Foundation
import SwiftData

/// The guesses a new session starts with, so a repeat log is "check, rate,
/// save" rather than rebuilding the same setup every time.
///
/// Only the *setup* is ever guessed — where you surfed and what you rode.
/// Conditions, rating and notes describe one particular session, so they are
/// never carried from another one: a copied swell reading would be a stale
/// number presented as today's (AGENTS.md → Honesty about derived numbers).
///
/// Every function takes `sessions` newest-first, as the editor's query sorts them.
enum QuickLogDefaults {
    /// Presets for the "time in water" chips. Minutes, all on the editor's
    /// 5-minute step and inside `SurfSession.maxDurationMinutes`.
    static let durationPresets = [60, 90, 120, 180]

    /// The spot of the most recent session that has one. Imported Watch surfs
    /// can land without a spot; those are skipped rather than suggesting nothing.
    static func suggestedSpot(sessions: [SurfSession]) -> Spot? {
        sessions.lazy.compactMap(\.spot).first
    }

    /// Gear from the most recent session *at this spot* that logged any —
    /// boards follow breaks — falling back to the most recent setup anywhere.
    /// Archived gear is never suggested.
    static func suggestedGear(for spot: Spot?, sessions: [SurfSession]) -> [Gear] {
        if let spot {
            let atSpot = sessions.first { session in
                session.spot?.persistentModelID == spot.persistentModelID && !activeGear(session).isEmpty
            }
            if let atSpot {
                return activeGear(atSpot)
            }
        }
        for session in sessions {
            let gear = activeGear(session)
            if !gear.isEmpty { return gear }
        }
        return []
    }

    /// Fills whatever a new draft is missing from history. A spot the draft
    /// already carries (timer, nearest spot to a Watch route) wins, and so does
    /// a typed spot name with no library match. Returns true if anything changed.
    @discardableResult
    static func apply(to draft: inout SessionDraft, sessions: [SurfSession]) -> Bool {
        var changed = false
        if draft.selectedSpot == nil,
           draft.spotName.trimmedNonEmpty == nil,
           let spot = suggestedSpot(sessions: sessions) {
            draft.selectSpot(spot)
            changed = true
        }
        if draft.selectedGear.isEmpty {
            let gear = suggestedGear(for: draft.selectedSpot, sessions: sessions)
            if !gear.isEmpty {
                draft.selectedGear = gear
                draft.gearIsSuggested = true
                changed = true
            }
        }
        return changed
    }

    /// Keeps a suggested setup in step with the spot: switching from Trestles
    /// to Ocean Beach swaps in what was ridden at Ocean Beach last time. Gear
    /// the surfer picked by hand is left alone. Returns true if anything changed.
    @discardableResult
    static func spotDidChange(in draft: inout SessionDraft, sessions: [SurfSession]) -> Bool {
        guard draft.gearIsSuggested, let spot = draft.selectedSpot else { return false }
        let gear = suggestedGear(for: spot, sessions: sessions)
        // Relationship arrays carry no order, so compare as sets.
        guard !gear.isEmpty,
              Set(gear.map(\.persistentModelID)) != Set(draft.selectedGear.map(\.persistentModelID)) else { return false }
        draft.selectedGear = gear
        return true
    }

    /// "Same setup as last session": spot, gear and buddies — never the
    /// conditions, rating, notes or media, which belonged to that day.
    static func applySameSetup(from session: SurfSession, to draft: inout SessionDraft) {
        if let spot = session.spot {
            draft.selectSpot(spot)
        }
        draft.selectedGear = activeGear(session)
        draft.gearIsSuggested = false
        draft.selectedBuddies = session.buddies
    }

    private static func activeGear(_ session: SurfSession) -> [Gear] {
        session.gear.filter { !$0.isArchived }
    }
}
