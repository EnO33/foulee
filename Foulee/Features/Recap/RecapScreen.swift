import Dependencies
import FouleeKit
import SwiftUI

/// The Bilan: the streak, the week or the month, and the year (issues #344,
/// #346, #350, #363, #444, #445).
///
/// Read top to bottom like a story: the streak and its record, then what the
/// period meant (the verdict and the goal ring), how it went day by day — a
/// tap on a day lays out its outings — how it compares with the one before,
/// and its high points; the year's totals and most regular weekdays close it.
/// Everything fills in as the screen opens.
///
/// It opens on the period in progress and pages back a week or a month at a
/// time, by a horizontal swipe or the chevrons either side of the period's
/// name, as far as `RecapPeriod.historyMonths` (issue #444).
struct RecapScreen: View {
    let goalMinutes: Int
    let activeDays: Set<Weekday>
    /// The hydration goal, `nil` while hydration is off (issue #356).
    let waterGoalML: Int?
    var onClose: () -> Void

    @State private var kind: RecapPeriod.Kind
    /// The page on screen for each kind: switching between Semaine and Mois
    /// comes back to where each was left.
    @State private var shown: [RecapPeriod.Kind: RecapPeriod]
    /// The side the next page slides in from.
    @State private var arrival: Edge = .trailing
    @State private var store = RecapStore()
    @State private var isSharing = false
    /// The outings pushed: the one a session notification opened (#530).
    @State private var path: [WorkoutSummary] = []
    /// That outing, until the period's outings are read.
    @State private var pendingOuting: DateInterval?
    /// A sheet presented from a sheet doesn't inherit the theme.
    @Environment(\.colorScheme) private var colorScheme
    /// A page slides in from the side it was swiped to, or fades in place
    /// with « Réduire les animations » (issue #598).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Dependency(\.date) private var date

    /// The period on screen.
    private var period: RecapPeriod {
        shown[kind] ?? RecapPeriod.current(kind, at: date.now)
    }

    private var content: RecapPeriodContent? {
        store.content(for: period)
    }

    /// The recap on screen, when there is something in it to share.
    private var shareable: Recap? {
        content.flatMap { $0.recap.isEmpty ? nil : $0.recap }
    }

    /// `period` opens a given page — the month just ended, from the
    /// notification of the 1st (issue #444); `nil` opens the one in progress.
    /// `outing` is pushed once read — the one a session notification
    /// announced (issue #530).
    init(
        kind: RecapPeriod.Kind,
        period: RecapPeriod? = nil,
        outing: DateInterval? = nil,
        goalMinutes: Int,
        activeDays: Set<Weekday>,
        waterGoalML: Int?,
        onClose: @escaping () -> Void
    ) {
        @Dependency(\.date) var date
        let now = date.now
        var shown = Dictionary(uniqueKeysWithValues: RecapPeriod.Kind.allCases.map { ($0, RecapPeriod.current($0, at: now)) })
        if let period { shown[period.kind] = period }
        _kind = State(initialValue: period?.kind ?? kind)
        _shown = State(initialValue: shown)
        _pendingOuting = State(initialValue: outing)
        self.goalMinutes = goalMinutes
        self.activeDays = activeDays
        self.waterGoalML = waterGoalML
        self.onClose = onClose
    }

    var body: some View {
        // A stack so an outing opens its detail by a push, not a sheet on the
        // sheet (#218); its bar only shows once something is pushed.
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SheetHeader(eyebrow: "Récap", title: "Ton bilan")
                    if let streak = store.streak {
                        RecapStreakHeader(streak: streak)
                            .transition(.opacity)
                    }
                    Picker("Période", selection: $kind.animation(.snappy)) {
                        ForEach(RecapPeriod.Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    RecapPeriodNavigator(
                        title: period.title,
                        earlier: period.hasEarlier(at: date.now) ? { page(by: -1) } : nil,
                        later: period.later(at: date.now) != nil ? { page(by: 1) } : nil
                    )

                    if let content {
                        // Keyed on the period, so paging replays the reveal and
                        // starts again from its own day.
                        RecapContent(
                            recap: content.recap,
                            outings: content.outings,
                            water: content.water,
                            isInProgress: period.isInProgress(at: date.now)
                        )
                        .id(period)
                        .transition(reduceMotion ? .opacity : .push(from: arrival))
                    } else if store.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if store.lastError != nil {
                        Label("Impossible de lire tes données Santé pour le moment.", systemImage: "exclamationmark.triangle")
                            .font(FouleeFont.callout)
                            .foregroundStyle(.secondary)
                    }
                    // The year doesn't page with the period: it stays put.
                    if let streak = store.streak {
                        RecapYear(streak: streak)
                    }
                    if content != nil {
                        healthAppLink
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 40)
                // Alongside the vertical scroll, never instead of it: only a
                // drag clearly sideways turns the page.
                .gesture(HorizontalSwipeGesture { page(by: $0 == .left ? 1 : -1) })
            }
            .overlay(alignment: .topTrailing) { cornerButtons }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WorkoutSummary.self) { WorkoutDetailSheet(summary: $0, merging: mergeOptions(for: $0)) }
        }
        .onChange(of: content?.outings, initial: true) { _, days in openPendingOuting(in: days) }
        .presentationBackground { SheetBackground() }
        .sensoryFeedback(.selection, trigger: period)
        .task {
            await store.load(goalMinutes: goalMinutes, activeDays: activeDays, waterGoalML: waterGoalML, withHistory: true)
        }
        .sheet(isPresented: $isSharing) {
            if let shareable {
                RecapShareSheet(recap: shareable) { isSharing = false }
                    .preferredColorScheme(colorScheme)
            }
        }
    }

    /// Push the outing a notification announced, once its days are read. Not
    /// found — Santé dropped it meanwhile — the Bilan itself stays open.
    private func openPendingOuting(in days: [OutingDay]?) {
        guard let outing = pendingOuting, let days else { return }
        pendingOuting = nil
        if let summary = OutingDay.outing(overlapping: outing, in: days) {
            path = [summary]
        }
    }

    /// What `outing` can be merged with (issue #552). Merging or separating
    /// closes the detail on the Bilan, read again with the outing changed.
    private func mergeOptions(for outing: WorkoutSummary) -> OutingMergeOptions {
        let neighbours = store.mergeNeighbours(of: outing)
        return OutingMergeOptions(
            previous: neighbours.previous,
            next: neighbours.next,
            isMerged: store.isMerged(outing),
            merge: { other in
                path = []
                Task { await store.merge(outing, with: other) }
            },
            separate: {
                path = []
                Task { await store.separate(outing) }
            }
        )
    }

    /// One page back (`-1`) or forward (`1`), within the history. A swipe to
    /// the left goes forward in time, to the right back: the calendar's own
    /// direction.
    private func page(by step: Int) {
        let now = date.now
        let target = step < 0
            ? (period.hasEarlier(at: now) ? period.earlier() : nil)
            : period.later(at: now)
        guard let target else { return }
        arrival = step < 0 ? .leading : .trailing
        withAnimation(.snappy) { shown[kind] = target }
    }

    private var healthAppLink: some View {
        Button {
            if let url = URL(string: "x-apple-health://") {
                UIApplication.shared.open(url)
            }
        } label: {
            Label("Voir dans Santé", systemImage: "heart.fill")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(FouleeColor.accentMid)
        }
        .buttonStyle(.pressable)
    }

    /// Share (issue #410) beside the close button — only once there is a
    /// period with something in it to show.
    private var cornerButtons: some View {
        HStack(spacing: 12) {
            if shareable != nil {
                SheetRoundButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Partager le bilan") {
                    isSharing = true
                }
                .transition(.opacity)
            }
            SheetRoundButton(systemImage: "xmark", accessibilityLabel: "Fermer", action: onClose)
        }
        .padding(20)
    }
}

/// The period's name between a chevron back and a chevron forward (issue
/// #444). The swipe does the same; the chevrons are what VoiceOver reads, and
/// what says there is somewhere to go. A `nil` action greys its chevron out.
private struct RecapPeriodNavigator: View {
    let title: String
    let earlier: (() -> Void)?
    let later: (() -> Void)?

    var body: some View {
        HStack {
            chevron("chevron.left", label: "Période précédente", action: earlier)
            Spacer(minLength: 0)
            Text(title)
                .font(FouleeFont.headline)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            chevron("chevron.right", label: "Période suivante", action: later)
        }
    }

    private func chevron(_ icon: String, label: LocalizedStringResource, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.pressable)
        .disabled(action == nil)
        .opacity(action == nil ? 0.3 : 1)
        .accessibilityLabel(Text(label))
    }
}

/// One recap, laid out.
private struct RecapContent: View {
    let recap: Recap
    let outings: [OutingDay]
    let water: RecapWater?
    /// Whether today falls in the period: its empty state says « pas encore ».
    let isInProgress: Bool

    @State private var isRevealed = false
    /// The day whose outings are laid out: today in the period in progress,
    /// outing or not, else the period's last day (issue #443).
    @State private var selectedDay: Date?
    /// The rings fill at once, without the reveal (issue #598).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Dependency(\.date) private var date

    private var isWeek: Bool { recap.period.kind == .week }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RecapHero(recap: recap, isRevealed: isRevealed)
            if recap.isEmpty {
                // Rings with nothing in them say nothing (#369): say what the
                // period is waiting for instead.
                emptyState
            } else {
                GlassSection(daysTitle) {
                    RecapDaysView(recap: recap, selection: $selectedDay, isRevealed: isRevealed)
                    legend
                }
                if let day = outings.first(where: { $0.day == selectedDay }),
                   let ring = recap.days.first(where: { $0.date == day.day }) {
                    RecapDayTimeline(outings: day, ring: ring, goalMinutes: recap.goalMinutes)
                        .id(day.day)
                        .transition(.opacity)
                }
                GlassSection(comparisonTitle) {
                    RecapComparison(recap: recap, isInProgress: isInProgress, isRevealed: isRevealed)
                }
                RecapHighlights(recap: recap)
            }
            if let water {
                GlassSection("Hydratation") {
                    RecapHydration(water: water, isRevealed: isRevealed)
                }
            }
        }
        .onAppear {
            selectedDay = OutingDay.initialSelection(among: outings.map(\.day), today: date.now)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8).delay(0.15)) { isRevealed = true }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label { Text(emptyTitle) } icon: { Image(systemName: "figure.walk") }
        } description: {
            Text(isInProgress
                ? "Une sortie, même courte, et ton bilan prend vie, jour après jour."
                : isWeek
                    ? "Rien n'a été enregistré dans Santé cette semaine-là."
                    : "Rien n'a été enregistré dans Santé ce mois-là.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .fouleeGlass(cornerRadius: 22)
    }

    private var daysTitle: LocalizedStringResource {
        isWeek ? LocalizedStringResource("Jour par jour") : LocalizedStringResource("Le mois en un coup d'œil")
    }

    /// Says what the comparison is with (#454): the same days of the period
    /// before while this one is open, the whole of it once it is over.
    private var comparisonTitle: LocalizedStringResource {
        switch (isWeek, isInProgress) {
        case (true, true): "Par rapport aux mêmes jours de la semaine d'avant"
        case (true, false): "Par rapport à la semaine d'avant"
        case (false, true): "Par rapport aux mêmes jours du mois d'avant"
        case (false, false): "Par rapport au mois d'avant"
        }
    }

    /// « Pas encore » while the period is open (issue #444), « pas » once it
    /// is over and nothing can change.
    private var emptyTitle: LocalizedStringResource {
        switch (isWeek, isInProgress) {
        case (true, true): "Pas encore d'activité cette semaine"
        case (true, false): "Pas d'activité cette semaine-là"
        case (false, true): "Pas encore d'activité ce mois-ci"
        case (false, false): "Pas d'activité ce mois-là"
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label("Objectif de \(recap.goalMinutes) min tenu", systemImage: "circle.inset.filled")
                .foregroundStyle(FouleeColor.success)
            Label("Jour de repos", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        }
        .font(FouleeFont.caption)
        .labelStyle(.titleAndIcon)
    }
}
