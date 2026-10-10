import SwiftUI

/// The way into the recaps from the home (issues #344, #346): last week at a
/// glance — a ring per day, the minutes, the goals held — so the card already
/// tells something before it is tapped. A tap opens the week; the link under
/// it, the month.
struct RecapHomeCard: View {
    let goalMinutes: Int
    let activeDays: Set<Weekday>
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
        .task(id: "\(goalMinutes)-\(activeDays.bitmask)") {
            await store.load(goalMinutes: goalMinutes, activeDays: activeDays)
        }
    }

    private var weekPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ta semaine passée", systemImage: "chart.bar.doc.horizontal")
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
                Text("Ton bilan de la semaine dernière, jour par jour.")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre le récap de la semaine")
    }
}

/// Presents the recap the router asks for (issue #344): from the home card,
/// or from a notification — whether its tap launched the app or found the home
/// already on screen. One way in for both, and a modifier so the home's own
/// body stays short.
struct RecapPresentation: ViewModifier {
    let goalMinutes: Int
    let activeDays: Set<Weekday>
    let colorScheme: ColorScheme?
    var router: RecapRouter = .shared

    @State private var selection: RecapPeriod.Kind?

    func body(content: Content) -> some View {
        content
            .sheet(item: $selection) { kind in
                RecapScreen(kind: kind, goalMinutes: goalMinutes, activeDays: activeDays) {
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
