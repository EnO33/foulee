import Dependencies
import Foundation
import Observation

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

    /// Begin a fresh session. No-op when already active or finished — call
    /// `reset()` first to start a second walk in the same screen lifetime.
    func start() {
        guard case .idle = state else { return }
        let session = WalkSession(startedAt: date.now)
        state = .active(session)
        pedometerTask = makePedometerTask(from: session.startedAt)
        tickerTask = makeTickerTask()
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
