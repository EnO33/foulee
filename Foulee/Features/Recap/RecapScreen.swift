import SwiftUI

/// The Bilan: the last seven days or the last month (issues #344, #346, #350).
///
/// Read top to bottom like a story: what the period meant (the verdict and
/// the goal ring), how it went day by day — a tap on a day lays out its
/// outings — how it compares with the one before, and its high points.
/// Everything fills in as the screen opens.
struct RecapScreen: View {
    let goalMinutes: Int
    let activeDays: Set<Weekday>
    /// The hydration goal, `nil` while hydration is off (issue #356).
    let waterGoalML: Int?
    var onClose: () -> Void

    @State private var kind: RecapPeriod.Kind
    @State private var store = RecapStore()

    init(
        kind: RecapPeriod.Kind,
        goalMinutes: Int,
        activeDays: Set<Weekday>,
        waterGoalML: Int?,
        onClose: @escaping () -> Void
    ) {
        _kind = State(initialValue: kind)
        self.goalMinutes = goalMinutes
        self.activeDays = activeDays
        self.waterGoalML = waterGoalML
        self.onClose = onClose
    }

    var body: some View {
        // A stack so an outing opens its detail by a push, not a sheet on the
        // sheet (#218); its bar only shows once something is pushed.
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Picker("Période", selection: $kind.animation(.snappy)) {
                        ForEach(RecapPeriod.Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let recap = store.recaps[kind] {
                        // Keyed on the period, so switching replays the reveal
                        // and starts again from its own day.
                        RecapContent(recap: recap, outings: store.outings[kind] ?? [], water: store.water[kind])
                            .id(kind)
                            .transition(.opacity)
                    } else if store.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if store.lastError != nil {
                        Label("Impossible de lire tes données Santé pour le moment.", systemImage: "exclamationmark.triangle")
                            .font(FouleeFont.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
            .overlay(alignment: .topTrailing) { closeButton }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WorkoutSummary.self) { WorkoutDetailSheet(summary: $0) }
        }
        .presentationBackground { SheetBackground() }
        .task { await store.load(goalMinutes: goalMinutes, activeDays: activeDays, waterGoalML: waterGoalML) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RÉCAP")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            Text("Ton bilan")
                .font(FouleeFont.largeTitle)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.pressable)
        .padding(20)
        .accessibilityLabel("Fermer")
    }
}

/// One recap, laid out.
private struct RecapContent: View {
    let recap: Recap
    let outings: [OutingDay]
    let water: RecapWater?

    @State private var isRevealed = false
    /// The day whose outings are laid out: the latest with one, else the last.
    @State private var selectedDay: Date?

    private var isWeek: Bool { recap.period.kind == .week }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RecapHero(recap: recap, isRevealed: isRevealed)
            section(isWeek ? "Jour par jour" : "Le mois en un coup d'œil") {
                RecapDaysView(recap: recap, selection: $selectedDay, isRevealed: isRevealed)
                legend
            }
            if let day = outings.first(where: { $0.day == selectedDay }),
               let ring = recap.days.first(where: { $0.date == day.day }) {
                RecapDayTimeline(outings: day, ring: ring, goalMinutes: recap.goalMinutes)
                    .id(day.day)
                    .transition(.opacity)
            }
            if !recap.isEmpty {
                section(isWeek ? "Par rapport aux 7 jours d'avant" : "Par rapport au mois d'avant") {
                    RecapComparison(recap: recap, isRevealed: isRevealed)
                }
                RecapHighlights(recap: recap)
            }
            if let water {
                section("Hydratation") {
                    RecapHydration(water: water, isRevealed: isRevealed)
                }
            }
            healthAppLink
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            selectedDay = (outings.last { !$0.workouts.isEmpty } ?? outings.last)?.day
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) { isRevealed = true }
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(FouleeFont.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .fouleeGlass(cornerRadius: 22)
    }
}
