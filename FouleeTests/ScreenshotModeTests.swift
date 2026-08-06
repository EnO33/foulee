import Dependencies
import Foundation
import Testing
@testable import Foulee

/// The three constraints of the capture mode (issue #235), asserted rather
/// than promised.
///
/// The fourth — "a Release build contains none of this" — has no runtime
/// assertion by nature: it is enforced by the `#if DEBUG` wrapping every file
/// in `Foulee/Screenshots/` **and** the guard around the single call site in
/// `FouleeApp.init()`. This suite itself only compiles because it runs against
/// a Debug build.
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

    /// The two HealthKit writes the app can make. Both are `{}` in the capture
    /// doubles, so the session capture saves no `HKWorkout` and a tap on
    /// « J'ai bu » stores no `dietaryWater` sample. Asserted by calling them:
    /// a future edit that wires a real store back in would have to keep these
    /// silent *and* leave the seeded water total untouched.
    @Test("The capture doubles write nothing back")
    func doublesNeverWrite() async throws {
        let health = ScreenshotDoubles.healthKit
        try await health.saveWorkout(WalkSession(startedAt: ScreenshotSeed.instant))
        try await health.logWater(500)
        let water = try await health.todayWaterML()
        #expect(water == ScreenshotSeed.waterML)
    }
}
