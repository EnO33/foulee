import ActivityKit
import Foundation

/// Shape of the data the Live Activity surfaces. Imported by both the
/// iOS app target (which starts/updates/ends the activity) and the
/// FouleeLiveActivity widget extension (which renders Lock Screen +
/// Dynamic Island views).
///
/// It is also the *only* channel between the two: the extension has no
/// app-group entitlement (`FouleeLiveActivity.entitlements` is empty), so the
/// snapshot the Série and Aujourd'hui widgets read is out of reach and nothing
/// else can tell it what the session in flight is (issue #225).
struct WalkActivityAttributes: ActivityAttributes {
    typealias ContentState = WalkActivityState

    var goalMinutes: Int

    /// What the session in flight is, as the app started it — carried here so
    /// the Lock Screen stops announcing a run as a walk (issue #225).
    ///
    /// Optional, and the optionality is the compatibility story rather than a
    /// convenience. ActivityKit keeps an activity alive across app launches
    /// *and across app updates*, so the moment this field ships, the new
    /// extension binary can be handed an activity whose persisted attributes
    /// were written by a build that had no such field. `nil` is that payload:
    /// a session the app cannot name. It renders exactly what the build that
    /// started it rendered — « Ta sortie » and the neutral figure (#222) —
    /// rather than guessing `.walking`, which would resurrect the very bug
    /// this field exists to kill on the one payload that cannot answer.
    ///
    /// Deliberately *not* defaulted: `init(goalMinutes:activity:)` below
    /// replaces the memberwise initializer (which would have handed an
    /// optional an implicit `nil`) so no production call site can drop the
    /// activity by omission. Only a legacy decode may produce `nil`.
    var activity: SessionActivity?

    init(goalMinutes: Int, activity: SessionActivity?) {
        self.goalMinutes = goalMinutes
        self.activity = activity
    }

    /// Title for the Lock Screen row, in the app's own registre.
    ///
    /// « Marche » and « Course » are the two activities the rest of the app
    /// names (`ActivityMode.label`), and « sortie » stays the noun for a
    /// session whose activity is unknown — no third word is introduced here.
    /// The paused suffix keeps the shape #222 gave it.
    func title(isPaused: Bool) -> String {
        isPaused ? "\(baseTitle) · En pause" : baseTitle
    }

    /// SF Symbol for the same session, read from `ActivityGlyph` rather than
    /// `FouleeIcon`: the latter lives in DesignSystem, imports SwiftUI and is
    /// not compiled into this extension (see Project.swift).
    var glyph: String {
        switch activity {
        case .walking: ActivityGlyph.walk
        case .running: ActivityGlyph.run
        case nil: ActivityGlyph.mixedCardio
        }
    }

    private var baseTitle: String {
        switch activity {
        case .walking: "Ta marche"
        case .running: "Ta course"
        case nil: "Ta sortie"
        }
    }

    /// Pushed on walk events (start, pause, resume, pedometer samples) —
    /// the clock itself runs system-side off `timerBasis`.
    struct WalkActivityState: Codable, Hashable, Sendable {
        /// Virtual start of the walk: now minus accumulated elapsed,
        /// recomputed on every push so `Text(timerInterval:)` keeps the
        /// clock running while the app is suspended.
        var timerBasis: Date
        /// Set while paused; freezes the system timer via `pauseTime`.
        var pausedAt: Date?
        var elapsed: TimeInterval
        var steps: Int
        var distanceKm: Double
        var activeCalories: Int

        var isPaused: Bool { pausedAt != nil }
    }
}

// MARK: - Tolerant decoding

extension WalkActivityAttributes {
    /// Never fails on the `activity` field, whatever is (or isn't) in the
    /// persisted payload — the same discipline #214 and #222 applied to the
    /// widget snapshot, and here it is load-bearing rather than defensive.
    ///
    /// The failure it prevents is specific. Both sweeps that clean up a
    /// stranded activity — `FouleeApp.endOrphanedWalkActivitiesOnce` at
    /// process start and `ActiveWalkStore.startLiveActivity` before requesting
    /// a new one — reach an activity only by enumerating
    /// `Activity<WalkActivityAttributes>.activities`, and ActivityKit offers no
    /// way to end an activity whose attributes it cannot rebuild. An attributes
    /// type that throws on last version's payload would therefore not just
    /// render wrong: it would put the stale activity out of reach of the only
    /// two things that can end it, and leave it on the Lock Screen.
    ///
    /// Two ways the field can be unreadable, both mapped to `nil`:
    /// * **absent** — written by a build before #225. Swift's synthesized
    ///   decoder already tolerates this one (an optional property decodes a
    ///   missing key as `nil`); it is spelled out here so the tolerance is a
    ///   stated contract and not an artefact of how the property is typed.
    /// * **unrecognised** — a raw value this binary has no case for, which the
    ///   synthesized decoder does *not* tolerate: it throws `dataCorrupted`.
    ///   Reachable by installing an older build over a newer one (TestFlight
    ///   allows it) and by any later third activity.
    ///
    /// `goalMinutes` stays required on purpose: it has been in every payload
    /// ever written, so a payload missing it is corrupt rather than old, and
    /// swallowing that would hide a real bug behind a 0-minute ring.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goalMinutes = try container.decode(Int.self, forKey: .goalMinutes)
        activity = try? container.decode(SessionActivity.self, forKey: .activity)
    }
}
