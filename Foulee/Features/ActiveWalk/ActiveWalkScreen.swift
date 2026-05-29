import Dependencies
import SwiftUI

/// Live walk screen — chip "EN COURS" + big timer + progress ring with
/// pas/distance/kcal + control row. Renders three distinct presentations
/// depending on `store.state`.
struct ActiveWalkScreen: View {
    let minutesGoal: Int
    var onDismiss: () -> Void

    @State private var store = ActiveWalkStore()

    var body: some View {
        ZStack {
            SheetBackground()
            content
        }
        .onAppear { store.start(minutesGoal: minutesGoal) }
        .onDisappear { store.reset() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle:
            ProgressView()
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

    private func finishedBody(session: WalkSession) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: FouleeIcon.check)
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(FouleeColor.accentGradient)
            Text("Marche terminée")
                .font(FouleeFont.title2)
            VStack(spacing: 4) {
                Text(session.elapsed.walkClockText)
                    .font(FouleeFont.numeric(size: 48))
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
            PrimaryButton(title: "Terminer", systemIcon: FouleeIcon.check, action: onDismiss)
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 32)
    }

    private func finishedSummary(session: WalkSession) -> String {
        "\(session.steps.formattedFR) pas · \(session.distanceKm.kmText())"
    }

    private func header(paused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Chip(
                label: paused ? "EN PAUSE" : "EN COURS",
                systemIcon: paused ? FouleeIcon.pause : nil,
                tint: paused ? FouleeColor.warning : FouleeColor.success,
                fill: (paused ? FouleeColor.warning : FouleeColor.success).opacity(0.16)
            )
            Text("Marche du midi")
                .font(FouleeFont.largeTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private func timer(session: WalkSession) -> some View {
        VStack(spacing: 6) {
            Text(session.elapsed.walkClockText)
                .font(.system(size: 86, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .kerning(-2)
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
                    .font(FouleeFont.numeric(size: 56))
                Text("PAS")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    metric(value: session.distanceKm.kmText(fractionDigits: 1), label: "Distance")
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 28)
                    metric(value: "\(session.estimatedCalories) kcal", label: "Énergie")
                }
                .padding(.top, 8)
            }
        }
        .frame(width: 232, height: 232)
        .padding(.top, 22)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(FouleeFont.numeric(size: 17, weight: .semibold))
            Text(label)
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var heartRatePlaceholder: some View {
        HStack(spacing: 10) {
            Image(systemName: FouleeIcon.heart)
                .font(.system(size: 20))
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
                // Map view ships in a later PR.
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
            Text(label)
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
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
        ActiveWalkScreen(minutesGoal: 20, onDismiss: {})
    }
}

#Preview("Active") { ActiveWalkPreview() }
