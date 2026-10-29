import Foundation
import Testing
@testable import FouleeKit

/// MetricKit diagnostics kept on the device and attached to a report (issue #610).
@Suite("Diagnostics")
struct DiagnosticsTests {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func record(daysAgo: Double, payload: String, incidents: [DiagnosticIncident] = []) -> DiagnosticRecord {
        DiagnosticRecord(receivedAt: now.addingTimeInterval(-daysAgo * day), incidents: incidents, payload: payload)
    }

    @Test("A crash reads as its exception, its signal and its reason")
    func crashDetail() {
        let crash = DiagnosticIncident.crash(
            date: now, version: "1.52 (123)", exceptionType: 1, signal: 11, terminationReason: "Namespace SIGNAL"
        )
        #expect(crash.kind == .crash)
        #expect(crash.detail == "EXC_BAD_ACCESS · SIGSEGV · Namespace SIGNAL")
    }

    @Test("An unknown code keeps its number, a crash with nothing known says so")
    func crashUnknown() {
        let numbered = DiagnosticIncident.crash(date: now, version: nil, exceptionType: 42, signal: 31, terminationReason: nil)
        #expect(numbered.detail == "EXC 42 · signal 31")
        let empty = DiagnosticIncident.crash(date: now, version: nil, exceptionType: nil, signal: nil, terminationReason: nil)
        #expect(empty.detail == "unknown")
    }

    @Test("A long termination reason is cut short")
    func longReason() {
        let reason = String(repeating: "x", count: 500)
        let crash = DiagnosticIncident.crash(date: now, version: nil, exceptionType: nil, signal: nil, terminationReason: reason)
        #expect(crash.detail.count == DiagnosticIncident.terminationReasonLength)
    }

    @Test("A hang reads as its duration")
    func hangDetail() {
        let hang = DiagnosticIncident.duration(.hang, date: now, version: nil, duration: Measurement(value: 2430, unit: .milliseconds))
        #expect(hang.detail == "2.4 s")
    }

    @Test("Disk writes read in megabytes")
    func diskDetail() {
        let written = Measurement(value: 2.5, unit: UnitInformationStorage.gigabytes)
        let disk = DiagnosticIncident.diskWrites(date: now, version: nil, written: written)
        #expect(disk.kind == .diskWriteException)
        #expect(disk.detail == "2500 MB")
    }

    @Test("The history keeps the newest first and a payload once")
    func historyOrder() {
        let old = record(daysAgo: 3, payload: "a")
        let recent = record(daysAgo: 1, payload: "b")
        let again = record(daysAgo: 0, payload: "a")
        let kept = DiagnosticHistory.adding([recent, again], to: [old], now: now)
        #expect(kept.map(\.payload) == ["a", "b"])
    }

    @Test("A payload older than a month is dropped")
    func historyAge() {
        let kept = DiagnosticHistory.adding([record(daysAgo: 31, payload: "old")], to: [record(daysAgo: 29, payload: "kept")], now: now)
        #expect(kept.map(\.payload) == ["kept"])
    }

    @Test("The history keeps at most its limit")
    func historyLimit() {
        let records = (0..<15).map { record(daysAgo: Double($0), payload: "\($0)") }
        let kept = DiagnosticHistory.adding(records, to: [], now: now)
        #expect(kept.count == DiagnosticHistory.recordLimit)
        #expect(kept.first?.payload == "0")
    }

    @Test("The summary names the build, the device and each incident, newest first")
    func summary() throws {
        let crash = DiagnosticIncident.crash(
            date: now.addingTimeInterval(-day), version: "1.51", exceptionType: 6, signal: 5, terminationReason: nil
        )
        let hang = DiagnosticIncident.duration(.hang, date: now, version: nil, duration: Measurement(value: 3, unit: .seconds))
        let report = ProblemReport(
            version: "1.52 (123)", device: "iPhone18,1", system: "iOS 26.1",
            records: [record(daysAgo: 0, payload: "{}", incidents: [crash, hang])]
        )
        let lines = report.summary.split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0] == "Foulée 1.52 (123) · iPhone18,1 · iOS 26.1")
        #expect(lines[1].hasSuffix("UTC hang: 3.0 s"))
        #expect(lines[2].hasSuffix("UTC crash (1.51): EXC_BREAKPOINT · SIGTRAP"))
    }

    @Test("Without an incident the summary says so")
    func emptySummary() {
        let report = ProblemReport(version: "1.52", device: "iPhone18,1", system: "iOS 26.1", records: [])
        #expect(report.summary.hasSuffix("No incident recorded."))
    }

    @Test("The summary lists at most its limit of incidents")
    func summaryLimit() {
        let incidents = (0..<25).map {
            DiagnosticIncident.duration(
                .hang, date: now.addingTimeInterval(Double(-$0)), version: nil, duration: Measurement(value: 1, unit: .seconds)
            )
        }
        let report = ProblemReport(
            version: "1", device: "d", system: "s", records: [record(daysAgo: 0, payload: "p", incidents: incidents)]
        )
        #expect(report.incidents.count == ProblemReport.incidentLimit)
    }

    @Test("The full report adds every payload; the issue body leaves room above the summary")
    func reports() {
        let report = ProblemReport(
            version: "1", device: "d", system: "s",
            records: [record(daysAgo: 0, payload: "{\"one\":1}"), record(daysAgo: 1, payload: "{\"two\":2}")]
        )
        #expect(report.fullReport.contains("{\"one\":1}"))
        #expect(report.fullReport.contains("{\"two\":2}"))
        #expect(!report.issueBody.contains("{\"one\":1}"))
        #expect(report.issueBody.hasPrefix("\n\n"))
        #expect(report.issueBody.contains(report.summary))
    }
}
