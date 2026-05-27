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
    private static let maxChartPoints = 80

    let detail: WorkoutDetail

    private var chartSamples: [HeartRateSample] {
        let all = detail.heartRateSamples
        guard all.count > Self.maxChartPoints else { return all }
        let step = max(all.count / Self.maxChartPoints, 1)
        return all.enumerated().compactMap { offset, sample in
            offset % step == 0 ? sample : nil
        }
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
                // frame.
                .drawingGroup()
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(FouleeColor.danger)
            Text("Fréquence cardiaque")
                .font(FouleeFont.headline)
            Spacer()
            if let avg = detail.averageHeartRate {
                Text("\(avg) bpm")
                    .font(FouleeFont.numeric(size: 22, weight: .semibold))
                    .foregroundStyle(FouleeColor.danger)
            }
        }
    }

    private func hrCell(label: String, value: Int?) -> some View {
        VStack(spacing: 2) {
            Text(value.map { "\($0)" } ?? "—")
                .font(FouleeFont.numeric(size: 18, weight: .semibold))
            Text(label)
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.25))
            .frame(width: 1, height: 36)
    }

    private var chart: some View {
        Chart(chartSamples) { sample in
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
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }
}
