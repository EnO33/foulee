import CoreMotion
import Foundation
import Testing
@testable import FouleeWatch

/// The device probe's readings (issue #248).
///
/// The probe exists to be *trustworthy about what the hardware does*, so its
/// display has to be checkable without hardware. Everything past the one-line
/// copy out of `CMMotionActivity` is a pure function, and this suite drives
/// every state a wrist could produce — including the two that matter most and
/// that a naive display gets wrong: **all six flags false**, and **several true
/// at once**.
@Suite("Watch motion probe report")
struct WatchMotionProbeReportTests {
    /// A fixed wall clock, so « il y a 4 s » is a fact and not the weather.
    /// 1 754 000 000 is 22:13:20 UTC.
    private let now = Date(timeIntervalSince1970: 1_754_000_000)

    /// UTC, so the timestamp row reads the same on any machine.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func estimate(
        confidence: MotionProbeConfidence = .medium,
        walking: Bool = false,
        running: Bool = false,
        stationary: Bool = false,
        unknown: Bool = false,
        cycling: Bool = false,
        automotive: Bool = false,
        startedAgo: TimeInterval = 12,
        receivedAgo: TimeInterval = 3
    ) -> MotionProbeEstimate {
        MotionProbeEstimate(
            startDate: now.addingTimeInterval(-startedAgo),
            receivedAt: now.addingTimeInterval(-receivedAgo),
            confidence: confidence,
            walking: walking,
            running: running,
            stationary: stationary,
            unknown: unknown,
            cycling: cycling,
            automotive: automotive
        )
    }

    private func state(
        _ estimate: MotionProbeEstimate?,
        isAvailable: Bool = true,
        authorization: MotionProbeAuthorization = .authorized,
        count: Int = 1,
        listeningFor: TimeInterval? = 30
    ) -> MotionProbeState {
        MotionProbeState(
            isAvailable: isAvailable,
            authorization: authorization,
            startedAt: listeningFor.map { now.addingTimeInterval(-$0) },
            estimateCount: count,
            latest: estimate
        )
    }

    private func rows(_ state: MotionProbeState) -> [MotionProbeRow] {
        MotionProbeReport.rows(for: state, now: now, calendar: utc)
    }

    private func value(_ label: String, _ rows: [MotionProbeRow]) throws -> String {
        try #require(rows.first { $0.label == label }, "no row labelled \(label)").value
    }

    private var flagLabels: [String] { MotionProbeFlag.allCases.map(\.label) }

    // MARK: - The two states a naive display collapses

    @Test("All six flags false is shown as such, and never as an activity")
    func allFlagsFalseIsVisible() throws {
        // The single most important property of this screen. CoreMotion can
        // and does deliver an estimate asserting nothing at all; a display
        // that answered « marche » here — because walking is the app's
        // historical default, or because a `switch` needed a last case — would
        // send #244 down a wrong path with no way to notice.
        let built = rows(state(estimate()))

        for flag in MotionProbeFlag.allCases {
            let shown = try value(flag.label, built)
            #expect(shown == "non")
        }
        let summary = try value("Drapeaux actifs", built)
        #expect(summary == "aucun")

        // And nothing anywhere on the screen puts an activity forward as the
        // reading.
        let claimed = Set(built.map(\.value))
        for label in flagLabels {
            #expect(claimed.contains(label) == false)
        }
    }

    @Test("Several flags true at once are all shown, not reduced to one")
    func severalFlagsTrueAreAllShown() throws {
        // The flags are not mutually exclusive. Walking and running asserted
        // together is exactly the transition #248 is trying to time, and a
        // display that picked a winner would hide the moment it happens.
        let built = rows(state(estimate(walking: true, running: true, stationary: true)))

        #expect(try value("marche", built) == "oui")
        #expect(try value("course", built) == "oui")
        #expect(try value("immobile", built) == "oui")
        #expect(try value("inconnu", built) == "non")
        #expect(try value("vélo", built) == "non")
        #expect(try value("voiture", built) == "non")
        #expect(try value("Drapeaux actifs", built) == "marche + course + immobile")
    }

    @Test("Each flag gets its own line, and all six are always listed")
    func everyFlagHasItsOwnRow() throws {
        for flag in MotionProbeFlag.allCases {
            let only = estimate(
                walking: flag == .walking,
                running: flag == .running,
                stationary: flag == .stationary,
                unknown: flag == .unknown,
                cycling: flag == .cycling,
                automotive: flag == .automotive
            )
            let built = rows(state(only))
            let shown = try value(flag.label, built)
            let summary = try value("Drapeaux actifs", built)

            #expect(shown == "oui")
            #expect(summary == flag.label)
            // A flag that disappeared from the screen when false would be a
            // flag nobody can report on.
            #expect(built.count { flagLabels.contains($0.label) } == MotionProbeFlag.allCases.count)
        }
    }

    // MARK: - Confidence

    @Test("Every confidence level reads distinctly")
    func confidenceLevels() throws {
        let expected: [MotionProbeConfidence: String] = [
            .low: "faible",
            .medium: "moyenne",
            .high: "élevée",
            .unrecognised: "inconnue"
        ]
        for (level, label) in expected {
            let shown = try value("Confiance", rows(state(estimate(confidence: level))))
            #expect(shown == label)
        }
        // Four levels, four readings — a table where two collapsed would make
        // « faible » and « élevée » indistinguishable on the wrist, and
        // confidence is half of how a transition is judged.
        #expect(Set(expected.values).count == MotionProbeConfidence.allCases.count)
    }

    @Test("Confidence mirrors CoreMotion's own constants")
    func confidenceRawValuesMatchCoreMotion() {
        // The bridge out of `CMMotionActivity` maps by raw value, so this is
        // the one thing that could silently mislabel every reading taken on
        // the wrist. Pinned rather than trusted.
        #expect(MotionProbeConfidence.low.rawValue == CMMotionActivityConfidence.low.rawValue)
        #expect(MotionProbeConfidence.medium.rawValue == CMMotionActivityConfidence.medium.rawValue)
        #expect(MotionProbeConfidence.high.rawValue == CMMotionActivityConfidence.high.rawValue)
    }

    @Test("Authorization mirrors CoreMotion's constants, and each status reads distinctly")
    func authorizationRawValuesMatchCoreMotion() throws {
        #expect(MotionProbeAuthorization.notDetermined.rawValue == CMAuthorizationStatus.notDetermined.rawValue)
        #expect(MotionProbeAuthorization.restricted.rawValue == CMAuthorizationStatus.restricted.rawValue)
        #expect(MotionProbeAuthorization.denied.rawValue == CMAuthorizationStatus.denied.rawValue)
        #expect(MotionProbeAuthorization.authorized.rawValue == CMAuthorizationStatus.authorized.rawValue)

        for status in MotionProbeAuthorization.allCases {
            let shown = try value("Autorisation", rows(state(estimate(), authorization: status)))
            #expect(shown == status.label)
        }
        let labels = Set(MotionProbeAuthorization.allCases.map(\.label))
        #expect(labels.count == MotionProbeAuthorization.allCases.count)
    }

    // MARK: - « rien ne bouge » vs « le flux est mort »

    @Test("A stream open for minutes with nothing received says so")
    func silentStreamIsDistinguishableFromAStillWearer() throws {
        // Zero estimates is not, on its own, evidence of anything: it means
        // one thing after four minutes of listening and another after four
        // seconds. Both numbers are on screen for exactly that reason.
        let built = rows(state(nil, count: 0, listeningFor: 240))

        #expect(try value("Écoute depuis", built) == "il y a 4 min 00 s")
        #expect(try value("Estimations reçues", built) == "0")
        #expect(try value("Dernière reçue", built) == "aucune")
        #expect(try value("Confiance", built) == MotionProbeReport.noValue)
        // The flags stay listed, with no value — not « non », which would be
        // a claim the device never made.
        for flag in MotionProbeFlag.allCases {
            let shown = try value(flag.label, built)
            #expect(shown == MotionProbeReport.noValue)
        }
    }

    @Test("A stream that was never opened says that, rather than showing a zero")
    func unopenedStreamSaysSo() throws {
        let built = rows(state(nil, isAvailable: false, count: 0, listeningFor: nil))
        #expect(try value("Disponible", built) == "non")
        #expect(try value("Écoute depuis", built) == "flux non ouvert")
    }

    @Test("A live stream reports both the age of its last estimate and the activity's own start")
    func ageAndTimestampAreBothShown() throws {
        let built = rows(state(estimate(startedAgo: 90, receivedAgo: 7)))
        #expect(try value("Dernière reçue", built) == "il y a 7 s")
        // 22:13:20 − 90 s. The device's own stamp for when the activity began,
        // which is a different question from when we were handed it: a fresh
        // delivery about an activity that started a minute ago is the shape a
        // smoothed, late transition would take.
        #expect(try value("Début de l'activité", built) == "22:11:50")
    }

    @Test("Elapsed text stays honest at the edges")
    func elapsedFormatting() {
        #expect(MotionProbeReport.elapsedText(0) == "il y a 0 s")
        #expect(MotionProbeReport.elapsedText(59) == "il y a 59 s")
        #expect(MotionProbeReport.elapsedText(60) == "il y a 1 min 00 s")
        #expect(MotionProbeReport.elapsedText(3_607) == "il y a 60 min 07 s")
        // A device stamp slightly ahead of ours must not print a future.
        #expect(MotionProbeReport.elapsedText(-4) == "il y a 0 s")
    }

    // MARK: - Availability and authorization are flagged, not buried

    @Test("Unavailable and unauthorized are marked as things to notice")
    func problemsAreToned() throws {
        let broken = rows(state(nil, isAvailable: false, authorization: .denied, count: 0, listeningFor: nil))
        #expect(broken.first { $0.label == "Disponible" }?.tone == .alert)
        #expect(broken.first { $0.label == "Autorisation" }?.tone == .alert)

        let healthy = rows(state(estimate(walking: true)))
        #expect(healthy.first { $0.label == "Disponible" }?.tone == .on)
        #expect(healthy.first { $0.label == "Autorisation" }?.tone == .on)
    }

    // MARK: - The stream bookkeeping

    @Test("Estimates accumulate and the newest one wins")
    @MainActor
    func ingestCountsAndReplaces() {
        let probe = WatchMotionProbe()
        #expect(probe.state.estimateCount == 0)
        #expect(probe.state.latest == nil)

        probe.ingest(estimate(walking: true))
        probe.ingest(estimate(running: true))

        // The count is what makes a dead stream visible; it must not reset
        // when a newer estimate lands.
        #expect(probe.state.estimateCount == 2)
        #expect(probe.state.latest?.running == true)
        #expect(probe.state.latest?.walking == false)
    }
}
