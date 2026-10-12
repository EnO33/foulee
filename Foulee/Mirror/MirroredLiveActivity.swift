// Same as `ActiveWalkStore` and `FouleeApp`: `Activity` predates Sendable
// annotations, and this type only ever touches it from the main actor.
@preconcurrency import ActivityKit
import FouleeKit
import Foundation
import os
import UIKit

/// The outing running on the wrist, on the iPhone's Lock Screen (issue #275).
///
/// **An experiment as much as a feature.** ActivityKit's documentation says
/// `Activity.request` fails outside the foreground; Apple's WWDC23 session on
/// mirroring says HealthKit gives the app ten seconds to start one from a
/// mirror wake. No document settles it and no simulator can, so this tries —
/// and logs which way it went, with the app state at the moment of asking.
/// The first outing on a real wrist answers the issue:
///
/// ```sh
/// log stream --predicate 'subsystem == "com.eno33.foulee" AND category == "live-activity"' --info
/// ```
///
/// Either outcome leaves the app as it was: a refused request is logged and
/// the in-app mirror screen (#279) carries on alone.
final class MirroredLiveActivity {
    static let shared = MirroredLiveActivity()

    private var activity: Activity<WalkActivityAttributes>?

    /// Activities this process started. The orphan sweep at launch
    /// (`FouleeApp.endOrphanedWalkActivitiesOnce`) must leave them alone: a
    /// mirror wake *is* a launch, and the sweep would otherwise end the very
    /// activity this wake just started.
    nonisolated static let startedHere = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    /// Bring the Lock Screen in line with what the store now knows.
    func reflect(_ store: MirroredSessionStore) async {
        guard let session = store.session else {
            await end()
            return
        }
        let state = Self.state(
            figures: store.figures,
            outingStartedAt: store.outingStartedAt ?? session.startedAt
        )
        if let activity {
            await activity.update(ActivityContent(state: state, staleDate: Self.staleDate()))
        } else {
            start(with: state)
        }
    }

    /// What the Lock Screen draws, from the wrist's last figures — zeros
    /// until the first batch, with the clock already running from the
    /// outing's start.
    ///
    /// `timerBasis` is the outing's own start rather than « now minus
    /// elapsed »: the wrist already pushes that start back by every pause, and
    /// the system runs the clock from it between two wakes.
    nonisolated static func state(
        figures: WatchSessionSnapshot?,
        outingStartedAt: Date
    ) -> WalkActivityAttributes.WalkActivityState {
        guard let figures else {
            return WalkActivityAttributes.WalkActivityState(
                timerBasis: outingStartedAt, pausedAt: nil, elapsed: 0,
                steps: 0, distanceKm: 0, activeCalories: 0
            )
        }
        return WalkActivityAttributes.WalkActivityState(
            timerBasis: figures.outingStartedAt,
            pausedAt: figures.isPaused ? figures.sentAt : nil,
            elapsed: figures.elapsed(at: figures.sentAt),
            steps: figures.steps,
            distanceKm: figures.distanceKm,
            activeCalories: figures.activeCalories
        )
    }

    private func start(with state: WalkActivityAttributes.WalkActivityState) {
        let appState = Self.describe(UIApplication.shared.applicationState)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            FouleeLog.liveActivity.notice("miroir : Live Activities désactivées dans Réglages (app \(appState, privacy: .public))")
            return
        }
        // No sport in the attributes: they are fixed for the activity's life,
        // and a mirrored outing can switch from walk to run mid-way (#265).
        // « Ta sortie » stays true; a named sport would go stale at the first
        // switch.
        let attributes = WalkActivityAttributes(goalMinutes: Self.goalMinutes, activity: nil)
        do {
            let started = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Self.staleDate()),
                pushType: nil
            )
            let id = started.id
            _ = Self.startedHere.withLock { $0.insert(id) }
            activity = started
            FouleeLog.liveActivity.notice("miroir : Live Activity démarrée (app \(appState, privacy: .public))")
        } catch {
            FouleeLog.liveActivity.error(
                "miroir : Activity.request refusé (app \(appState, privacy: .public)) : \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func end() async {
        guard let activity else { return }
        self.activity = nil
        await activity.end(nil, dismissalPolicy: .default)
        FouleeLog.liveActivity.notice("miroir : Live Activity terminée")
    }

    /// Read straight from the defaults: a mirror wake mounts no UI, so the
    /// `UserPreferences` the screens share does not exist on this path.
    private static var goalMinutes: Int {
        UserDefaults.standard.object(forKey: "preferences.minutesGoal") as? Int ?? 20
    }

    /// Past this the system greys the figures as stale; the clock keeps
    /// running regardless. HealthKit can go minutes between two deliveries.
    private static func staleDate() -> Date {
        Date.now.addingTimeInterval(10 * 60)
    }

    /// The fact #275 is about: was the app in the foreground when it asked?
    private static func describe(_ state: UIApplication.State) -> String {
        switch state {
        case .active: "au premier plan"
        case .inactive: "inactive"
        case .background: "en arrière-plan"
        @unknown default: "état inconnu"
        }
    }
}
