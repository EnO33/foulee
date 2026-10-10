import Dependencies
import SwiftUI

/// Gates the hydration card on the home behind the user's preference and wires
/// the "J'ai bu" tap to the store. Split out of `TodayScreen` to keep that
/// view's body small. Also surfaces the store's write problems: a denied
/// `dietaryWater` authorization (banner + link to Santé) or a failed save —
/// without them the card silently stays at 0 and "J'ai bu" looks broken.
struct HydrationHomeCard: View {
    let preferences: UserPreferences
    let store: HydrationStore

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Dependency(\.date) private var date
    @State private var isShowingDetail = false

    var body: some View {
        if preferences.hydrationEnabled {
            VStack(spacing: 8) {
                if store.writeDenied {
                    deniedBanner
                } else if store.lastError != nil {
                    failureBanner
                }
                // Re-read every minute: the rhythm moves with the clock even
                // when nothing is drunk (#353).
                TimelineView(.everyMinute) { _ in
                    HydrationCard(
                        intakeML: store.intakeML,
                        goalML: preferences.hydrationGoalML,
                        glassML: preferences.hydrationGlassML,
                        pace: pace,
                        onDrink: { milliliters in Task { await store.logGlass(ml: milliliters) } },
                        onOpen: { isShowingDetail = true }
                    )
                }
            }
            .sheet(isPresented: $isShowingDetail) {
                HydrationScreen(preferences: preferences, store: store) { isShowingDetail = false }
                    .preferredColorScheme(colorScheme)
            }
        }
    }

    /// Read from the app's clock rather than the timeline's, so a pinned clock
    /// (tests, captures) is the one the rhythm follows.
    private var pace: HydrationPace {
        HydrationPace.evaluate(
            intakeML: store.intakeML,
            goalML: preferences.hydrationGoalML,
            glassML: preferences.hydrationGlassML,
            window: HydrationPace.Window(start: preferences.hydrationWindowStart, end: preferences.hydrationWindowEnd),
            now: date.now
        )
    }

    /// Writing water was explicitly denied — "J'ai bu" can't work until the
    /// user re-enables it in the Health app.
    private var deniedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(FouleeColor.warning)
            Text("Autorise l'eau dans Santé pour compter tes verres")
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            } label: {
                Text("Ouvrir Santé")
                    .font(FouleeFont.caption.weight(.semibold))
                    .foregroundStyle(FouleeColor.accentMid)
            }
            .buttonStyle(.pressable)
        }
        .padding(12)
        .fouleeGlass(cornerRadius: 16)
    }

    /// The last "J'ai bu" write failed for another reason — say so instead of
    /// letting the glass vanish. Cleared on the next successful log.
    private var failureBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(FouleeColor.warning)
            Text("Verre non enregistré — réessaie")
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .fouleeGlass(cornerRadius: 16)
    }
}
