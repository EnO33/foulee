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

    @ObservationIgnored
    @Dependency(\.pedometer) private var pedometer

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    @ObservationIgnored
    @Dependency(\.continuousClock) private var clock

    @ObservationIgnored
    @Dependency(\.date) private var date

    @ObservationIgnored
    private var pedometerTask: Task<Void, Never>?

    @ObservationIgnored
    private var tickerTask: Task<Void, Never>?

    @ObservationIgnored
    private var liveActivity: Activity<WalkActivityAttributes>?

    // A pause splits the walk into segments. `banked*` carries the totals
    // from finished segments; the live segment (started at `segmentStart`,
    // counting `segment*`) is added on top. Paused wall-time — and any
    // steps taken while paused — never make it into the banked totals.
    @ObservationIgnored private var bankedElapsed: TimeInterval = 0
    @ObservationIgnored private var bankedSteps = 0
    @ObservationIgnored private var bankedDistance: Double = 0
    @ObservationIgnored private var segmentStart = Date.distantPast
    @ObservationIgnored private var segmentSteps = 0
    @ObservationIgnored private var segmentDistance: Double = 0

    /// Begin a fresh session. No-op when already active or finished — call
    /// `reset()` first to start a second walk in the same screen lifetime.
    func start(minutesGoal: Int = 20) {
        guard case .idle = state else { return }
        let session = WalkSession(startedAt: date.now)
        bankedElapsed = 0
        bankedSteps = 0
        bankedDistance = 0
        beginSegment()
        state = .active(session)
        tickerTask = makeTickerTask()
        startLiveActivity(startedAt: session.startedAt, minutesGoal: minutesGoal)
    }

    /// Freeze the clock + pedometer without ending the walk.
    func pause() async {
        guard case .active(var session) = state else { return }
        bankSegment()
        cancelObservers()
        session.elapsed = bankedElapsed
        session.steps = bankedSteps
        session.distanceMeters = bankedDistance
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
            live.endedAt = date.now
            session = live
        case .paused(var held):
            held.endedAt = date.now
            session = held
        default:
            return
        }
        cancelObservers()
        state = .finished(session)
        await runOrTrap { try await healthKit.saveWalkingWorkout(session) }
        await endLiveActivity(with: session)

        // Today's walk just landed in HealthKit — push the streak +
        // exercise-minute widgets to refresh right away rather than
        // waiting for the next 1 h tick.
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Return to idle so a second walk can be started in the same screen.
    func reset() {
        cancelObservers()
        bankedElapsed = 0
        bankedSteps = 0
        bankedDistance = 0
        segmentSteps = 0
        segmentDistance = 0
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
        pedometerTask = makePedometerTask(from: segmentStart)
    }

    /// Fold the live segment's totals into the running tally.
    private func bankSegment() {
        bankedElapsed += date.now.timeIntervalSince(segmentStart)
        bankedSteps += segmentSteps
        bankedDistance += segmentDistance
        segmentSteps = 0
        segmentDistance = 0
    }

    private func cancelObservers() {
        pedometerTask?.cancel()
        tickerTask?.cancel()
        pedometer.stop()
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
                    self.state = .active(session)
                    Task { await self.pushLiveActivity(session: session, isPaused: false) }
                }
            }
        }
    }

    private func makeTickerTask() -> Task<Void, Never> {
        Task { [clock] in
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(1))
                await MainActor.run {
                    guard case .active(var session) = self.state else { return }
                    session.elapsed = self.bankedElapsed
                        + self.date.now.timeIntervalSince(self.segmentStart)
                    self.state = .active(session)
                    Task { await self.pushLiveActivity(session: session, isPaused: false) }
                }
            }
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity(startedAt: Date, minutesGoal: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WalkActivityAttributes(startedAt: startedAt, goalMinutes: minutesGoal)
        let state = WalkActivityAttributes.WalkActivityState.zero
        let content = ActivityContent(state: state, staleDate: nil)
        liveActivity = try? Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    private func pushLiveActivity(session: WalkSession, isPaused: Bool) async {
        guard let liveActivity else { return }
        let state = WalkActivityAttributes.WalkActivityState(
            elapsed: session.elapsed,
            steps: session.steps,
            distanceKm: session.distanceKm,
            activeCalories: session.estimatedCalories,
            isPaused: isPaused
        )
        await liveActivity.update(ActivityContent(state: state, staleDate: nil))
    }

    private func endLiveActivity(with session: WalkSession) async {
        guard let liveActivity else { return }
        let finalState = WalkActivityAttributes.WalkActivityState(
            elapsed: session.elapsed,
            steps: session.steps,
            distanceKm: session.distanceKm,
            activeCalories: session.estimatedCalories,
            isPaused: false
        )
        await liveActivity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )
        self.liveActivity = nil
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
