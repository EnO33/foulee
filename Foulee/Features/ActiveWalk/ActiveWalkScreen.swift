import Dependencies
import SwiftUI

/// Live walk screen — chip "EN COURS" + big timer + progress ring with
/// pas/distance/kcal + control row. Renders three distinct presentations
/// depending on `store.state`.
struct ActiveWalkScreen: View {
    let minutesGoal: Int
    /// What Santé will record this session as (issue #223) — or `.ask` when
    /// the user is in « les deux » and only they can say (issue #224).
    ///
    /// Resolved by `TodayStore`, not here: a `View` body is out of reach of the
    /// test process, and this is the value the stamp is made of.
    let intent: ActivityStartIntent
    var onDismiss: (WalkSession) -> Void
    /// Backed out of the picker without starting anything. Distinct from
    /// `onDismiss`, which carries a finished session for the home to overlay —
    /// there is no session here, and registering an empty one would move the
    /// step baseline for a walk that never happened.
    var onCancel: () -> Void

    @State private var store: ActiveWalkStore
    @State private var showRoute = false

    /// The store is a defaulted parameter for the same reason `WatchIdleScreen`
    /// takes its `onStart` from above: built inside the body it is invisible to
    /// a test, and the two hops it hides — the `.onAppear` guard that must
    /// *not* start anything in « les deux », and the answer that carries the
    /// chosen activity into the session — are where the phone turns a tap into
    /// a permanent Santé stamp (issue #224). Handed in, a test drives the
    /// screen that ships and reads what it actually started.
    init(
        minutesGoal: Int,
        intent: ActivityStartIntent,
        store: ActiveWalkStore = ActiveWalkStore(),
        onDismiss: @escaping (WalkSession) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.minutesGoal = minutesGoal
        self.intent = intent
        self.onDismiss = onDismiss
        self.onCancel = onCancel
        _store = State(wrappedValue: store)
    }

    var body: some View {
        ZStack {
            SheetBackground()
            content
        }
        .onAppear { startIfKnown() }
        .onDisappear { store.reset() }
        .sheet(isPresented: $showRoute) {
            WalkRouteMapView(route: store.route) { showRoute = false }
        }
        // Haptics: a tap when the walk starts or resumes, a success buzz when
        // it's finished. The closure form fires only on the rising edge.
        .sensoryFeedback(trigger: isActiveState) { _, now in now ? .impact(weight: .medium) : nil }
        .sensoryFeedback(trigger: isFinishedState) { _, now in now ? .success : nil }
    }

    /// Starts the session as soon as the screen appears — but only when the
    /// mode already answers the question. In « les deux » it does nothing at
    /// all: the picker is what the screen shows instead, and nothing may be
    /// recorded before the user has said what this session is.
    ///
    /// A named method rather than the body of `.onAppear`, and internal rather
    /// than private, because `.onAppear` never fires in a test process: inlined
    /// there, this guard could be dropped — every « les deux » session silently
    /// stamped a walk again — with the whole suite green.
    func startIfKnown() {
        guard let activity = intent.immediate else { return }
        store.start(minutesGoal: minutesGoal, activity: activity)
    }

    private var isActiveState: Bool {
        if case .active = store.state { return true }
        return false
    }

    private var isFinishedState: Bool {
        if case .finished = store.state { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle:
            // Idle means "nothing started yet", which is where the question
            // belongs: `.ask` shows the picker, every other mode shows the
            // brief spinner it always did while `onAppear` starts the session.
            if case .ask = intent {
                ActivityChoiceScreen(
                    onChoose: { store.start(minutesGoal: minutesGoal, activity: $0) },
                    onCancel: onCancel
                )
            } else {
                ProgressView()
            }
        case .active(let session):
            walkBody(session: session, paused: false)
        case .paused(let session):
            walkBody(session: session, paused: true)
        case .finished(let session):
            finishedBody(session: session)
        }
    }

    private func walkBody(session: WalkSession, paused: Bool) -> some View {
        VStack(spacing: 0) {
            header(paused: paused)
            timer(session: session)
            ring(session: session)
            heartRatePlaceholder
            Spacer(minLength: 0)
            controls(paused: paused)
        }
        .padding(.top, 60)
        .padding(.bottom, 56)
    }

    private func header(paused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Chip(
                label: paused ? "EN PAUSE" : "EN COURS",
                systemIcon: paused ? FouleeIcon.pause : nil,
                tint: paused ? FouleeColor.warning : FouleeColor.success,
                fill: (paused ? FouleeColor.warning : FouleeColor.success).opacity(0.16)
            )
            // Neutral, and no longer tied to a time of day (#222): this screen
            // is opened whenever the user taps start, and the chip above it
            // already says whether it is running or paused.
            Text("Ta sortie")
                .font(FouleeFont.largeTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private func timer(session: WalkSession) -> some View {
        VStack(spacing: 6) {
            Text(session.elapsed.walkClockText)
                .kerning(-2)
                .scaledNumericFont(size: 86, weight: .ultraLight)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("DURÉE")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
        }
        .padding(.top, 30)
    }

    private func ring(session: WalkSession) -> some View {
        let goalSeconds = TimeInterval(minutesGoal * 60)
        let progress = goalSeconds > 0 ? session.elapsed / goalSeconds : 0
        return ProgressRing(progress: progress, lineWidth: 16) {
            VStack(spacing: 4) {
                Text(session.steps.formattedFR)
                    .scaledNumericFont(size: 56)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("PAS")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    metric(value: session.distanceKm.kmText(fractionDigits: 1), label: "Distance")
                    ringDivider
                    metric(value: "\(session.estimatedCalories) kcal", label: "Énergie")
                    ringDivider
                    metric(value: "\(Int(session.elevationGainMeters)) m", label: "Dénivelé")
                }
                .padding(.top, 8)
            }
        }
        .frame(width: 232, height: 232)
        .padding(.top, 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sortie en cours")
        .accessibilityValue(
            "\(session.steps.formattedFR) pas, "
            + "\(session.distanceKm.kmText(fractionDigits: 1)), "
            + "\(session.estimatedCalories) kilocalories, "
            + "\(Int(session.elevationGainMeters)) mètres de dénivelé"
        )
    }

    private var ringDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 1, height: 28)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .scaledNumericFont(size: 17, weight: .semibold)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var heartRatePlaceholder: some View {
        HStack(spacing: 10) {
            Image(systemName: FouleeIcon.heart)
                .scaledSystemFont(size: 20)
                .foregroundStyle(FouleeColor.danger)
            Text("Connecte ta Watch pour le rythme cardiaque")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .fouleeGlass(cornerRadius: 22)
        .padding(.horizontal, 20)
        .padding(.top, 32)
    }

    private func controls(paused: Bool) -> some View {
        HStack(spacing: 28) {
            controlButton(icon: FouleeIcon.stop, color: FouleeColor.danger, label: "Arrêter") {
                Task { await store.stop() }
            }
            if paused {
                controlButton(icon: FouleeIcon.play, color: FouleeColor.accentMid, label: "Reprendre", big: true) {
                    store.resume()
                }
            } else {
                controlButton(icon: FouleeIcon.pause, color: FouleeColor.accentMid, label: "Pause", big: true) {
                    Task { await store.pause() }
                }
            }
            controlButton(icon: FouleeIcon.location, color: Color(hex: 0x0A84FF), label: "Carte") {
                showRoute = true
            }
        }
        .padding(.bottom, 40)
    }

    private func controlButton(
        icon: String,
        color: Color,
        label: String,
        big: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: big ? 32 : 24, weight: .semibold))
                    .foregroundStyle(big ? AnyShapeStyle(Color.white) : AnyShapeStyle(color))
                    .frame(width: big ? 80 : 62, height: big ? 80 : 62)
                    .background(
                        big
                            ? AnyShapeStyle(FouleeColor.accentGradient)
                            : AnyShapeStyle(.ultraThinMaterial),
                        in: Circle()
                    )
                    .shadow(
                        color: big ? FouleeColor.accentMid.opacity(0.4) : .black.opacity(0.15),
                        radius: big ? 18 : 8, x: 0, y: 6
                    )
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(label)
            Text(label)
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

}

/// The end-of-session presentation. In an extension so the screen's own
/// type body stays inside the length budget — and it reads as one piece:
/// nothing here decides anything, it draws a session that is already over.
private extension ActiveWalkScreen {
    func finishedBody(session: WalkSession) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                CelebrationBurst()
                Image(systemName: FouleeIcon.check)
                    .font(.system(size: 84, weight: .bold))
                    .foregroundStyle(FouleeColor.accentGradient)
                    .symbolEffect(.bounce, value: isFinishedState)
            }
            Text("Sortie terminée")
                .font(FouleeFont.title2)
            VStack(spacing: 4) {
                Text(session.elapsed.walkClockText)
                    .scaledNumericFont(size: 48)
                Text(finishedSummary(session: session))
                    .font(FouleeFont.callout)
                    .foregroundStyle(.secondary)
            }
            if let lastError = store.lastError {
                Text(lastError)
                    .font(FouleeFont.footnote)
                    .foregroundStyle(FouleeColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            PrimaryButton(title: "Terminer", systemIcon: FouleeIcon.check) { onDismiss(session) }
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 32)
    }

    func finishedSummary(session: WalkSession) -> String {
        var parts = ["\(session.steps.formattedFR) pas", session.distanceKm.kmText()]
        if session.elevationGainMeters >= 1 {
            parts.append("↑ \(Int(session.elevationGainMeters)) m")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ActiveWalkPreview: View {
    init() {
        prepareDependencies {
            $0.healthKit = .previewValue
            $0.pedometer = .previewValue
        }
    }
    var body: some View {
        ActiveWalkScreen(minutesGoal: 20, intent: .start(.walking), onDismiss: { _ in }, onCancel: {})
    }
}

#Preview("Active") { ActiveWalkPreview() }
