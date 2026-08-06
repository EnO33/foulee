import SwiftUI

/// Second onboarding screen — marche, course, ou les deux.
///
/// Placed right after the welcome and before the goal step: the flow is linear
/// with no back navigation, and this is its first consequential choice whose
/// default isn't self-evident, so it has to be asked before the screens that
/// are written around it (issue #221).
///
/// Nothing here touches the streak: `activityMode` is a presentation
/// preference, and the streak stays `max(appleExerciseTime, workout minutes)`
/// over every activity type whatever is picked.
struct OnboardingActivityView: View {
    var preferences: UserPreferences
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Scrolled for the same reason as the permissions screen: the
            // heading plus three two-line rows outgrow a fixed stack at the
            // larger Dynamic Type sizes. The CTA stays pinned to the bottom.
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    OnboardingStepIndicator(step: .activity)
                        .frame(maxWidth: .infinity)
                    heading
                    choices
                }
                .padding(.horizontal, 24)
                .padding(.top, 70)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            PrimaryButton(title: "Continuer", systemIcon: nil, action: confirm)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tu marches ou\ntu cours ?")
                .scaledSystemFont(size: 30, weight: .bold)
                .lineSpacing(2)
            Text("On adaptera Foulée à ta pratique.")
                .font(FouleeFont.body)
                .foregroundStyle(.secondary)
        }
    }

    private var choices: some View {
        VStack(spacing: 12) {
            ForEach(ActivityMode.allCases) { mode in
                ActivityChoiceRow(
                    mode: mode,
                    isSelected: preferences.activityMode == mode,
                    // Written the moment it's tapped rather than held in local
                    // state until the end: an onboarding abandoned midway
                    // still leaves the choice behind, and it is on disk well
                    // before `hasCompletedOnboarding`.
                    select: { preferences.activityMode = mode }
                )
            }
        }
    }

    /// Re-assigning the value already in memory looks redundant, but `didSet`
    /// is what writes `UserDefaults`: this is how someone who accepts the
    /// default (marche) still leaves the key on disk, instead of a blank that
    /// reads exactly like the installs which predate the question (#219).
    private func confirm() {
        let chosen = preferences.activityMode
        preferences.activityMode = chosen
        onContinue()
    }
}

/// One tappable glass row per mode. The copy lives here rather than on
/// `ActivityMode`: onboarding wants a title *and* a line of explanation, and
/// the enum deliberately carries no display label until the settings picker
/// needs one (#220).
///
/// Internal rather than private only so the tests can name it: rows are built
/// inside a `ForEach`, which stores a closure instead of its rows, and calling
/// that closure is the only way to reach a row's tap action without a UI test
/// (`OnboardingFlowTests.tappingARowWritesImmediately`).
struct ActivityChoiceRow: View {
    var mode: ActivityMode
    var isSelected: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 14) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FouleeFont.headline)
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: FouleeIcon.check)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FouleeColor.accentMid)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(14)
            .fouleeGlass(cornerRadius: 18)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(FouleeColor.accentMid.opacity(isSelected ? 0.8 : 0), lineWidth: 2)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var icon: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                isSelected
                    ? AnyShapeStyle(FouleeColor.accentGradient)
                    : AnyShapeStyle(FouleeColor.accentMid.opacity(0.15))
            )
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: systemIcon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(FouleeColor.accentMid))
            }
    }

    private var systemIcon: String {
        switch mode {
        case .walking: FouleeIcon.walk
        case .running: FouleeIcon.run
        case .both: FouleeIcon.mixedCardio
        }
    }

    private var title: String {
        switch mode {
        case .walking: "Marche"
        case .running: "Course"
        case .both: "Les deux"
        }
    }

    private var subtitle: String {
        switch mode {
        case .walking: "Une sortie tranquille, à ton rythme"
        case .running: "Des sorties plus intenses"
        case .both: "Ça dépend des jours"
        }
    }
}

// Spelled out in each block rather than shared through a helper: the screen
// holds a plain reference (no `@State` wrapper needed), and any named
// declaration only previews reach reads as dead code to the Periphery scan.
#Preview("Light") {
    ZStack {
        Wallpaper()
        OnboardingActivityView(
            preferences: UserPreferences(
                defaults: UserDefaults(suiteName: "preview-onboarding-activity") ?? .standard
            ),
            onContinue: {}
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    ZStack {
        Wallpaper()
        OnboardingActivityView(
            preferences: UserPreferences(
                defaults: UserDefaults(suiteName: "preview-onboarding-activity") ?? .standard
            ),
            onContinue: {}
        )
    }
    .preferredColorScheme(.dark)
}
