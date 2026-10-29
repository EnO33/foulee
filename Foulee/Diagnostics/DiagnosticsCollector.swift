import FouleeKit
import Foundation
@preconcurrency import MetricKit
import os

/// MetricKit's crash, hang and launch diagnostics, kept on the device
/// (issue #610). Nothing is sent anywhere: « Signaler un problème » shows the
/// summary and lets the user attach it, or share the full report, themselves.
nonisolated final class DiagnosticsCollector: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = DiagnosticsCollector()

    /// One writer at a time: MetricKit delivers on its own queue, the page
    /// reads from a task.
    private let lock = OSAllocatedUnfairLock()

    private let fileURL = URL.applicationSupportDirectory.appending(path: "Diagnostics/records.json")

    /// Once per process, from `FouleeApp`: MetricKit delivers what it
    /// gathered since the last launch to the subscribers it finds.
    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let now = Date.now
        let records = payloads.map { Self.record($0, receivedAt: now) }
        lock.withLock {
            let kept = DiagnosticHistory.adding(records, to: storedRecords(), now: now)
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                // Readable after the first unlock: MetricKit can deliver with
                // the phone locked, and an unreadable file would read as empty
                // and be overwritten.
                try JSONEncoder().encode(kept)
                    .write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                // MetricKit's callback is the highest boundary: nothing above
                // it can handle a failed write, and the payload is gone.
                FouleeLog.background.error(
                    "diagnostics : écriture impossible : \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// The report « Signaler un problème » offers to attach, read off the
    /// main actor.
    @concurrent
    func report() async -> ProblemReport {
        let records = lock.withLock { storedRecords() }
        return ProblemReport(
            version: AppVersion.current,
            device: Self.deviceModel,
            system: Self.systemVersion,
            records: records
        )
    }

    /// No file yet, or one an older format can't read: nothing kept.
    private func storedRecords() -> [DiagnosticRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([DiagnosticRecord].self, from: data)) ?? []
    }

    private static func record(_ payload: MXDiagnosticPayload, receivedAt: Date) -> DiagnosticRecord {
        let date = payload.timeStampEnd
        let crashes = (payload.crashDiagnostics ?? []).map {
            DiagnosticIncident.crash(
                date: date,
                version: $0.applicationVersion,
                exceptionType: $0.exceptionType?.intValue,
                signal: $0.signal?.intValue,
                terminationReason: $0.terminationReason
            )
        }
        func durations<Diagnostic: MXDiagnostic>(
            _ diagnostics: [Diagnostic]?,
            _ kind: DiagnosticIncident.Kind,
            _ duration: (Diagnostic) -> Measurement<UnitDuration>
        ) -> [DiagnosticIncident] {
            (diagnostics ?? []).map {
                .duration(kind, date: date, version: $0.applicationVersion, duration: duration($0))
            }
        }
        let disk = (payload.diskWriteExceptionDiagnostics ?? []).map {
            DiagnosticIncident.diskWrites(date: date, version: $0.applicationVersion, written: $0.totalWritesCaused)
        }
        return DiagnosticRecord(
            receivedAt: receivedAt,
            incidents: crashes
                + durations(payload.hangDiagnostics, .hang, \.hangDuration)
                + durations(payload.appLaunchDiagnostics, .slowLaunch, \.launchDuration)
                + durations(payload.cpuExceptionDiagnostics, .cpuException, \.totalCPUTime)
                + disk,
            payload: String(bytes: payload.jsonRepresentation(), encoding: .utf8) ?? ""
        )
    }

    /// The hardware identifier, « iPhone18,1 »: `UIDevice.model` only says
    /// « iPhone ».
    private static let deviceModel: String = {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
        }
    }()

    private static let systemVersion: String = {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
    }()
}
