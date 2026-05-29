@preconcurrency import ActivityKit
import Dependencies
import Foundation
import Observation
import WidgetKit

/// Owns the in-flight walk: starts/stops the pedometer stream, ticks the
/// elapsed timer once a second, saves a `HKWorkout` on stop.
///
/// State is a simple three-case enum so the view binds against it
/// declaratively (no flag soup). Errors funnel through a single
/// `runOrTrap` boundary; the rest of the file is happy-path.
@MainActor
@Observable
final class ActiveWalkStore {
    enum State: Equatable {
        case idle
        case active(WalkSession)
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

    /// Begin a fresh session. No-op when already active or finished — call
    /// `reset()` first to start a second walk in the same screen lifetime.
    func start(minutesGoal: Int = 20) {
        guard case .idle = state else { return }
        let session = WalkSession(startedAt: date.now)
        state = .active(session)
        pedometerTask = makePedometerTask(from: session.startedAt)
        tickerTask = makeTickerTask()
        startLiveActivity(startedAt: session.startedAt, minutesGoal: minutesGoal)
    }

    /// Stop, cancel observers and persist the workout in HealthKit.
    func stop() async {
        guard case .active(var session) = state else { return }
        pedometerTask?.cancel()
        tickerTask?.cancel()
        pedometer.stop()
        session.endedAt = date.now
        session.elapsed = date.now.timeIntervalSince(session.startedAt)
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
        pedometerTask?.cancel()
        tickerTask?.cancel()
        pedometer.stop()
        state = .idle
        lastError = nil
    }

    private func makePedometerTask(from start: Date) -> Task<Void, Never> {
        Task { [pedometer] in
            for await sample in pedometer.startUpdates(start) {
                await MainActor.run {
                    guard case .active(var session) = self.state else { return }
                    session.steps = sample.steps
                    session.distanceMeters = sample.distanceMeters
                    self.state = .active(session)
                    Task { await self.pushLiveActivity(session: session) }
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
                    session.elapsed = self.date.now.timeIntervalSince(session.startedAt)
                    self.state = .active(session)
                    Task { await self.pushLiveActivity(session: session) }
                }
            }
        }
    }

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

    private func pushLiveActivity(session: WalkSession) async {
        guard let liveActivity else { return }
        let state = WalkActivityAttributes.WalkActivityState(
            elapsed: session.elapsed,
            steps: session.steps,
            distanceKm: session.distanceKm,
            activeCalories: session.estimatedCalories
        )
        await liveActivity.update(ActivityContent(state: state, staleDate: nil))
    }

    private func endLiveActivity(with session: WalkSession) async {
        guard let liveActivity else { return }
        let finalState = WalkActivityAttributes.WalkActivityState(
            elapsed: session.elapsed,
            steps: session.steps,
            distanceKm: session.distanceKm,
            activeCalories: session.estimatedCalories
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
