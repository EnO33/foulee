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
    /// convenience. ActivityKit keeps an activity alive across app launches,
    /// and an app *update* is on that path, so the new extension binary may be
    /// handed an activity whose persisted attributes were written by a build
    /// that had no such field. `nil` is that payload: a session the app cannot
    /// name. It renders exactly what the build that started it rendered —
    /// « Ta sortie » and the neutral figure (#222) — rather than guessing
    /// `.walking`, which would resurrect the very bug this field exists to
    /// kill on the one payload that cannot answer.
    ///
    /// How far that scenario is *verified* rather than reasoned: see
    /// `init(from:)` below, which is explicit about it.
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
    /// The two named cases come from `SessionActivity.sessionTitle`, which is
    /// also what the phone's own live screen draws — the two surfaces are on
    /// screen at the same moment and #222 asked for one voice across them.
    /// « sortie » stays the noun for a session whose activity is unknown; no
    /// third word is introduced here. The paused suffix keeps #222's shape.
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
        activity?.sessionTitle ?? "Ta sortie"
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
    /// **What is verified, and what is not.** The tolerance itself is tested:
    /// this type decodes a pre-#225 payload, an unknown raw value and a type
    /// mismatch, under `JSONDecoder` *and* `PropertyListDecoder`
    /// (`WalkActivityAttributesTests`). What no test here can reach is the step
    /// upstream of the decoder — whether ActivityKit persists attributes
    /// through `Codable` at all, and whether `Activity.activities` surfaces an
    /// activity whose attributes type changed shape between two builds. The
    /// archive format is private and no test process can leave an activity in
    /// flight across a binary swap. #225 shipped without that being observed on
    /// a device, so the paragraph below is the *reason* the tolerance is worth
    /// its few lines, not an established failure mode.
    ///
    /// The failure it is insurance against: both sweeps that clean up a
    /// stranded activity — `FouleeApp.endOrphanedWalkActivitiesOnce` at
    /// process start and `ActiveWalkStore.startLiveActivity` before requesting
    /// a new one — reach an activity only by enumerating
    /// `Activity<WalkActivityAttributes>.activities`, and ActivityKit offers no
    /// documented way to end an activity whose attributes it cannot rebuild.
    /// *If* the rebuild does run through this initializer, then a type that
    /// throws on last version's payload would not just render wrong: it would
    /// put the stale activity out of reach of the only two things that can end
    /// it. Cheap to buy out; expensive and un-hotfixable to get wrong.
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
