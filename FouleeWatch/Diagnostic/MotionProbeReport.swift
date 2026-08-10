import Foundation

/// The device probe's value layer (issue #248): everything the diagnostic
/// screen displays, expressed without importing CoreMotion.
///
/// The point of the probe is to be *trustworthy about what the hardware does*,
/// and a screen whose reading can only be checked by going for a run is not
/// checkable at all. So the shape of a `CMMotionActivity` is mirrored here as
/// plain values — `WatchMotionProbe` does the one-line copy from the real
/// object — and the whole formatting path is a pure function of those values
/// plus a clock. `WatchMotionProbeReportTests` drives every state the wrist
/// could produce, on a simulator, with no motion at all.

/// How sure CoreMotion says it is. Mirrors `CMMotionActivityConfidence`; the
/// raw values are pinned against the real enum in the test suite.
///
/// `unrecognised` exists because a future watchOS could add a level, and
/// folding an unknown value into `low` would put a number on screen that the
/// device never said.
enum MotionProbeConfidence: Int, CaseIterable, Sendable {
    case unrecognised = -1
    case low = 0
    case medium = 1
    case high = 2

    var label: String {
        switch self {
        case .unrecognised: "inconnue"
        case .low: "faible"
        case .medium: "moyenne"
        case .high: "élevée"
        }
    }
}

/// Mirrors `CMAuthorizationStatus`. Same reasoning as above for
/// `unrecognised`, and the raw values are pinned against CoreMotion's.
enum MotionProbeAuthorization: Int, CaseIterable, Sendable {
    case unrecognised = -1
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorized = 3

    var label: String {
        switch self {
        case .unrecognised: "inconnue"
        case .notDetermined: "pas encore demandée"
        case .restricted: "restreinte"
        case .denied: "refusée"
        case .authorized: "accordée"
        }
    }
}

/// The six booleans a `CMMotionActivity` carries.
///
/// An enum rather than six properties read one by one, because the display
/// must show each of them *independently*: they are not mutually exclusive,
/// several can be true at once, and they can all be false. Collapsing them
/// into a single verdict — the obvious, wrong design — would put « marche »
/// on screen at moments when the device asserted nothing, and the entire
/// point of the probe is to tell those two apart.
enum MotionProbeFlag: String, CaseIterable, Sendable {
    case walking
    case running
    case stationary
    case unknown
    case cycling
    case automotive

    var label: String {
        switch self {
        case .walking: "marche"
        case .running: "course"
        case .stationary: "immobile"
        case .unknown: "inconnu"
        case .cycling: "vélo"
        case .automotive: "voiture"
        }
    }
}

/// One `CMMotionActivity`, flattened.
///
/// `startDate` is the device's own stamp for when the activity began;
/// `receivedAt` is when this process was handed it. Both are shown, and they
/// are not the same question: a stale `startDate` with a fresh `receivedAt` is
/// a live stream reporting an activity that started a while ago, whereas a
/// stale `receivedAt` is a stream that has gone quiet.
struct MotionProbeEstimate: Equatable, Sendable {
    var startDate: Date
    var receivedAt: Date
    var confidence: MotionProbeConfidence
    var walking: Bool
    var running: Bool
    var stationary: Bool
    var unknown: Bool
    var cycling: Bool
    var automotive: Bool

    func isSet(_ flag: MotionProbeFlag) -> Bool {
        switch flag {
        case .walking: walking
        case .running: running
        case .stationary: stationary
        case .unknown: unknown
        case .cycling: cycling
        case .automotive: automotive
        }
    }

    /// Every flag the device actually asserted — possibly none, possibly
    /// several.
    var activeFlags: [MotionProbeFlag] {
        MotionProbeFlag.allCases.filter(isSet)
    }
}

/// Everything the probe knows right now.
///
/// Everything below the two capability answers describes **one listening
/// window** — the stretch since `startedAt`, and nothing before it. That is not
/// bookkeeping tidiness: « Écoute depuis » and « Estimations reçues » are read
/// as a *pair*, and that pair is the whole way of telling « rien ne bouge »
/// apart from « le flux est mort ». Let a count from an earlier visit to the
/// screen sit next to a clock that restarted seconds ago and a dead stream
/// reads as a healthy one.
struct MotionProbeState: Equatable, Sendable {
    var isAvailable = false
    var authorization = MotionProbeAuthorization.notDetermined
    /// When the stream was opened. Nil means it is not open — which is why
    /// "zero estimates" is not on its own evidence of a dead stream.
    var startedAt: Date?
    var estimateCount = 0
    var latest: MotionProbeEstimate?

    /// Open a window. Called when the stream opens, including on a reopen of
    /// the screen mid-outing.
    mutating func openWindow(at date: Date) {
        startedAt = date
        estimateCount = 0
        latest = nil
    }

    /// Close it, when the stream closes. `startedAt` must not outlive the
    /// stream it describes: left behind, it puts « Écoute depuis : il y a
    /// 12 min » on a screen that is listening to nothing.
    mutating func closeWindow() {
        startedAt = nil
        estimateCount = 0
        latest = nil
    }
}

/// One displayed line. `tone` only colours it; the text says everything.
struct MotionProbeRow: Equatable, Identifiable, Sendable {
    enum Tone: Sendable {
        case plain
        /// The device said yes.
        case on
        /// The device said no.
        case off
        /// Something the owner must notice: unavailable, denied, no stream.
        case alert
    }

    var label: String
    var value: String
    var tone: Tone = .plain

    var id: String { label }
}

/// Turns a `MotionProbeState` into the lines on screen. Pure: same inputs,
/// same rows, on a Mac as on a wrist.
enum MotionProbeReport {
    /// Placeholder for "there is nothing to say yet" — never a zero, which
    /// would read as a measurement.
    static let noValue = "—"

    static func rows(for state: MotionProbeState, now: Date, calendar: Calendar = .current) -> [MotionProbeRow] {
        capabilityRows(for: state, now: now)
            + estimateRows(for: state, now: now, calendar: calendar)
            + flagRows(for: state.latest)
    }

    /// The two class-level answers, plus the evidence that tells "nothing is
    /// moving" apart from "the stream is dead": how long we have been
    /// listening, and how many estimates that produced.
    private static func capabilityRows(for state: MotionProbeState, now: Date) -> [MotionProbeRow] {
        [
            MotionProbeRow(
                label: "Disponible",
                value: state.isAvailable ? "oui" : "non",
                tone: state.isAvailable ? .on : .alert
            ),
            MotionProbeRow(
                label: "Autorisation",
                value: state.authorization.label,
                tone: state.authorization == .authorized ? .on : .alert
            ),
            MotionProbeRow(
                label: "Écoute depuis",
                value: state.startedAt.map { elapsedText(now.timeIntervalSince($0)) } ?? "flux non ouvert",
                tone: state.startedAt == nil ? .alert : .plain
            ),
            MotionProbeRow(
                label: "Estimations reçues",
                value: "\(state.estimateCount)",
                tone: state.estimateCount == 0 ? .alert : .plain
            )
        ]
    }

    private static func estimateRows(
        for state: MotionProbeState,
        now: Date,
        calendar: Calendar
    ) -> [MotionProbeRow] {
        guard let latest = state.latest else {
            return [
                MotionProbeRow(label: "Dernière reçue", value: "aucune", tone: .alert),
                MotionProbeRow(label: "Début de l'activité", value: noValue),
                MotionProbeRow(label: "Confiance", value: noValue),
                MotionProbeRow(label: "Drapeaux actifs", value: noValue)
            ]
        }
        let active = latest.activeFlags
        return [
            MotionProbeRow(label: "Dernière reçue", value: elapsedText(now.timeIntervalSince(latest.receivedAt))),
            MotionProbeRow(label: "Début de l'activité", value: timeText(latest.startDate, calendar: calendar)),
            MotionProbeRow(label: "Confiance", value: latest.confidence.label),
            // Named « drapeaux » and not « activité »: this line is a list of
            // what the device asserted, and « aucun » is a real, frequent
            // answer that must be readable as such.
            MotionProbeRow(
                label: "Drapeaux actifs",
                value: active.isEmpty ? "aucun" : active.map(\.label).joined(separator: " + "),
                tone: active.isEmpty ? .alert : .on
            )
        ]
    }

    /// Every flag on its own line, always all six, whether or not an estimate
    /// has arrived — a flag that disappears from the screen when false is a
    /// flag nobody can report on.
    private static func flagRows(for estimate: MotionProbeEstimate?) -> [MotionProbeRow] {
        MotionProbeFlag.allCases.map { flag in
            guard let estimate else {
                return MotionProbeRow(label: flag.label, value: noValue)
            }
            let isSet = estimate.isSet(flag)
            return MotionProbeRow(label: flag.label, value: isSet ? "oui" : "non", tone: isSet ? .on : .off)
        }
    }

    /// « il y a 4 s » / « il y a 2 min 07 s ». Negative intervals — a device
    /// clock stamp slightly ahead of ours — clamp to zero rather than printing
    /// a nonsense past.
    static func elapsedText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        guard seconds >= 60 else { return "il y a \(seconds) s" }
        return String(format: "il y a %d min %02d s", seconds / 60, seconds % 60)
    }

    /// Wall clock, to the second, because the number being hunted here is a
    /// latency. Deliberately not a locale-formatted style: the owner is
    /// comparing this against a stopwatch, not reading prose.
    static func timeText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}
