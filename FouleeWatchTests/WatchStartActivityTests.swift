import Foundation
import Testing
@testable import FouleeWatch

/// The watch's half of the phone→wrist wire (issue #223).
///
/// `WatchWorkoutStoreTests` proves the `activity` argument is honoured once
/// passed; these prove the watch actually *reads* the mode the phone synced.
/// Without them the watch could ignore the phone entirely — replacing the read
/// with a plain `.walking` left the watch suite green.
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

    @Test("A synced running mode starts a run")
    @MainActor
    func runningModeStartsARun() throws {
        try withDefaults { defaults in
            // The full wire, through `WatchSyncStore`'s own storage: what the
            // receiver persists on a phone push is what the start button reads.
            WatchSyncStore.write(payload(.running), to: defaults)
            #expect(WatchRootView.startActivity(syncedTo: defaults) == .running)
        }
    }

    @Test("A synced walking mode starts a walk")
    @MainActor
    func walkingModeStartsAWalk() throws {
        try withDefaults { defaults in
            WatchSyncStore.write(payload(.walking), to: defaults)
            #expect(WatchRootView.startActivity(syncedTo: defaults) == .walking)
        }
    }

    @Test("« Les deux » starts a walk until #224 adds the picker")
    @MainActor
    func bothStartsAWalk() throws {
        try withDefaults { defaults in
            // The watch sees the raw mode, not a resolved activity, precisely
            // so #224 can ask here instead of guessing.
            WatchSyncStore.write(payload(.both), to: defaults)
            #expect(WatchRootView.startActivity(syncedTo: defaults) == .walking)
        }
    }

    @Test("A watch that never received a payload starts a walk")
    @MainActor
    func freshPairingStartsAWalk() throws {
        try withDefaults { defaults in
            // Fresh pairing, or a phone not opened since the update. Walking is
            // the app's historical behaviour, and a wrong stamp is permanent.
            #expect(WatchSyncStore.read(from: defaults) == nil)
            #expect(WatchRootView.startActivity(syncedTo: defaults) == .walking)
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
            #expect(WatchRootView.startActivity(syncedTo: defaults) == .running)
        }
    }
}
