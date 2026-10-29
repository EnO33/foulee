import Foundation

/// One thing MetricKit saw go wrong (issue #610): a crash, a hang, a launch
/// too slow, an exception for CPU or disk use. Only what tells the kind of
/// failure apart — no call stack, no message text, nothing the user did.
nonisolated public struct DiagnosticIncident: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case crash, hang, slowLaunch, cpuException, diskWriteException
    }

    public var kind: Kind
    public var date: Date
    /// The build that failed, « 1.52 (123) », when MetricKit says.
    public var version: String?
    /// « EXC_BAD_ACCESS · SIGSEGV », « 2.4 s »: short, technical, in English.
    public var detail: String

    public init(kind: Kind, date: Date, version: String?, detail: String) {
        self.kind = kind
        self.date = date
        self.version = version
        self.detail = detail
    }

    /// A crash as MetricKit numbers it: Mach exception type and signal, plus
    /// the system's termination reason, cut short.
    public static func crash(
        date: Date,
        version: String?,
        exceptionType: Int?,
        signal: Int?,
        terminationReason: String?
    ) -> DiagnosticIncident {
        let reason = terminationReason.map { String($0.prefix(terminationReasonLength)) }
        let parts = [exceptionType.map(exceptionName), signal.map(signalName), reason].compactMap(\.self)
        return DiagnosticIncident(
            kind: .crash,
            date: date,
            version: version,
            detail: parts.isEmpty ? "unknown" : parts.joined(separator: " · ")
        )
    }

    /// A hang, a slow launch or CPU time over budget, in seconds.
    public static func duration(
        _ kind: Kind,
        date: Date,
        version: String?,
        duration: Measurement<UnitDuration>
    ) -> DiagnosticIncident {
        let seconds = duration.converted(to: .seconds).value
        return DiagnosticIncident(kind: kind, date: date, version: version, detail: String(format: "%.1f s", seconds))
    }

    /// Disk writes over budget, in megabytes.
    public static func diskWrites(
        date: Date,
        version: String?,
        written: Measurement<UnitInformationStorage>
    ) -> DiagnosticIncident {
        let megabytes = written.converted(to: .megabytes).value
        return DiagnosticIncident(
            kind: .diskWriteException, date: date, version: version, detail: String(format: "%.0f MB", megabytes)
        )
    }

    static let terminationReasonLength = 120

    static func exceptionName(_ type: Int) -> String {
        switch type {
        case 1: "EXC_BAD_ACCESS"
        case 2: "EXC_BAD_INSTRUCTION"
        case 3: "EXC_ARITHMETIC"
        case 5: "EXC_SOFTWARE"
        case 6: "EXC_BREAKPOINT"
        case 10: "EXC_CRASH"
        case 11: "EXC_RESOURCE"
        case 12: "EXC_GUARD"
        default: "EXC \(type)"
        }
    }

    static func signalName(_ signal: Int) -> String {
        switch signal {
        case 4: "SIGILL"
        case 5: "SIGTRAP"
        case 6: "SIGABRT"
        case 8: "SIGFPE"
        case 9: "SIGKILL"
        case 10: "SIGBUS"
        case 11: "SIGSEGV"
        default: "signal \(signal)"
        }
    }
}

/// One MetricKit diagnostic payload as kept on the device: what it says in
/// short, and the payload itself, call stacks included, for a full report the
/// user chooses to share.
nonisolated public struct DiagnosticRecord: Codable, Equatable, Sendable {
    public var receivedAt: Date
    public var incidents: [DiagnosticIncident]
    /// MetricKit's JSON representation of the payload.
    public var payload: String

    public init(receivedAt: Date, incidents: [DiagnosticIncident], payload: String) {
        self.receivedAt = receivedAt
        self.incidents = incidents
        self.payload = payload
    }
}

/// The payloads the device keeps (issue #610): the most recent ones, never
/// older than a month. Nothing leaves the device from here.
nonisolated public enum DiagnosticHistory {
    static let recordLimit = 10
    static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    /// `existing` with `new` added, newest first: a payload MetricKit hands
    /// over twice is kept once, an old one or one past the limit is dropped.
    public static func adding(
        _ new: [DiagnosticRecord],
        to existing: [DiagnosticRecord],
        now: Date
    ) -> [DiagnosticRecord] {
        var kept: [DiagnosticRecord] = []
        for record in (new + existing).sorted(by: { $0.receivedAt > $1.receivedAt })
        where now.timeIntervalSince(record.receivedAt) <= maximumAge
            && !kept.contains(where: { $0.payload == record.payload }) {
            kept.append(record)
        }
        return Array(kept.prefix(recordLimit))
    }
}

/// What « Signaler un problème » proposes to attach (issue #610): the build,
/// the device, the system and the latest incidents. No health data, ever.
nonisolated public struct ProblemReport: Equatable, Sendable {
    /// The latest incidents, newest first.
    public let incidents: [DiagnosticIncident]
    /// The short summary, for a public issue: one line per incident, no call
    /// stack. Technical, so not translated: it is read by the maintainer.
    public let summary: String
    /// The summary followed by every payload kept, call stacks included, for
    /// a report the user sends privately.
    public let fullReport: String

    /// Built once, off the main actor: the payloads can weigh hundreds of
    /// kilobytes, and the page reads these strings on every redraw.
    public init(version: String, device: String, system: String, records: [DiagnosticRecord]) {
        let incidents = Array(records.flatMap(\.incidents).sorted { $0.date > $1.date }.prefix(Self.incidentLimit))
        var lines = ["Foulée \(version) · \(device) · \(system)"]
        if incidents.isEmpty {
            lines.append("No incident recorded.")
        } else {
            lines += incidents.map { incident in
                let date = incident.date.formatted(Self.dateStyle)
                let version = incident.version.map { " (\($0))" } ?? ""
                return "- \(date) UTC \(incident.kind.rawValue)\(version): \(incident.detail)"
            }
        }
        self.incidents = incidents
        self.summary = lines.joined(separator: "\n")
        self.fullReport = ([summary] + records.map(\.payload)).joined(separator: "\n\n")
    }

    static let incidentLimit = 10

    /// The body of a new issue: room for the user's words first, the summary
    /// below in a code block.
    public var issueBody: String {
        "\n\n---\n```\n\(summary)\n```\n"
    }

    private static let dateStyle = Date.ISO8601FormatStyle(timeZone: .gmt)
        .year().month().day().dateTimeSeparator(.space).time(includingFractionalSeconds: false)
}
