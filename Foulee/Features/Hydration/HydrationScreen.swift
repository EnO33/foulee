import Dependencies
import SwiftUI

/// The Hydratation screen (issue #355), opened from the home card: today as a
/// drop filling up with its rhythm, quick amounts to log, the day glass by
/// glass, and the last seven days — the Bilan's grammar, in water.
struct HydrationScreen: View {
    let preferences: UserPreferences
    let store: HydrationStore
    var onClose: () -> Void

    @State private var detail = HydrationDetailStore()
    @Dependency(\.date) private var date

    private var goalML: Int { preferences.hydrationGoalML }

    private var pace: HydrationPace {
        HydrationPace.evaluate(
            intakeML: store.intakeML,
            goalML: goalML,
            glassML: preferences.hydrationGlassML,
            window: HydrationPace.Window(start: preferences.hydrationWindowStart, end: preferences.hydrationWindowEnd),
            now: date.now
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                HydrationTodayHero(intakeML: store.intakeML, goalML: goalML, pace: pace)
                servings
                section("Verre par verre") {
                    HydrationTimeline(samples: detail.samples)
                }
                if let history = detail.history {
                    section("7 derniers jours") {
                        HydrationWeekView(history: history)
                    }
                } else if detail.lastError != nil {
                    Label("Impossible de lire ton historique d'eau pour le moment.", systemImage: "exclamationmark.triangle")
                        .font(FouleeFont.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .presentationBackground { SheetBackground() }
        .sensoryFeedback(.increase, trigger: store.intakeML)
        // Any change to the day's water — a glass here, one from the watch, an
        // undone one — redraws the timeline and today's ring.
        .task(id: store.intakeML) { await detail.load(goalML: goalML) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("HYDRATATION")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            Text("Aujourd'hui")
                .font(FouleeFont.largeTitle)
        }
    }

    /// Every quick amount on view, rather than behind the home's long press.
    private var servings: some View {
        HStack(spacing: 8) {
            ForEach(HydrationServing.presets(glassML: preferences.hydrationGlassML)) { serving in
                Button {
                    Task { await store.logGlass(ml: serving.milliliters) }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: serving.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(HydrationCard.water)
                        Text("\(serving.milliliters) mL")
                            .font(FouleeFont.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text(serving.label)
                            .font(FouleeFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .fouleeGlass(cornerRadius: 18)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("J'ai bu : \(serving.label), \(serving.milliliters) millilitres")
            }
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
