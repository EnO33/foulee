import Foundation
import Testing
@testable import FouleeWatch

/// The phone's session on the wrist (issue #342): what is shown, and the
/// commands sent back.
@MainActor
@Suite("Watch phone session")
struct WatchPhoneSessionTests {
    private let now = Date(timeIntervalSince1970: 1_754_000_000)
    private struct Unreachable: Error {}

    private func snapshot(
        _ phase: PhoneSessionSnapshot.Phase = .active,
        sentAgo: TimeInterval = 0,
        route: [MirroredRoutePortion] = []
    ) -> PhoneSessionSnapshot {
        PhoneSessionSnapshot(
            sentAt: now.addingTimeInterval(-sentAgo),
            activity: .running,
            phase: phase,
            elapsed: 600,
            steps: 1_800,
            distanceMeters: 1_650,
            activeCalories: 150,
            route: route
        )
    }

    private func session(_ answer: @escaping @Sendable (PhoneSessionCommand) async throws -> Bool = { _ in true })
        -> WatchPhoneSession {
        WatchPhoneSession(sender: PhoneCommandSender(send: answer))
    }

    // MARK: - What is shown

    /// A context and a live message can carry the session in either order.
    @Test("The newest state wins")
    func newestWins() {
        let sut = session()
        sut.receive(snapshot(sentAgo: 0))
        sut.receive(snapshot(.paused, sentAgo: 5))
        #expect(sut.snapshot?.phase == .active)
    }

    @Test("No session from the phone clears what was shown")
    func noSessionClears() {
        let sut = session()
        sut.receive(snapshot())
        sut.receive(nil)
        #expect(sut.shown(at: now) == nil)
    }

    @Test("An ended session is not shown")
    func endedIsHidden() {
        let sut = session()
        sut.receive(snapshot(.ended))
        #expect(sut.shown(at: now) == nil)
    }

    /// The phone app killed mid-walk never says it ended.
    @Test("A session the phone stopped telling of goes stale")
    func staleIsHidden() {
        let sut = session()
        sut.receive(snapshot())
        #expect(sut.shown(at: now.addingTimeInterval(WatchPhoneSession.staleAfter)) != nil)
        #expect(sut.shown(at: now.addingTimeInterval(WatchPhoneSession.staleAfter + 1)) == nil)
    }

    // MARK: - In the wrist's own types

    @Test("The figures are the phone's, with no heart rate")
    func metrics() {
        let metrics = snapshot().metrics
        #expect(metrics.steps == 1_800)
        #expect(metrics.distanceMeters == 1_650)
        #expect(metrics.activeCalories == 150)
        #expect(metrics.heartRate == nil)
        #expect(metrics.activity == .running)
        #expect(metrics.elapsed(at: now.addingTimeInterval(30)) == 630)
        #expect(snapshot(.paused).metrics.elapsed(at: now.addingTimeInterval(30)) == 600)
    }

    @Test("A route keeps the portions that make a line, with stable identities")
    func routePortions() {
        let line = [Coordinate(latitude: 44.83, longitude: -0.57), Coordinate(latitude: 44.84, longitude: -0.58)]
        let route = [
            MirroredRoutePortion(activity: .walking, coordinates: line),
            MirroredRoutePortion(activity: .running, coordinates: [line[0]])
        ]
        let portions = snapshot(route: route).routePortions
        #expect(portions.count == 1)
        #expect(portions.first?.activity == .walking)
        #expect(portions.first?.id == snapshot(route: route).routePortions.first?.id)
    }

    // MARK: - Commands

    @Test("A command the phone carries out leaves nothing to say")
    func commandDone() async {
        let sut = session { command in command == .pause }
        await sut.send(.pause)
        #expect(sut.errorMessage == nil)
        #expect(!sut.isSending)
    }

    /// The phone's own button got there first.
    @Test("A command the phone could not obey is said on screen")
    func commandRefused() async {
        let sut = session { _ in false }
        await sut.send(.stop)
        #expect(sut.errorMessage != nil)
    }

    @Test("A phone out of reach is said on screen")
    func phoneUnreachable() async {
        let sut = session { _ in throw Unreachable() }
        await sut.send(.pause)
        #expect(sut.errorMessage != nil)
    }
}
