import Charts
import SwiftUI

/// HR section of `WorkoutDetailSheet` — min/avg/max trio + a small line
/// chart of the HR samples over the workout's duration.
///
/// Apple Watch records HR every few seconds, so a 30-min walk easily
/// produces 300+ samples. Swift Charts with `.catmullRom` interpolation
/// stays fluid up to ~100 points; past that the sheet feels sluggish
/// to open. We downsample to `maxChartPoints` evenly-spaced samples
/// for rendering only — min/avg/max are still computed on the full
/// set in `WorkoutDetail`, so accuracy isn't affected.
struct WorkoutDetailHeartRate: View {
    private static let maxChartPoints = 60

    let detail: WorkoutDetail

    /// Downsampled once at init — not recomputed on every `body` evaluation.
    private let chartSamples: [HeartRateSample]

    /// Where the finger is on the curve (#319), `nil` when it is not on it.
    @State private var selectedDate: Date?

    init(detail: WorkoutDetail) {
        self.detail = detail
        self.chartSamples = Self.downsample(detail.heartRateSamples)
    }

    private static func downsample(_ all: [HeartRateSample]) -> [HeartRateSample] {
        guard all.count > maxChartPoints else { return all }
        let step = max(all.count / maxChartPoints, 1)
        return all.enumerated().compactMap { offset, sample in
            offset % step == 0 ? sample : nil
        }
    }

    private var heartRateSummary: String {
        func bpm(_ value: Int?) -> String { value.map { "\($0)" } ?? "indisponible" }
        return "Minimum \(bpm(detail.minHeartRate)), "
            + "moyenne \(bpm(detail.averageHeartRate)), "
            + "maximum \(bpm(detail.maxHeartRate)) battements par minute"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(spacing: 0) {
                hrCell(label: "Min", value: detail.minHeartRate)
                divider
                hrCell(label: "Moyenne", value: detail.averageHeartRate)
                divider
                hrCell(label: "Max", value: detail.maxHeartRate)
            }
            chart
                .frame(height: 120)
                .padding(.top, 4)
                // Flatten the chart's rendering into an offscreen bitmap
                // so the sheet's slide-up animation composites a single
                // texture instead of recomputing Swift Charts marks per
                // frame. `drawingGroup()` drops the marks' own a11y, so we
                // describe the curve at the container level instead.
                .drawingGroup()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Courbe de fréquence cardiaque")
                .accessibilityValue(heartRateSummary)
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(.callout, weight: .bold))
                .foregroundStyle(FouleeColor.danger)
            Text("Fréquence cardiaque")
                .font(FouleeFont.headline)
            Spacer()
            if let avg = detail.averageHeartRate {
                Text("\(avg) bpm")
                    .scaledNumericFont(size: 22, weight: .semibold)
                    .foregroundStyle(FouleeColor.danger)
            }
        }
    }

    private func hrCell(label: String, value: Int?) -> some View {
        VStack(spacing: 2) {
            Text(value.map { "\($0)" } ?? "—")
                .scaledNumericFont(size: 18, weight: .semibold)
            Text(label)
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { "\($0) battements par minute" } ?? "indisponible")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.25))
            .frame(width: 1, height: 36)
    }

    private var chart: some View {
        Chart {
            // The outing's legs behind the curve, in the timeline's colours
            // (issue #318), so a climb in heart rate reads against the run that
            // caused it. Nothing for a single session: there is only one leg.
            if detail.summary.legs.count > 1 {
                ForEach(detail.summary.legs) { leg in
                    RectangleMark(
                        xStart: .value("Début", leg.startedAt),
                        xEnd: .value("Fin", leg.endedAt)
                    )
                    .foregroundStyle(leg.activity.tint.opacity(0.14))
                }
            }
            ForEach(chartSamples) { sample in
                curve(sample)
            }
            if let selectedDate, let reading = detail.heartRate(nearest: selectedDate) {
                selection(reading)
            }
        }
        // Read against the full set, not the downsampled curve: the bubble
        // names a real reading, never an interpolated one.
        .chartXSelection(value: $selectedDate)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }

    /// The cursor under the finger: a rule at the reading, a dot on the curve,
    /// and a bubble saying when, how fast the heart was beating, and — on an
    /// outing — which sport was being done.
    @ChartContentBuilder
    private func selection(_ reading: HeartRateSample) -> some ChartContent {
        RuleMark(x: .value("Temps", reading.date))
            .foregroundStyle(Color.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .annotation(
                position: .top,
                spacing: 4,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                bubble(reading)
            }
        PointMark(
            x: .value("Temps", reading.date),
            y: .value("BPM", reading.bpm)
        )
        .foregroundStyle(FouleeColor.danger)
        .symbolSize(60)
    }

    private func bubble(_ reading: HeartRateSample) -> some View {
        let leg = detail.summary.legs.count > 1
            ? OutingBreakdown.leg(at: reading.date, in: detail.summary.legs)
            : nil
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(reading.bpm) bpm")
                .scaledNumericFont(size: 15, weight: .semibold)
                .foregroundStyle(FouleeColor.danger)
            Text(reading.date.clockText)
                .font(FouleeFont.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if let leg {
                Label(leg.activity.label, systemImage: leg.activity.icon)
                    .font(FouleeFont.caption.weight(.semibold))
                    .foregroundStyle(leg.activity.tint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Opaque, not a material: the chart is flattened by `drawingGroup()`,
        // and a blur does not survive being drawn into a bitmap.
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    @ChartContentBuilder
    private func curve(_ sample: HeartRateSample) -> some ChartContent {
        LineMark(
            x: .value("Temps", sample.date),
            y: .value("BPM", sample.bpm)
        )
        .foregroundStyle(FouleeColor.danger)
        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .interpolationMethod(.catmullRom)

        AreaMark(
            x: .value("Temps", sample.date),
            y: .value("BPM", sample.bpm)
        )
        .foregroundStyle(
            LinearGradient(
                colors: [
                    FouleeColor.danger.opacity(0.28),
                    FouleeColor.danger.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .interpolationMethod(.catmullRom)
    }
}
