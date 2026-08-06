import Foundation
import Testing
@testable import FouleeWatch

/// The watch's half of the phone→wrist wire (issue #223).
///
/// `WatchWorkoutStoreTests` proves the `activity` argument is honoured once
/// passed; these prove the watch actually *reads* the mode the phone synced.
/// Without them the watch could ignore the phone entirely — replacing the read
/// with a plain `.walking` left the watch suite green.
///
/// What each mode makes the start *button* do is one hop further out, in
/// `WatchActivityPickerTests` (issue #224).
@Suite("Watch start activity")
struct WatchStartActivityTests {
    /// Runs `body` against a throwaway suite, like `WatchSyncStoreTests`: the
    /// real one is the shared app group, which every other suite reads.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "watch-start-activity-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private func payload(_ mode: ActivityMode) -> WatchSyncPayload {
        WatchSyncPayload(streak: 3, minutesGoal: 20, stepsGoal: 6_000, activityMode: mode)
    }

    @Test("A synced running mode starts a run, in one gesture")
    @MainActor
    func runningModeStartsARun() throws {
        try withDefaults { defaults in
            // The full wire, through `WatchSyncStore`'s own storage: what the
            // receiver persists on a phone push is what the start button reads.
            WatchSyncStore.write(payload(.running), to: defaults)
            #expect(WatchRootView.startIntent(syncedTo: defaults) == .start(.running))
        }
    }

    @Test("A synced walking mode starts a walk, in one gesture")
    @MainActor
    func walkingModeStartsAWalk() throws {
        try withDefaults { defaults in
            // No picker in a single-activity mode: the user answered this
            // question in Réglages, and asking again would cost them a tap on
            // every session (issue #224).
            WatchSyncStore.write(payload(.walking), to: defaults)
            #expect(WatchRootView.startIntent(syncedTo: defaults) == .start(.walking))
        }
    }

    @Test("« Les deux » asks instead of guessing")
    @MainActor
    func bothAsks() throws {
        try withDefaults { defaults in
            // The watch sees the raw mode, not a resolved activity, precisely
            // so it can ask here instead of guessing. It used to resolve to
            // `.walking`, which wrote every run a « les deux » user recorded
            // into Santé as a walk — and `HKWorkout` is immutable (issue #224).
            WatchSyncStore.write(payload(.both), to: defaults)
            #expect(WatchRootView.startIntent(syncedTo: defaults) == .ask)
        }
    }

    @Test("A watch that never received a payload starts a walk")
    @MainActor
    func freshPairingStartsAWalk() throws {
        try withDefaults { defaults in
            // Fresh pairing, or a phone not opened since the update. Walking is
            // the app's historical behaviour, and a wrong stamp is permanent.
            // Asking would be worse here: the question would come from a
            // preference this watch has never been told about.
            #expect(WatchSyncStore.read(from: defaults) == nil)
            #expect(WatchRootView.startIntent(syncedTo: defaults) == .start(.walking))
        }
    }

    @Test("A newer mode from the phone wins")
    @MainActor
    func laterPushWins() throws {
        try withDefaults { defaults in
            // Read at tap time, not at view build: the phone can push while the
            // home screen sits on the wrist.
            WatchSyncStore.write(payload(.walking), to: defaults)
            WatchSyncStore.write(payload(.running), to: defaults)
            #expect(WatchRootView.startIntent(syncedTo: defaults) == .start(.running))
        }
    }
}
