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
}
