import Dependencies
import FouleeKit
import Foundation
import Testing
@testable import Foulee

/// The running work's contract, and the one acceptance criterion of #220 that
/// isn't visible on screen: **no existing user's history may move.**
/// `ActivityMode` steers what the app proposes; the streak, the record and the
/// Bilan's year count exercise minutes across every activity type, so all three
/// must answer the same thing under `.walking`, `.running` and `.both`.
///
/// Pinned by output rather than by construction, because there is nothing
/// structural left to assert: `StreakCalculator`, `StreakSummary` and
/// `RecapStore` take no activity parameter at all, and
/// `TodayStore.apply(preferences:)` mirrors every preference *except* this
/// one. So the suite drives the real stores over one fixture, once per mode,
/// and compares everything they publish. Wiring the mode into any of them
/// would have to move one of these numbers to be worth wiring at all — and
/// then this fails. Verified by sabotage: a `didSet` raising `minutesGoal` to
/// 30 for `.running` — the plausible "runners get their own goal" mistake —
/// drops the streak from 3 to 0 and the record from 5 to 0, and the suite
/// reports it.
///
/// What it can't catch: a mode threaded into the *live* HealthKit queries,
/// which the stub replaces. The window assertion is the closest guard
/// available — the history read carries a day count and nothing else, so
/// there is no channel through which the preference could reach it.
@Suite("Activity mode moves no history")
struct ActivityModeNeutralityTests {
    /// A live 3-day streak (today included) in front of an older 5-day run, so
    /// `current` and `best` differ and neither is 0 — two zeros would compare
    /// equal whatever the mode did.
    ///
    /// nonisolated: read from a `@Sendable` history closure.
    nonisolated private static let walkedOffsets = [0, 1, 2, 5, 6, 7, 8, 9]

    @Test("Streak, record and year are identical under walking, running and both")
    func everyModeAnswersTheSame() async throws {
        let baseline = try await outputs(for: .walking)
        // The fixture has to be worth comparing before the comparison means
        // anything: a store answering 0 everywhere would pass silently.
        #expect(baseline.streak == 3)
        #expect(baseline.bestStreak == 5)
        #expect(baseline.bilanStreak == 3)
        #expect(baseline.bilanBest == 5)
        #expect(baseline.year?.walks == 8)

        for mode in ActivityMode.allCases where mode != .walking {
            expect(try await outputs(for: mode), matches: baseline, mode: mode)
        }
    }

    /// Compared field by field rather than by a synthesized `==`: each failure
    /// then names the surface that moved, and the dead-code scan can see every
    /// property being read (an assign-only property whose only reader is a
    /// synthesized `Equatable` fails the build).
    private func expect(_ measured: StreakOutputs, matches baseline: StreakOutputs, mode: ActivityMode) {
        let culprit = mode.rawValue
        #expect(measured.streak == baseline.streak, "\(culprit) moved the streak")
        #expect(measured.bestStreak == baseline.bestStreak, "\(culprit) moved the record")
        #expect(measured.weekMinutes == baseline.weekMinutes, "\(culprit) moved the week bars")
        #expect(measured.bilanStreak == baseline.bilanStreak, "\(culprit) moved the Bilan's streak")
        #expect(measured.bilanBest == baseline.bilanBest, "\(culprit) moved the Bilan's record")
        #expect(measured.historyWindows == baseline.historyWindows, "\(culprit) changed the history read")
        #expect(measured.year == baseline.year, "\(culprit) moved the Bilan's year")
    }

    /// Everything the streak surfaces publish for one mode: the home card's
    /// counts and week bars, and the Bilan's streak and year (#445).
    private struct StreakOutputs {
        var streak: Int
        var bestStreak: Int
        var weekMinutes: [Int]
        var bilanStreak: Int
        var bilanBest: Int
        var year: StreakSummary?
        /// Day counts the history read was asked for, in order.
        var historyWindows: [Int]
    }

    private func outputs(for mode: ActivityMode) async throws -> StreakOutputs {
        let suiteName = "ActivityModeNeutrality-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserPreferences(defaults: defaults)
        // Every weekday active, so the counts don't depend on which day the
        // suite happens to run — same reason as `StreakTestSupport`.
        preferences.activeDays = Set(Weekday.allCases)
        preferences.activityMode = mode

        let windows = LockedRef<[Int]>([])
        let history = StreakTestSupport.windowed { StreakTestSupport.walkedDays(Self.walkedOffsets) }
        return await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = { daysBack in
                windows.set(windows.value + [daysBack])
                return try await history(daysBack)
            }
        } operation: {
            let today = TodayStore()
            today.apply(preferences: preferences)
            await today.refresh()
            let bilan = RecapStore()
            await bilan.load(goalMinutes: preferences.minutesGoal, activeDays: preferences.activeDays, withHistory: true)
            return StreakOutputs(
                streak: today.snapshot?.streak ?? -1,
                bestStreak: today.snapshot?.bestStreak ?? -1,
                weekMinutes: today.snapshot?.weekMinutes ?? [],
                bilanStreak: bilan.streak?.current ?? -1,
                bilanBest: bilan.streak?.best ?? -1,
                year: bilan.streak,
                historyWindows: windows.value
            )
        }
    }
}
