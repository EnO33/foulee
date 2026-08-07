#if DEBUG
import Foundation
import os

/// Deterministic capture mode for the Apple Watch App Store screenshots
/// (issue #239) — the wrist half of what `ScreenshotMode` does on the phone.
///
/// **This file, and everything else under `FouleeWatch/Screenshots/`, is wrapped
/// in `#if DEBUG`.** A Release build compiles none of it: the type does not
/// exist, so none of the guards that name it exist either, whatever the process
/// is launched with. That is the first of the two locks; the second is the
/// launch argument below, which a normal launch never carries.
///
/// What it does, once both locks are open, is *nothing by itself*: it is a flag.
/// The watch has no dependency container to swap — `WatchTodayStore` reads
/// `HKHealthStore` directly — so instead of a facade shipped in Release, each
/// of the watch's HealthKit entry points takes one `#if DEBUG` early return on
/// this flag:
///
/// * `WatchTodayStore.load()` — serves `ScreenshotSeed` instead of querying.
/// * `WatchTodayStore.startObserving()` — registers no `HKObserverQuery`.
/// * `WatchTodayStore.logGlass()` — the visible « J'ai bu » button saves no
///   `dietaryWater` sample if it is ever tapped on camera.
/// * `WatchWorkoutStore.start(activity:)` — shows the seeded session without
///   opening an `HKWorkoutSession`, so nothing is recorded and there is no
///   handle for `stop()` to finish.
/// * `WatchWorkoutRecovery.run()` — a stranded session is *not* finished during
///   a capture; finishing one is an `HKWorkout` write.
/// * `WatchWaterBackgroundDelivery.start()` — no background delivery, no
///   persistent observer.
///
/// The one HealthKit path not guarded is
/// `WatchHydrationNotificationCenter`'s « J'ai bu » action, which is reachable
/// only from a delivered notification — a capture run schedules none.
enum WatchScreenshotMode {
    /// The argument the capture target passes on launch. The same spelling the
    /// phone uses, because it is the same concept and one string is easier to
    /// keep honest than two; the two apps are separate processes, so nothing is
    /// shared but the text.
    ///
    /// Duplicated as a string literal in the `FouleeWatchScreenshots` UI-test
    /// target — a UI test drives a separate process and cannot import app code.
    /// `WatchScreenshotModeTests` pins the spelling.
    static let launchArgument = "-FouleeScreenshotMode"

    /// Set once at launch and read from wherever a HealthKit call would be
    /// made, including `WatchWorkoutRecovery`, which runs off the main actor.
    /// A lock rather than an actor-isolated `var` for exactly that reason.
    private static let active = OSAllocatedUnfairLock(initialState: false)

    /// Whether the current process activated the mode. False in every normal
    /// launch, which `WatchScreenshotModeTests` asserts against this process's
    /// own arguments.
    static var isActive: Bool { active.withLock { $0 } }

    /// Whether `arguments` asks for the capture mode. Pure and parameterised so
    /// the "a normal launch does not activate it" test can assert on the real
    /// `ProcessInfo` arguments *and* on hand-built ones.
    static func isRequested(arguments: [String]) -> Bool {
        arguments.contains(launchArgument)
    }

    /// Called first thing in `FouleeWatchApp.init()`, before anything reads
    /// HealthKit. Idempotent.
    static func activateIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard isRequested(arguments: arguments) else { return }
        active.withLock { $0 = true }
    }
}
#endif
