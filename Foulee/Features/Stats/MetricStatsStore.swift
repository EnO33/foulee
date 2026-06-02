import Dependencies
import Foundation
import Observation

/// The three temporalities the per-metric stats screen charts.
enum MetricRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Aujourd'hui"
        case .week: "Semaine"
        case .month: "Mois"
        }
    }

    /// Daily history depth for the daily ranges (today uses an hourly query).
    var daysBack: Int {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        }
    }
}

/// Loads one `WalkMetric`'s series for the active range (hourly for today,
/// daily for week/month) and derives the headline summary. Mirrors the
/// `runOrTrap` single-boundary error handling of the other stores.
@MainActor
@Observable
final class MetricStatsStore {
    let metric: WalkMetric
    private(set) var points: [MetricPoint] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    var range: MetricRange = .week

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    init(metric: WalkMetric) {
        self.metric = metric
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let loaded: [MetricPoint]?
        switch range {
        case .today:
            loaded = await runOrTrap { try await healthKit.hourlyToday(metric) }
        case .week, .month:
            loaded = await runOrTrap { try await healthKit.metricSeries(metric, range.daysBack) }
        }
        points = loaded ?? []
    }

    // MARK: - Summary (pure, derived from `points`)

    /// Sum across all buckets — today's total, or the week/month total.
    var total: Double { points.reduce(0) { $0 + $1.value } }

    /// Mean per non-empty bucket (per active hour today, per logged day else).
    var average: Double {
        let active = points.filter { $0.value > 0 }
        guard !active.isEmpty else { return 0 }
        return total / Double(active.count)
    }

    /// Best single bucket (best hour today, best day otherwise).
    var best: Double { points.map(\.value).max() ?? 0 }

    var isEmpty: Bool { points.allSatisfy { $0.value == 0 } }

    private func runOrTrap<T: Sendable>(_ body: () async throws -> T) async -> T? {
        do {
            return try await body()
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
