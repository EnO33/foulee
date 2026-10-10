import SwiftUI

/// Today at a glance (issue #355): a drop filling up to the goal, the litres,
/// and where the day stands against its rhythm.
struct HydrationTodayHero: View {
    let intakeML: Int
    let goalML: Int
    let pace: HydrationPace

    private var progress: Double { HydrationMath.progress(intakeML: intakeML, goalML: goalML) }

    var body: some View {
        HStack(spacing: 20) {
            ZStack(alignment: .bottom) {
                DropShape()
                    .fill(HydrationCard.water.opacity(0.12))
                Rectangle()
                    .fill(HydrationCard.water.gradient)
                    .scaleEffect(x: 1, y: progress, anchor: .bottom)
                    .mask(DropShape())
                DropShape()
                    .stroke(HydrationCard.water.opacity(0.6), lineWidth: 2)
            }
            .frame(width: 84, height: 112)
            .animation(.spring(duration: 0.8, bounce: 0.2), value: progress)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(litres(intakeML))
                        .scaledNumericFont(size: 40)
                        .contentTransition(.numericText())
                    Text("/ \(litres(goalML)) L")
                        .font(FouleeFont.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Label(pace.text, systemImage: pace.systemImage)
                    .font(FouleeFont.callout.weight(.semibold))
                    .foregroundStyle(pace == .reached ? HydrationCard.water : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(HydrationCard.water)
                .opacity(0.1)
        }
        .fouleeGlass(cornerRadius: 24, strong: true)
        .accessibilityElement(children: .combine)
    }
}

/// A water drop: a point on top, a round belly below.
private struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.maxY - radius)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: center.y),
            control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.45)
        )
        path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.45)
        )
        path.closeSubpath()
        return path
    }
}

/// The day glass by glass (issues #355, #361), newest on top, each at its
/// hour, with its amount and the app that logged it — the outings timeline's
/// layout, in water.
struct HydrationTimeline: View {
    let samples: [WaterSample]

    var body: some View {
        if samples.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "drop")
                    .scaledSystemFont(size: 18)
                    .foregroundStyle(.secondary)
                Text("Pas encore de verre aujourd'hui")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(samples.enumerated()), id: \.element.id) { index, sample in
                    row(sample, isLast: index == samples.count - 1)
                }
            }
        }
    }

    private func row(_ sample: WaterSample, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(sample.date.clockText)
                .font(FouleeFont.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
            VStack(spacing: 0) {
                Circle()
                    .fill(HydrationCard.water)
                    .frame(width: 10, height: 10)
                    .padding(.top, 3)
                Rectangle()
                    .fill(isLast ? Color.clear : Color.gray.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            HStack {
                Text("\(sample.milliliters) mL")
                    .font(FouleeFont.callout.weight(.semibold).monospacedDigit())
                Spacer()
                Text(sample.sourceName)
                    .font(FouleeFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sample.date.clockText) : \(sample.milliliters) millilitres, \(sample.sourceName)")
    }
}

/// The last seven days (issue #355): a ring a day in the colour of water, the
/// days the goal held, and the daily mean.
struct HydrationWeekView: View {
    let history: HydrationHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(history.days) { day in
                    VStack(spacing: 6) {
                        ring(day)
                        Text(Self.letterFormatter.string(from: day.date).uppercased())
                            .font(FouleeFont.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(day.milliliters > 0 ? litres(day.milliliters) : "–")
                            .font(FouleeFont.caption.monospacedDigit())
                            .foregroundStyle(day.milliliters > 0 ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.dayFormatter.string(from: day.date))
                    .accessibilityValue("\(litres(day.milliliters)) litre")
                }
            }
            HStack(spacing: 6) {
                Label("Objectif tenu \(history.goalDaysMet)/\(history.days.count)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(HydrationCard.water)
                Text("· \(litres(history.averageML)) L par jour en moyenne")
                    .foregroundStyle(.secondary)
            }
            .font(FouleeFont.footnote.weight(.semibold))
        }
    }

    private func ring(_ day: HydrationHistory.Day) -> some View {
        let held = HydrationMath.reachedGoal(intakeML: day.milliliters, goalML: history.goalML)
        return ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.18), lineWidth: 4.5)
            Circle()
                .trim(from: 0, to: HydrationMath.progress(intakeML: day.milliliters, goalML: history.goalML))
                .stroke(HydrationCard.water.gradient, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if held {
                Circle()
                    .fill(HydrationCard.water.opacity(0.16))
                    .padding(6.75)
            }
        }
        .padding(2.25)
        .aspectRatio(1, contentMode: .fit)
    }

    private static let letterFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()
}
