import SwiftUI

/// The week or the month in review (issues #344, #346).
///
/// Read top to bottom like a story: what the period meant (the verdict and
/// the goal ring), how it went day by day, how it compares with the one
/// before, and its high points. Everything fills in as the screen opens.
struct RecapScreen: View {
    let goalMinutes: Int
    let activeDays: Set<Weekday>
    var onClose: () -> Void

    @State private var kind: RecapPeriod.Kind
    @State private var store = RecapStore()

    init(kind: RecapPeriod.Kind, goalMinutes: Int, activeDays: Set<Weekday>, onClose: @escaping () -> Void) {
        _kind = State(initialValue: kind)
        self.goalMinutes = goalMinutes
        self.activeDays = activeDays
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("Période", selection: $kind.animation(.snappy)) {
                    ForEach(RecapPeriod.Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if let recap = store.recaps[kind] {
                    // Keyed on the period, so switching replays the reveal.
                    RecapContent(recap: recap)
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
        .overlay(alignment: .topTrailing) {
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
        .presentationBackground { SheetBackground() }
        .task { await store.load(goalMinutes: goalMinutes, activeDays: activeDays) }
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
}

/// One recap, laid out.
private struct RecapContent: View {
    let recap: Recap

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RecapHero(recap: recap, isRevealed: isRevealed)
            if !recap.isEmpty {
                section(recap.period.kind == .week ? "Jour par jour" : "Le mois en un coup d'œil") {
                    RecapDaysView(recap: recap, isRevealed: isRevealed)
                    legend
                }
                section(recap.period.kind == .week ? "Par rapport à la semaine d'avant" : "Par rapport au mois d'avant") {
                    RecapComparison(recap: recap, isRevealed: isRevealed)
                }
                RecapHighlights(recap: recap)
            }
        }
        .onAppear {
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
