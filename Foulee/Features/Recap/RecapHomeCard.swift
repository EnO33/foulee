import SwiftUI

/// The way into the Bilan from the home (issues #344, #346, #350, #363): the
/// week so far at a glance — a ring per day, Monday first, the minutes, the
/// goals held — so the card already tells something before it is tapped. A
/// tap opens the week and its outings; the link under it, the month.
struct RecapHomeCard: View {
    let goalMinutes: Int
    let activeDays: Set<Weekday>
    /// Today's minutes: today is part of the week, so the card reads again
    /// whenever they move.
    let todayMinutes: Int
    var onOpen: (RecapPeriod.Kind) -> Void

    @State private var store = RecapStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { onOpen(.week) } label: { weekPreview }
                .buttonStyle(.pressable)
            Button { onOpen(.month) } label: {
                HStack(spacing: 4) {
                    Text("Voir le récap du mois")
                    Image(systemName: "chevron.right")
                }
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(FouleeColor.accentMid)
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .fouleeGlass(cornerRadius: 22)
        .task(id: "\(goalMinutes)-\(activeDays.bitmask)-\(todayMinutes)") {
            await store.load(goalMinutes: goalMinutes, activeDays: activeDays)
        }
    }

    private var weekPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ta semaine", systemImage: "chart.bar.doc.horizontal")
                    .font(FouleeFont.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let recap = store.recaps[.week] {
                HStack(spacing: 6) {
                    ForEach(recap.days) { day in
                        RecapDayRing(day: day, goalMinutes: recap.goalMinutes, lineWidth: 3.5)
                            .frame(maxWidth: 34)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(recap.period.daysToCome(), id: \.self) { _ in
                        UpcomingDayRing(lineWidth: 3.5)
                            .frame(maxWidth: 34)
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(recap.totals.minutes) min")
                        .font(FouleeFont.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                    if recap.goalDaysPlanned > 0 {
                        Text("· objectif tenu \(recap.goalDaysMet)/\(recap.goalDaysPlanned)")
                            .font(FouleeFont.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    RecapChangeChip(old: Double(recap.previous.minutes), new: Double(recap.totals.minutes))
                }
            } else {
                Text("Ta semaine, du lundi à aujourd'hui, jour par jour.")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre le bilan de la semaine et ses sorties")
    }
}

/// Presents the recap the router asks for (issue #344): from the home card,
/// or from a notification — whether its tap launched the app or found the home
/// already on screen. One way in for both, and a modifier so the home's own
/// body stays short.
struct RecapPresentation: ViewModifier {
    let goalMinutes: Int
    let activeDays: Set<Weekday>
    /// The hydration goal, `nil` while hydration is off (issue #356).
    let waterGoalML: Int?
    let colorScheme: ColorScheme?
    var router: RecapRouter = .shared

    @State private var selection: RecapPeriod.Kind?

    func body(content: Content) -> some View {
        content
            .sheet(item: $selection) { kind in
                RecapScreen(kind: kind, goalMinutes: goalMinutes, activeDays: activeDays, waterGoalML: waterGoalML) {
                    selection = nil
                }
                .preferredColorScheme(colorScheme)
            }
            .onAppear(perform: openPending)
            .onChange(of: router.pending) { _, _ in openPending() }
    }

    private func openPending() {
        guard let kind = router.take() else { return }
        selection = kind
    }
}
