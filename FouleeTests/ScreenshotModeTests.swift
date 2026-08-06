import Dependencies
import Foundation
import Testing
@testable import Foulee

/// The constraints of the capture mode (issue #235), asserted rather than
/// promised: never active in production, deterministic, and leaving nothing
/// behind in any store the app shares with anything else.
///
/// Two things here have no runtime assertion, by nature rather than by
/// omission. "A Release build contains none of this" is enforced by the
/// `#if DEBUG` wrapping every file in `Foulee/Screenshots/` **and** the guard
/// around the single call site in `FouleeApp.init()` — this suite itself only
/// compiles because it runs against a Debug build. And that
/// `activateIfRequested` *calls* `divertSharedWrites` cannot be checked from
/// here either: activating the mode in the test host would run
/// `prepareDependencies` in a process that has already resolved its
/// dependencies. What the diversion does, once called, is asserted below.
@Suite("Screenshot mode")
struct ScreenshotModeTests {
    // MARK: - Never active in production

    /// The one that matters: this process is a normal launch of the app (the
    /// test host), and it must not be in capture mode. Both the decision
    /// function fed the *real* launch arguments and the state it would have
    /// left behind are checked, so neither a mis-spelled argument nor an
    /// accidental unconditional activation passes.
    @Test("A normal launch does not activate the capture mode")
    @MainActor
    func normalLaunchDoesNotActivate() {
        #expect(ScreenshotMode.isRequested(arguments: ProcessInfo.processInfo.arguments) == false)
        #expect(ScreenshotMode.isActive == false)
        #expect(ScreenshotMode.preferencesDefaults == nil)
    }

    @Test("Only the explicit launch argument requests the capture mode")
    @MainActor
    func onlyTheExplicitArgumentActivates() {
        #expect(ScreenshotMode.isRequested(arguments: []) == false)
        #expect(ScreenshotMode.isRequested(arguments: ["/tmp/Foulee.app/Foulee"]) == false)
        #expect(ScreenshotMode.isRequested(arguments: ["-FouleeScreenshot"]) == false)
        #expect(ScreenshotMode.isRequested(arguments: ["screenshots"]) == false)
        #expect(ScreenshotMode.isRequested(arguments: [ScreenshotMode.launchArgument]))
    }

    /// A UI test target is a separate process and cannot import app code, so
    /// `FouleeScreenshots` spells these two arguments as literals. Pinning the
    /// exact strings here is what keeps a rename from silently turning every
    /// capture into a screenshot of the developer's own Health data.
    @Test("The launch arguments keep the spelling the capture target passes")
    @MainActor
    func launchArgumentSpelling() {
        #expect(ScreenshotMode.launchArgument == "-FouleeScreenshotMode")
        #expect(ScreenshotMode.onboardingArgument == "-FouleeScreenshotOnboarding")
    }

    // MARK: - Deterministic

    @Test("The seeded instant is a fixed Thursday afternoon, not today")
    func seededInstantIsFixed() {
        let calendar = Calendar.current
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .weekday],
            from: ScreenshotSeed.instant
        )
        #expect(parts.year == 2026)
        #expect(parts.month == 5)
        #expect(parts.day == 14)
        #expect(parts.hour == 14)
        #expect(parts.minute == 35)
        #expect(parts.weekday == 5) // Thursday, an active day in the seeded week
    }

    /// The clock the doubles install moves exactly once, to a fixed offset, and
    /// moving it again changes nothing — which is what stops the session
    /// capture from depending on how fast the UI test tapped.
    @Test("The capture clock advances idempotently to the session offset")
    func captureClockIsIdempotent() {
        let clock = ScreenshotClock.shared
        clock.advance(toOffset: ScreenshotSeed.sessionElapsed)
        let first = clock.now
        clock.advance(toOffset: ScreenshotSeed.sessionElapsed)
        #expect(clock.now == first)
        #expect(first == ScreenshotSeed.instant.addingTimeInterval(ScreenshotSeed.sessionElapsed))
    }

    // MARK: - Zero writes

    /// The two HealthKit writes the app can make, called for exactly what that
    /// proves: these two closures are silent, and the seeded intake a capture
    /// shows does not move when one of them is invoked.
    ///
    /// It proves nothing about an edit that wires a real store back into the
    /// doubles — a closure body is not observable from out here, and a
    /// `saveWorkout` that really saved would pass this test unchanged. That
    /// claim is the next test's, and it is checked at the source.
    @Test("The capture doubles' write closures are no-ops")
    func doublesNeverWrite() async throws {
        let health = ScreenshotDoubles.healthKit
        try await health.saveWorkout(WalkSession(startedAt: ScreenshotSeed.instant))
        try await health.logWater(500)
        let water = try await health.todayWaterML()
        #expect(water == ScreenshotSeed.waterML)
    }

    /// The invariant issue #235 actually states — « Zéro écriture HealthKit » —
    /// checked where it is decidable. Writing a sample takes an `HKHealthStore`,
    /// so no file under `Foulee/Screenshots/` may so much as name one; the rest
    /// of the list closes the same door on the two stores this mode diverts
    /// rather than doubles (the app's own preferences, the widget app group).
    ///
    /// Comments are stripped before matching, so the prose in those files stays
    /// free to name what it forbids — as this very comment does.
    @Test("No capture-mode source can reach a real store")
    func captureSourcesCannotReachAStore() throws {
        let forbidden = [
            "import HealthKit", "HKHealthStore", "HKWorkout", "HKQuantity",
            "UserDefaults.standard", "SharedStore.write", "SharedStore.updateWater"
        ]
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.captureSourceDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        // A scan that found nothing would pass every assertion below.
        #expect(files.count >= 5)
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            for symbol in forbidden {
                // Through a `Bool` rather than inline, so a failure reports the
                // file and the symbol instead of dumping the whole source.
                let names = code.contains(symbol)
                #expect(names == false, "\(file.lastPathComponent) names \(symbol)")
            }
        }
    }

    /// `Foulee/Screenshots/`, resolved from this file rather than from a bundle:
    /// the sources are not shipped into the test bundle, and the only path that
    /// survives is the one the compiler recorded. Same machine builds and runs,
    /// on a developer's Mac as on the CI runner.
    private static let captureSourceDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()   // FouleeTests/
        .deletingLastPathComponent()   // repository root
        .appending(path: "Foulee/Screenshots")

    // MARK: - The stores it cannot double

    /// The widget app group is process-global and shared with the widget
    /// extension, so it cannot be swapped through `@Dependency` like the rest.
    /// Activation points `SharedStore` at a throwaway domain instead, and mutes
    /// the Watch push that rides the same refresh pass — both fabricated, and
    /// a widget cannot tell a seeded snapshot from a measured one.
    @Test("Activation diverts the app group and mutes the Watch")
    @MainActor
    func activationDivertsEveryProcessGlobalStore() {
        defer { restoreSharedStore() }
        ScreenshotMode.divertSharedWrites()

        #expect(SharedStore.activeSuiteName == ScreenshotMode.sharedStoreSuite)
        #expect(SharedStore.activeSuiteName != SharedStore.suiteName)
        #expect(PhoneWatchSync.isMuted)
    }

    /// And the seam really moves the bytes: a snapshot written while diverted
    /// lands in the throwaway domain, and the real app group — the one every
    /// widget on the device reads — never sees it. Without the seam it would,
    /// stamped with the real day, which is what a capture run used to do.
    ///
    /// The sentinel step count is what makes this safe to run beside the rest
    /// of the suite: nothing else in the process writes that number. Drawn
    /// fresh each run rather than fixed, so it is always *this* run's write
    /// that is being looked for — a fixed one left in the real app group by a
    /// run that failed would keep failing every run after it.
    @Test("A write made while diverted never reaches the real app group")
    @MainActor
    func divertedWritesLeaveTheRealAppGroupAlone() throws {
        let sentinel = Int.random(in: 100_000_000...999_999_999)
        let suite = "ScreenshotModeTests-\(UUID().uuidString)"
        defer {
            restoreSharedStore()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        var snapshot = WidgetSnapshot.placeholder
        snapshot.steps = sentinel
        SharedStore.activeSuiteName = suite
        SharedStore.write(snapshot)

        #expect(SharedStore.read()?.steps == sentinel)
        // Key-agnostic on purpose: renaming the snapshot's defaults key must
        // not quietly turn this into an assertion about nothing.
        let group = try #require(UserDefaults(suiteName: SharedStore.suiteName))
        let stored = group.persistentDomain(forName: SharedStore.suiteName) ?? [:]
        let leaked = stored.values.contains { value in
            guard let data = value as? Data else { return false }
            return String(decoding: data, as: UTF8.self).contains("\(sentinel)")
        }
        #expect(leaked == false)
    }

    /// Both process-globals this suite moves, put back. One helper because
    /// forgetting either would leave the rest of the test run writing into a
    /// capture suite.
    @MainActor
    private func restoreSharedStore() {
        SharedStore.activeSuiteName = SharedStore.suiteName
        PhoneWatchSync.isMuted = false
        UserDefaults(suiteName: ScreenshotMode.sharedStoreSuite)?
            .removePersistentDomain(forName: ScreenshotMode.sharedStoreSuite)
    }
}
