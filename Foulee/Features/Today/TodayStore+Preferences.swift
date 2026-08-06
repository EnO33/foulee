import Foundation

/// The mirrored copy of the user's preferences: what the store derives from it,
/// and the gate that decides whether a change is worth re-deriving and
/// publishing. Split out of `TodayStore.swift` for the same reason
/// `TodayStore+WidgetPublication.swift` is — that file is at the length limit.
extension TodayStore {
    /// What tapping start on the Today screen right now has to do: begin a
    /// session of a known activity, or ask which one (issue #224).
    ///
    /// The phone's single resolution point, and the reason it lives on the
    /// store rather than in `TodayScreen`: a `View` body is not reachable from
    /// a test process, so with the `mode -> intent` step inlined there the
    /// whole phone path could go back to stamping walks with the suite green.
    /// `TodayScreen` only forwards this value to `ActiveWalkScreen`.
    var startIntent: ActivityStartIntent { ActivityStartIntent(mode: activityMode) }

    /// The walk window as the mirrored copy stores it — hour and minute only.
    /// Not private: `apply` (in `TodayStore.swift`) stores what it returns and
    /// `hasChanged` compares against it, and they must agree.
    static func window(for preferences: UserPreferences) -> DateComponents {
        DateComponents(
            hour: preferences.walkWindowStart.hour,
            minute: preferences.walkWindowStart.minute
        )
    }

    /// Whether anything the mirrored copy holds differs from `preferences`.
    ///
    /// Gates both halves of `apply`: the snapshot re-derivation (goal, days and
    /// window are what the ring and the streak are computed against) *and* the
    /// publish, which is the only thing that carries the hydration prefs and
    /// the activity mode to the Watch. Neither of the latter two is a snapshot
    /// input — they're compared here so a settings change reaches the wrist
    /// without waiting for the next refresh (issue #223).
    ///
    /// Internal, not private, and that is the point: for a preference the
    /// snapshot doesn't feed, `apply`'s only visible effect is a publish, and
    /// the publish goes through the process-global app group — unassertable
    /// from a suite that runs in parallel. This gate is where such a change is
    /// either noticed or lost, so it is the seam the tests hold.
    func hasChanged(preferences: UserPreferences) -> Bool {
        preferences.stepsGoal != stepsGoal
            || preferences.minutesGoal != minutesGoal
            || Self.window(for: preferences) != walkWindowStart
            || preferences.activeDays != activeDays
            || preferences.hydrationEnabled != hydrationEnabled
            || preferences.hydrationGoalML != hydrationGoalML
            || preferences.hydrationGlassML != hydrationGlassML
            || preferences.activityMode != activityMode
    }
}
