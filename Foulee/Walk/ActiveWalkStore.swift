@preconcurrency import ActivityKit
import Dependencies
import Foundation
import Observation
import WidgetKit

/// Owns the in-flight walk: starts/stops the pedometer stream, ticks the
/// elapsed timer once a second, saves a `HKWorkout` on stop. Supports
/// pausing — the clock and pedometer freeze and paused time never counts.
///
/// State is a simple four-case enum so the view binds against it
/// declaratively (no flag soup). Errors funnel through a single
/// `runOrTrap` boundary; the rest of the file is happy-path.
@MainActor
@Observable
final class ActiveWalkStore {
    enum State: Equatable {
        case idle
        case active(WalkSession)
        case paused(WalkSession)
        case finished(WalkSession)
    }

    private(set) var state: State = .idle
    private(set) var lastError: String?

    /// Fixes recorded since the walk started, drawn by the route map. Keeps
    /// recording across pauses — a pause just leaves a straight gap.
    private(set) var route: [Coordinate] = []

    @ObservationIgnored
    @Dependency(\.pedometer) private var pedometer

    @ObservationIgnored
    @Dependency(\.altimeter) private var altimeter

    @ObservationIgnored
    @Dependency(\.location) private var location

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    /// The session's own motion history, read once at `stop()` (issue #246).
    @ObservationIgnored
    @Dependency(\.motionActivityHistory) private var motionActivityHistory

    @ObservationIgnored
    @Dependency(\.continuousClock) private var clock

    @ObservationIgnored
    @Dependency(\.date) private var date

    @ObservationIgnored
    private var pedometerTask: Task<Void, Never>?

    @ObservationIgnored
    private var altimeterTask: Task<Void, Never>?

    @ObservationIgnored
    private var tickerTask: Task<Void, Never>?

    @ObservationIgnored
    private var routeTask: Task<Void, Never>?

    @ObservationIgnored
    private var liveActivity: Activity<WalkActivityAttributes>?

    // A pause splits the walk into segments. `banked*` carries the totals
    // from finished segments; the live segment (started at `segmentStart`,
    // counting `segment*`) is added on top. Paused wall-time — and any
    // steps taken while paused — never make it into the banked totals.
    @ObservationIgnored private var bankedElapsed: TimeInterval = 0
    @ObservationIgnored private var bankedSteps = 0
    @ObservationIgnored private var bankedDistance: Double = 0
    @ObservationIgnored private var bankedElevation: Double = 0
    @ObservationIgnored private var segmentStart = Date.distantPast
    @ObservationIgnored private var segmentSteps = 0
    @ObservationIgnored private var segmentDistance: Double = 0
    @ObservationIgnored private var segmentElevation: Double = 0

    /// Begin a fresh session. No-op when already active or finished — call
    /// `reset()` first to start a second walk in the same screen lifetime.
    ///
    /// `activity` is what the finished workout will be stamped with in Santé
    /// (issue #223); the screen derives it from the user's `ActivityMode`. It
    /// defaults to `.walking` like the rest of this path, so a caller that
    /// doesn't care gets the app's historical behaviour.
    /// - Parameter isUndecided: « les deux » mode, where `activity` is only a
    ///   placeholder and the real answer comes from the session's motion
    ///   history at `stop()` (issue #246).
    func start(
        minutesGoal: Int = 20,
        activity: SessionActivity = .walking,
        isUndecided: Bool = false
    ) {
        guard case .idle = state else { return }
        let session = WalkSession(
            startedAt: date.now,
            activity: activity,
            isActivityUndecided: isUndecided
        )
        bankedElapsed = 0
        bankedSteps = 0
        bankedDistance = 0
        bankedElevation = 0
        route = []
        beginSegment()
        routeTask = makeRouteTask()
        state = .active(session)
        tickerTask = makeTickerTask()
        startLiveActivity(minutesGoal: minutesGoal)
    }

    /// Freeze the clock + pedometer without ending the walk.
    func pause() async {
        guard case .active(var session) = state else { return }
        bankSegment()
        cancelObservers()
        session.elapsed = bankedElapsed
        session.steps = bankedSteps
        session.distanceMeters = bankedDistance
        session.elevationGainMeters = bankedElevation
        state = .paused(session)
        await pushLiveActivity(session: session, isPaused: true)
    }

    /// Resume after a pause: open a fresh segment and restart the observers.
    func resume() {
        guard case .paused(let session) = state else { return }
        beginSegment()
        state = .active(session)
        tickerTask = makeTickerTask()
        Task { await self.pushLiveActivity(session: session, isPaused: false) }
    }

    /// Stop, cancel observers and persist the workout in HealthKit. Works
    /// from both the active and paused states.
    func stop() async {
        let session: WalkSession
        switch state {
        case .active(var live):
            bankSegment()
            live.elapsed = bankedElapsed
            live.steps = bankedSteps
            live.distanceMeters = bankedDistance
            live.elevationGainMeters = bankedElevation
            live.endedAt = date.now
            session = live
        case .paused(var held):
            held.endedAt = date.now
            session = held
        default:
            return
        }
        cancelObservers()
        routeTask?.cancel()
        let recorded = await decidingActivity(of: session)
        state = .finished(recorded)
        await runOrTrap { try await healthKit.saveWorkout(recorded) }
        await endLiveActivity(with: session)

        // Today's walk just landed in HealthKit — push the streak +
        // exercise-minute widgets to refresh right away rather than
        // waiting for the next 1 h tick.
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Return to idle so a second walk can be started in the same screen.
    func reset() {
        cancelObservers()
        routeTask?.cancel()
        // Normally already ended by stop(), but no path may leak the handle:
        // an unended activity outlives the store on the Lock Screen.
        if let liveActivity {
            self.liveActivity = nil
            Task { await liveActivity.end(nil, dismissalPolicy: .immediate) }
        }
        bankedElapsed = 0
        bankedSteps = 0
        bankedDistance = 0
        bankedElevation = 0
        segmentSteps = 0
        segmentDistance = 0
        segmentElevation = 0
        route = []
        state = .idle
        lastError = nil
    }

    // MARK: - Segments

    /// Open a fresh live segment starting now and (re)start the pedometer
    /// from that instant so its cumulative counts are segment-relative.
    private func beginSegment() {
        segmentStart = date.now
        segmentSteps = 0
        segmentDistance = 0
        segmentElevation = 0
        pedometerTask = makePedometerTask(from: segmentStart)
        altimeterTask = makeAltimeterTask()
    }

    /// Fold the live segment's totals into the running tally.
    private func bankSegment() {
        bankedElapsed += date.now.timeIntervalSince(segmentStart)
        bankedSteps += segmentSteps
        bankedDistance += segmentDistance
        bankedElevation += segmentElevation
        segmentSteps = 0
        segmentDistance = 0
        segmentElevation = 0
    }

    private func cancelObservers() {
        pedometerTask?.cancel()
        altimeterTask?.cancel()
        tickerTask?.cancel()
        pedometer.stop()
        altimeter.stop()
    }

    private func makePedometerTask(from start: Date) -> Task<Void, Never> {
        Task { [pedometer] in
            for await sample in pedometer.startUpdates(start) {
                await MainActor.run {
                    guard case .active(var session) = self.state else { return }
                    self.segmentSteps = sample.steps
                    self.segmentDistance = sample.distanceMeters
                    session.steps = self.bankedSteps + sample.steps
                    session.distanceMeters = self.bankedDistance + sample.distanceMeters
                    session.elapsed = self.bankedElapsed
                        + self.date.now.timeIntervalSince(self.segmentStart)
                    self.state = .active(session)
                    Task { await self.pushLiveActivity(session: session, isPaused: false) }
                }
            }
        }
    }

    private func makeAltimeterTask() -> Task<Void, Never> {
        Task { [altimeter] in
            for await gain in altimeter.startUpdates() {
                await MainActor.run {
                    guard case .active(var session) = self.state else { return }
                    self.segmentElevation = gain
                    session.elevationGainMeters = self.bankedElevation + gain
                    self.state = .active(session)
                }
            }
        }
    }

    private func makeRouteTask() -> Task<Void, Never> {
        // Build the stream on the main actor (we're @MainActor here), then
        // drain it off the hot path, appending each fix back on the main actor.
        let updates = location.routeUpdates()
        return Task {
            for await coordinate in updates {
                await MainActor.run { self.route.append(coordinate) }
            }
        }
    }

    // Drives the in-app clock only — the Live Activity runs its own
    // system timer and is updated on events, not on this tick.
    private func makeTickerTask() -> Task<Void, Never> {
        Task { [clock] in
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(1))
                await MainActor.run {
                    guard case .active(var session) = self.state else { return }
                    session.elapsed = self.bankedElapsed
                        + self.date.now.timeIntervalSince(self.segmentStart)
                    self.state = .active(session)
                }
            }
        }
    }

    private func runOrTrap<T: Sendable>(_ body: () async throws -> T) async -> T? {
        do {
            return try await body()
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}

// MARK: - Live Activity

extension ActiveWalkStore {
    /// The attributes ActivityKit is handed for the session in flight — what
    /// the Lock Screen and the Dynamic Island then draw (issue #225).
    ///
    /// Read off the *session*, so the Lock Screen cannot name the activity
    /// differently from what Santé will be stamped with. A member rather than
    /// three lines inside `startLiveActivity`, for the reason #234 pulled
    /// `ActiveWalkScreen.startIfKnown()` out of its call site: inlined, the step
    /// that reads `session.activity` could be dropped — back to the hardcoded
    /// `.walking` this issue removes — with the whole suite green, because
    /// `Activity.request` needs a live ActivityKit and never runs in a test
    /// process. As a plain value it is assertable, and `ActiveWalkStoreTests`
    /// asserts it.
    ///
    /// `nil` activity only when nothing is in flight; the sole production
    /// caller runs immediately after `state` becomes `.active`.
    /// Settle « les deux » from what the device measured, or hand the session
    /// back untouched (issue #246).
    ///
    /// Runs **before** the workout is saved, because the stamp is permanent —
    /// `HKWorkout` is immutable and Foulée has no delete path. And it never
    /// overrides a session the user chose the sport of: a mode of « Marche » or
    /// « Course » is an answer already given, and detection is not entitled to
    /// contradict it.
    ///
    /// Internal so a test can drive it without a session in flight.
    func decidingActivity(of session: WalkSession) async -> WalkSession {
        guard session.isActivityUndecided, let endedAt = session.endedAt else { return session }
        let samples = await motionActivityHistory.samples(session.startedAt, endedAt)
        let segments = ActivitySegmentation.segments(samples, from: session.startedAt, to: endedAt)
        var decided = session
        decided.activity = ActivitySegmentation.dominant(segments)
        decided.isActivityUndecided = false
        return decided
    }

    func liveActivityAttributes(minutesGoal: Int) -> WalkActivityAttributes {
        let activity: SessionActivity? = switch state {
        case .idle: nil
        case .active(let session), .paused(let session), .finished(let session):
            // Nil while « les deux » has not been settled: the Lock Screen then
            // says « Ta sortie » rather than naming a sport the save is about
            // to overwrite (issue #246).
            session.isActivityUndecided ? nil : session.activity
        }
        return WalkActivityAttributes(goalMinutes: minutesGoal, activity: activity)
    }
}

private extension ActiveWalkStore {
    func startLiveActivity(minutesGoal: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // A crash/force-quit mid-walk can leave a stray activity behind; end
        // it before requesting so the Lock Screen never shows two walks. Also
        // the second of the two places that clear an activity left in flight
        // by a previous *build* — see `WalkActivityAttributes.init(from:)` for
        // why that enumeration is only reachable while the attributes still
        // decode last version's payload.
        for stray in Activity<WalkActivityAttributes>.activities {
            Task { await stray.end(nil, dismissalPolicy: .immediate) }
        }
        let attributes = liveActivityAttributes(minutesGoal: minutesGoal)
        let state = WalkActivityAttributes.WalkActivityState(
            timerBasis: date.now,
            pausedAt: nil,
            elapsed: 0,
            steps: 0,
            distanceKm: 0,
            activeCalories: 0
        )
        let content = ActivityContent(state: state, staleDate: nextStaleDate())
        liveActivity = try? Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    func pushLiveActivity(session: WalkSession, isPaused: Bool) async {
        guard let liveActivity else { return }
        await liveActivity.update(
            ActivityContent(
                state: activityState(for: session, isPaused: isPaused),
                staleDate: nextStaleDate()
            )
        )
    }

    func endLiveActivity(with session: WalkSession) async {
        guard let liveActivity else { return }
        await liveActivity.end(
            ActivityContent(
                state: activityState(for: session, isPaused: true),
                staleDate: nil
            ),
            dismissalPolicy: .immediate
        )
        self.liveActivity = nil
    }

    func activityState(
        for session: WalkSession,
        isPaused: Bool
    ) -> WalkActivityAttributes.WalkActivityState {
        let now = date.now
        return WalkActivityAttributes.WalkActivityState(
            timerBasis: now.addingTimeInterval(-session.elapsed),
            pausedAt: isPaused ? now : nil,
            elapsed: session.elapsed,
            steps: session.steps,
            distanceKm: session.distanceKm,
            activeCalories: session.estimatedCalories
        )
    }

    // Counters only move on event pushes; past this the system greys the
    // content out as stale (the clock keeps ticking regardless).
    func nextStaleDate() -> Date {
        date.now.addingTimeInterval(10 * 60)
    }
}
