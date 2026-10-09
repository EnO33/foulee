import Foundation
import Testing
@testable import FouleeWatch

/// The wrist's half of carrying a phone walk on (issue #335): what the phone
/// offered, and asking it to hand over.
@MainActor
@Suite("Watch phone handoff")
struct WatchPhoneHandoffTests {
    private let now = Date(timeIntervalSince1970: 1_754_000_000)
    private struct Unreachable: Error {}

    private func handoff(at end: Date) -> SessionHandoff {
        SessionHandoff(
            outingID: UUID(),
            phoneLeg: SessionHandoff.Leg(
                activity: .walking, start: end.addingTimeInterval(-300), end: end,
                steps: 500, distanceMeters: 400, activeCalories: 20
            )
        )
    }

    private func handoffClient(
        _ answer: @escaping @Sendable () async throws -> SessionHandoff?
    ) -> WatchPhoneHandoff {
        WatchPhoneHandoff(requester: PhoneHandoffRequester(request: answer))
    }

    // MARK: - What the phone offered

    @Test("The phone's walk in progress is offered until the phone says otherwise")
    func thePhoneSessionIsOffered() {
        let sut = handoffClient { nil }
        sut.receive(phoneSession: PhoneSessionStatus(startedAt: now), handoff: nil)
        #expect(sut.phoneSession == PhoneSessionStatus(startedAt: now))

        sut.receive(phoneSession: nil, handoff: nil)
        #expect(sut.phoneSession == nil)
    }

    /// The application context is resent whole at every change: the same
    /// handoff comes back long after it was used, and must not open a second
    /// leg 1 of the same outing.
    @Test("A handoff is taken up once")
    func takenOnce() {
        let sut = handoffClient { nil }
        let offered = handoff(at: now)
        sut.receive(phoneSession: nil, handoff: offered)

        #expect(sut.takeOffered(at: now) == offered)
        sut.receive(phoneSession: nil, handoff: offered)
        #expect(sut.takeOffered(at: now) == nil)
    }

    /// The watch opened on its own, a day later: that outing is long over.
    @Test("A stale handoff starts the outing fresh")
    func staleIsIgnored() {
        let sut = handoffClient { nil }
        sut.receive(phoneSession: nil, handoff: handoff(at: now))
        #expect(sut.takeOffered(at: now.addingTimeInterval(SessionHandoff.freshness + 1)) == nil)
    }

    // MARK: - « Reprendre la séance de l'iPhone »

    @Test("Asking the phone returns its handoff and stops offering it")
    func askingHandsOver() async {
        let answer = handoff(at: now)
        let sut = handoffClient { answer }
        sut.receive(phoneSession: PhoneSessionStatus(startedAt: now), handoff: nil)

        #expect(await sut.request() == answer)
        #expect(sut.phoneSession == nil)
        #expect(sut.errorMessage == nil)
        #expect(!sut.isRequesting)

        // The context echoes it back: still not a second leg 1.
        sut.receive(phoneSession: nil, handoff: answer)
        #expect(sut.takeOffered(at: now) == nil)
    }

    /// The phone's walk ended a second before the tap landed.
    @Test("A phone with nothing to hand over says so")
    func nothingToHandOver() async {
        let sut = handoffClient { nil }
        sut.receive(phoneSession: PhoneSessionStatus(startedAt: now), handoff: nil)

        #expect(await sut.request() == nil)
        #expect(sut.phoneSession == nil)
        #expect(sut.errorMessage != nil)
    }

    @Test("A phone out of reach is said on screen, and the offer stays")
    func unreachable() async {
        let sut = handoffClient { throw Unreachable() }
        sut.receive(phoneSession: PhoneSessionStatus(startedAt: now), handoff: nil)

        #expect(await sut.request() == nil)
        #expect(sut.errorMessage != nil)
        #expect(sut.phoneSession != nil)
    }

    // MARK: - Woken by the phone (issue #340)

    /// The order on a real wrist: `startWatchApp` lands first, the context
    /// carrying the handoff only once `WCSession` has activated.
    @Test("A start the phone asked for waits for the handoff on its way")
    func waitsForTheHandoff() async {
        let sut = handoffClient { nil }
        let handed = handoff(at: .now)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            sut.receive(phoneSession: nil, handoff: handed)
        }
        #expect(await sut.awaitOffered(timeout: .seconds(5)) == handed)
    }

    /// A phone still mid-walk has not handed over yet: its next word will.
    @Test("A phone still mid-walk is waited for")
    func midWalkIsWaitedFor() async {
        let sut = handoffClient { nil }
        sut.receive(phoneSession: PhoneSessionStatus(startedAt: .now), handoff: nil)
        let handed = handoff(at: .now)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            sut.receive(phoneSession: nil, handoff: handed)
        }
        #expect(await sut.awaitOffered(timeout: .seconds(5)) == handed)
    }

    /// « Démarrer sur la Watch » with no walk on the phone (issue #283) must
    /// not sit out the timeout.
    @Test("No walk on the phone starts at once")
    func noWalkStartsAtOnce() async {
        let sut = handoffClient { nil }
        sut.receive(phoneSession: nil, handoff: nil)
        let clock = ContinuousClock()
        let took = await clock.measure { #expect(await sut.awaitOffered(timeout: .seconds(5)) == nil) }
        #expect(took < .seconds(1))
    }

    @Test("A silent phone does not hold the start back")
    func aSilentPhoneTimesOut() async {
        let sut = handoffClient { nil }
        #expect(await sut.awaitOffered(timeout: .milliseconds(300)) == nil)
    }
}
