import FouleeKit
import SwiftUI

/// The two shapes a shared Bilan comes in (issue #410).
enum RecapShareFormat: String, CaseIterable, Identifiable, Sendable {
    /// 4:5 — Messages, WhatsApp, a feed post.
    case square
    /// 9:16 — a story, full screen.
    case story

    var id: String { rawValue }

    var label: String {
        switch self {
        case .square: "Carré"
        case .story: "Story"
        }
    }

    /// In points; rendered at ×3, so 1080 × 1350 and 1080 × 1920 pixels.
    var size: CGSize {
        switch self {
        case .square: CGSize(width: 360, height: 450)
        case .story: CGSize(width: 360, height: 640)
        }
    }

    fileprivate var isStory: Bool { self == .story }
}

/// The picture of a Bilan sent to friends (issue #410): the period, its
/// minutes, the days the goal held, three figures and the best day, signed
/// Foulée.
///
/// Drawn for `ImageRenderer`, not for the screen: fixed sizes rather than
/// Dynamic Type, solid fills rather than materials (a blur has nothing behind
/// it to blur off screen), and no animation — the same Bilan renders the same
/// pixels whoever shares it.
struct RecapShareImage: View {
    let recap: Recap
    let format: RecapShareFormat

    private var card: RecapShareCard { RecapShareCard(recap: recap) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 14)
            hero
            Spacer(minLength: 14)
            RecapShareDays(recap: recap, format: format)
            Spacer(minLength: 14)
            stats
            if let bestDay = card.bestDay {
                Label(bestDay, systemImage: "trophy.fill")
                    .font(.system(size: format.isStory ? 15 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(FouleeColor.warning)
                    .padding(.top, 10)
            }
            Spacer(minLength: 12)
            footer
        }
        .padding(format.isStory ? 28 : 24)
        .frame(width: format.size.width, height: format.size.height, alignment: .topLeading)
        .background(SheetBackground())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.heading)
                .font(.system(size: format.isStory ? 34 : 28, weight: .bold, design: .rounded))
            Text(card.periodTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var hero: some View {
        HStack(spacing: 18) {
            ProgressRing(
                progress: recap.goalRate,
                lineWidth: format.isStory ? 12 : 10,
                gradient: FouleeColor.activityGradient,
                trackColor: Color.gray.opacity(0.18)
            ) {
                Text(recap.goalDaysPlanned > 0 ? "\(recap.goalDaysMet)/\(recap.goalDaysPlanned)" : "–")
                    .font(.system(size: format.isStory ? 22 : 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: format.isStory ? 100 : 84, height: format.isStory ? 100 : 84)
            VStack(alignment: .leading, spacing: 4) {
                // No change beside the minutes (#454): on an image, nothing
                // says what it would be compared with.
                Text(card.minutes)
                    .font(.system(size: format.isStory ? 44 : 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("d'activité")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                if let goalLine = card.goalLine {
                    Text(goalLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FouleeColor.success)
                }
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            ForEach(card.stats) { stat in
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: stat.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FouleeColor.accentMid)
                    Text(stat.value)
                        .font(.system(size: format.isStory ? 18 : 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(stat.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: FouleeIcon.mixedCardio)
                .foregroundStyle(FouleeColor.accentGradient)
            Text("Foulée")
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The period day by day, as the Bilan draws it — the week's seven rings or
/// the month's calendar — without the buttons, the selection or the reveal.
/// A `Grid` rather than the Bilan's lazy one: an off-screen render lays out
/// everything at once.
private struct RecapShareDays: View {
    let recap: Recap
    let format: RecapShareFormat

    private static let letters = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        switch recap.period.kind {
        case .week: week
        case .month: month
        }
    }

    private var week: some View {
        let ring: CGFloat = format.isStory ? 38 : 32
        let toCome = recap.period.daysToCome()
        return HStack(spacing: 0) {
            ForEach(Array(recap.days.enumerated()), id: \.element.id) { index, day in
                column(letter: index) {
                    RecapDayRing(day: day, goalMinutes: recap.goalMinutes, lineWidth: ring * 0.14)
                        .frame(width: ring, height: ring)
                }
            }
            ForEach(Array(toCome.enumerated()), id: \.element) { offset, _ in
                column(letter: recap.days.count + offset) {
                    UpcomingDayRing(lineWidth: ring * 0.14)
                        .frame(width: ring, height: ring)
                }
            }
        }
    }

    private func column<Ring: View>(letter index: Int, @ViewBuilder ring: () -> Ring) -> some View {
        VStack(spacing: 5) {
            ring()
            Text(Self.letters[index % 7])
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var month: some View {
        let ring: CGFloat = format.isStory ? 30 : 18
        return Grid(horizontalSpacing: 6, verticalSpacing: format.isStory ? 6 : 3) {
            GridRow {
                ForEach(Array(Self.letters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Array(recap.calendarWeeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            RecapDayRing(day: day, goalMinutes: recap.goalMinutes, lineWidth: ring * 0.14)
                                .frame(width: ring, height: ring)
                        } else {
                            Color.clear.frame(width: ring, height: ring)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Turns a Bilan into the picture that is shared (issue #410).
enum RecapShareRenderer {
    /// Light, default text size, ×3, opaque: the image looks the same from
    /// every device and every setting, and a PNG with no alpha weighs less.
    static func image(of recap: Recap, as format: RecapShareFormat) -> UIImage? {
        let renderer = ImageRenderer(
            content: RecapShareImage(recap: recap, format: format)
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large)
        )
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
