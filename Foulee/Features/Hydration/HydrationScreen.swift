import Dependencies
import SwiftUI

/// The Hydratation screen (issue #355), opened from the home card: today as a
/// drop filling up with its rhythm, quick amounts to log, the day glass by
/// glass, and the week so far — the Bilan's grammar, in water.
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
                SheetHeader(eyebrow: "Hydratation", title: "Aujourd'hui")
                HydrationTodayHero(intakeML: store.intakeML, goalML: goalML, pace: pace)
                servings
                GlassSection("Verre par verre") {
                    HydrationTimeline(samples: detail.samples)
                }
                if let history = detail.history {
                    GlassSection("Cette semaine") {
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
        .overlay(alignment: .topTrailing) { SheetCloseButton(action: onClose) }
        .presentationBackground { SheetBackground() }
        .sensoryFeedback(.increase, trigger: store.intakeML)
        // Any change to the day's water — a glass here, one from the watch, an
        // undone one — redraws the timeline and today's ring.
        .task(id: store.intakeML) { await detail.load(goalML: goalML) }
    }

    /// Every quick amount on view, rather than behind the home's long press.
    private var servings: some View {
        // Four across, or two by two at the accessibility sizes (#371).
        AdaptiveGrid(columns: 4, accessibilityColumns: 2, spacing: 8) {
            ForEach(HydrationServing.presets(glassML: preferences.hydrationGlassML)) { serving in
                Button {
                    Task { await store.logGlass(ml: serving.milliliters) }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: serving.systemImage)
                            .scaledSystemFont(size: 20, weight: .semibold)
                            .foregroundStyle(FouleeColor.water)
                        Text("\(serving.milliliters) mL")
                            .font(FouleeFont.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                        // Wraps rather than shrinks (issue #658): a quarter
                        // of the width cuts « Grand verre » at large sizes.
                        Text(serving.label)
                            .font(FouleeFont.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    // The row's height, so the four tiles stay level when
                    // one label takes two lines.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 12)
                    .fouleeGlass(cornerRadius: 18)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("J'ai bu : \(serving.label), \(serving.milliliters) millilitres")
            }
        }
    }
}
