import SwiftUI
import Testing
@testable import FouleeWatch

/// Reaching the device probe, and what reaching it costs (issue #248).
///
/// Two promises are pinned here, and both are the difference between an
/// instrument and a liability:
///
/// * **It is reachable.** A probe nobody can open on a wrist answers none of
///   the four questions, and it ships in a Release build precisely so it can
///   be opened at all — TestFlight, the only route onto a paired Apple Watch,
///   distributes Release.
/// * **It only observes.** Opening it during a session must not start, stop or
///   alter a workout, and closing it must give the same session back.
@Suite("Watch diagnostic route")
@MainActor
struct WatchDiagnosticRouteTests {
    /// What the screens' closures did.
    @MainActor
    final class Taps {
        var opened = 0
        var stopped = 0
        var started: [SessionActivity] = []
    }

    private let metrics = WatchWorkoutMetrics(
        elapsed: 640,
        steps: 812,
        distanceMeters: 690,
        activeCalories: 47,
        heartRate: 118
    )

    // MARK: - The route

    @Test("The probe covers whatever is on screen, session included")
    func diagnosticWinsOverEverySessionState() {
        // Transition latency and battery cost over 30–60 min can only be read
        // *while* a session records — so the probe has to be able to sit over
        // a running workout, not only over the home screen.
        let states: [WatchWorkoutStore.State] = [
            .idle,
            .active(metrics),
            .ended(metrics, saveFailed: false),
            .ended(metrics, saveFailed: true)
        ]
        for state in states {
            #expect(WatchRoute.resolve(state: state, isShowingDiagnostic: true) == .diagnostic)
        }
    }

    @Test("Closing the probe gives the same session back, untouched")
    func theSessionIsHandedBackUnchanged() {
        // The whole non-interference promise, as a value: the route carries
        // the metrics through rather than resetting them, and there is no case
        // in `WatchRoute` that could end a workout.
        #expect(WatchRoute.resolve(state: .idle, isShowingDiagnostic: false) == .idle)
        #expect(WatchRoute.resolve(state: .active(metrics), isShowingDiagnostic: false) == .active(metrics))
        #expect(
            WatchRoute.resolve(state: .ended(metrics, saveFailed: true), isShowingDiagnostic: false)
                == .ended(metrics, saveFailed: true)
        )
    }

    // MARK: - Reachability, from both screens

    /// The idle route as `WatchRootView` builds it, with every outcome
    /// recorded — same shape as `WatchActivityPickerTests`' helper.
    private func idle(into taps: Taps) -> WatchIdleScreen {
        WatchIdleScreen(
            today: WatchTodayStore(),
            isChoosingActivity: false,
            intent: { .start(.walking) },
            onStart: { taps.started.append($0) },
            onAsk: {},
            onCancel: {},
            onDiagnostic: { taps.opened += 1 }
        )
    }

    @Test("The home screen offers the probe, and opening it starts no session")
    func theHomeScreenOpensTheProbe() throws {
        let taps = Taps()
        let home = try #require(ViewTreeProbe.first(WatchTodayView.self, in: idle(into: taps).body))
        // The button the home screen really builds, not the closure it was
        // handed: a diagnostic wired to nothing is a button that lies.
        let button = try #require(ViewTreeProbe.first(WatchDiagnosticButton.self, in: home.body))
        button.open()

        #expect(taps.opened == 1)
        // Nothing recorded. This button sits on the same screen as « Démarrer »,
        // and an `HKWorkout` stamp is permanent.
        #expect(taps.started.isEmpty)
    }

    @Test("A session in flight offers the probe too, without stopping")
    func theActiveScreenOpensTheProbe() throws {
        let taps = Taps()
        let screen = WatchActiveWalkView(
            metrics: metrics,
            onStop: { taps.stopped += 1 },
            onDiagnostic: { taps.opened += 1 }
        )
        let button = try #require(ViewTreeProbe.first(WatchDiagnosticButton.self, in: screen.body))
        button.open()

        #expect(taps.opened == 1)
        // The one mis-wiring that would cost a real outing: a diagnostic
        // button that ends the walk it was opened to measure.
        #expect(taps.stopped == 0)
    }

    @Test("The probe is not on screen until it is asked for")
    func theProbeIsNotOnTheHomeScreen() throws {
        let home = try #require(ViewTreeProbe.first(WatchTodayView.self, in: idle(into: Taps()).body))
        // Same density criterion as #224's picker: the home is read at a
        // glance outdoors, so the instrument is one labelled button, not a
        // panel of readings wedged under the streak hero.
        #expect(ViewTreeProbe.contains(WatchMotionProbeView.self, in: home.body) == false)
        #expect(ViewTreeProbe.contains(WatchDiagnosticButton.self, in: home.body))
    }

    // MARK: - Legible on the smallest wrist

    @Test("The way out is pinned to the screen, not scrolled away with the readings")
    func closeIsOutsideTheScrolledRegion() throws {
        let probe = WatchMotionProbeView(probe: WatchMotionProbe(), onClose: {})
        let scrolled = try #require(scrolledRegion(of: probe.body))

        // Fourteen rows of readings do not fit a 40 mm watch at any text size,
        // let alone the largest — so they scroll.
        #expect(ViewTreeProbe.contains(WatchMotionProbeCloseButton.self, in: scrolled) == false)
        // …and « Fermer » must not scroll with them. It is the only way back —
        // there is no navigation bar behind this screen — and #241 shipped
        // exactly this regression: content overflow put a button out of reach.
        #expect(ViewTreeProbe.contains(WatchMotionProbeCloseButton.self, in: probe.body))
    }

    /// The part of a screen the crown can push out of sight. Matched on the
    /// type's name, like `WatchActivityPickerTests` does, because a
    /// `ScrollView`'s type spells out the whole of its content.
    private func scrolledRegion(of value: Any, depth: Int = 24) -> Any? {
        if String(describing: type(of: value)).hasPrefix("ScrollView<") { return value }
        guard depth > 0 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = scrolledRegion(of: child.value, depth: depth - 1) { return found }
        }
        return nil
    }
}
