import SwiftUI

/// « Les deux » : which activity is this session? Asked on the phone's session
/// start screen, before a single sample is recorded (issue #224).
///
/// It is a *screen*, not a sheet over the home: `ActiveWalkScreen` shows it in
/// place of its own loading state, so the flow reads as one push — tap
/// « Démarrer ta sortie », answer, the timer starts — instead of a modal on a
/// modal. Users in « marche » or « course » never see it: their mode already
/// answers the question and `ActiveWalkScreen` starts on appear, one gesture,
/// exactly as before.
///
/// The question is asked every time on purpose. A remembered default would be
/// one tap cheaper and would eventually write a run into Santé labelled as a
/// walk, which `HKWorkout` makes permanent.
struct ActivityChoiceScreen: View {
    var onChoose: (SessionActivity) -> Void
    var onCancel: () -> Void

    var body: some View {
        // Scrolled rather than a fixed stack, for the same reason the
        // onboarding activity step is: heading + two rows + the cancel button
        // outgrow the screen at the largest Dynamic Type sizes.
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    heading
                    choices
                }
                .padding(.horizontal, 24)
                .padding(.top, 80)
            }
            .scrollBounceBehavior(.basedOnSize)
            ActivityChoiceCancelButton(cancel: onCancel)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    private var heading: some View {
        VStack(spacing: 8) {
            Text("Tu marches ou tu cours ?")
                .scaledSystemFont(size: 28, weight: .bold)
                .multilineTextAlignment(.center)
            // Says why it asks. Santé keeps the type for good, and this is the
            // only moment it can still be set.
            Text("Ta sortie sera enregistrée sous ce type dans Santé.")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var choices: some View {
        VStack(spacing: 12) {
            ForEach(SessionActivity.allCases, id: \.self) { activity in
                ActivityChoiceButton(activity: activity, select: { onChoose(activity) })
            }
        }
    }
}

/// One large glass button per activity.
///
/// Internal rather than private so the tests can name it: the buttons are
/// built inside a `ForEach`, which stores a closure instead of its rows, and
/// calling that closure is the only way to reach the tap action short of a UI
/// test — the same seam `ActivityChoiceRow` opens for onboarding.
struct ActivityChoiceButton: View {
    var activity: SessionActivity
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 16) {
                Image(systemName: activity.icon)
                    .scaledSystemFont(size: 26, weight: .semibold)
                    .foregroundStyle(FouleeColor.accentMid)
                    .frame(width: 44)
                Text(activity.label)
                    .font(FouleeFont.title3)
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: FouleeIcon.play)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FouleeColor.accentMid)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 18)
            .fouleeGlass(cornerRadius: 20)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Démarrer \(activity.label.lowercased())")
    }
}

/// The way back out. A named view for the same reason the answers are: a
/// `Button` buried in a `body` is unreachable from a test, and this one is the
/// only escape from a screen that is showing instead of the session — wired to
/// nothing, it traps the user; wired to the wrong thing, it starts a session
/// they were trying not to start.
struct ActivityChoiceCancelButton: View {
    var cancel: () -> Void

    var body: some View {
        Button(action: cancel) {
            Text("Annuler")
                .font(FouleeFont.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.pressable)
    }
}

#Preview("Choix") {
    ZStack {
        SheetBackground()
        ActivityChoiceScreen(onChoose: { _ in }, onCancel: {})
    }
}
