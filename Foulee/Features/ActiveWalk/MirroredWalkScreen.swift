import SwiftUI

/// The outing running on the wrist, as the phone can show it (issue #279).
///
/// **Read-only, and that is not a limitation to apologise for.** The watch owns
/// the session — there is no API that would let the phone measure one and mirror
/// it back — so this screen states what the wrist says and nothing else. Issue
/// #282 adds a stop button; it will still be a remote control, not a second
/// engine.
///
/// **It dates its figures.** HealthKit caches what a mirrored session sends and
/// wakes this app *periodically*, potentially minutes apart, so « en direct »
/// would be a lie for most of an outing. The clock runs — it is derived from a
/// date, so it needs no delivery to advance — while the counters carry the age
/// of the last thing the wrist actually said.
///
/// That split is the whole design of this screen: the one number that can be
/// honest in real time is big, and everything that cannot is labelled.
struct MirroredWalkScreen: View {
    let store: MirroredSessionStore
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    clock
                    figures
                    stopButton
                    origin
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .navigationTitle("Sortie en cours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer", action: onDismiss)
                }
            }
        }
    }

    /// The one figure that can be honest between two deliveries: derived from
    /// the outing's start date, so it advances on this device's own clock.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4) {
                Text(elapsed(at: context.date).walkClockText)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(store.session?.activity.label ?? "Séance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(store.session?.activity.label ?? "Séance") en cours depuis "
                    + elapsed(at: context.date).walkClockText
            )
        }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        guard let start = store.outingStartedAt else { return 0 }
        return max(0, date.timeIntervalSince(start))
    }

    /// The counters, or an honest wait.
    ///
    /// `nil` figures is a real state and not a flash: HealthKit may take
    /// minutes to deliver the first batch. Zeros would look measured.
    @ViewBuilder
    private var figures: some View {
        if let figures = store.figures {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    tile("\(figures.steps.formatted())", "pas")
                    tile(figures.distanceKm.kmValue(), "km")
                }
                HStack(spacing: 12) {
                    tile("\(figures.activeCalories)", "kcal")
                    tile(figures.heartRate.map { "\($0)" } ?? "—", "bpm")
                }
                freshness(figures)
            }
        } else {
            Text("En attente des chiffres de ta Watch")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// « Relevé il y a 2 min ». The line that keeps this screen from lying.
    private func freshness(_ figures: WatchSessionSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(Self.ageText(figures.age(at: context.date)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Rounded to the minute past a minute: a second-precise age on figures
    /// that arrive in batches would imply a precision the link does not have.
    ///
    /// Static and internal so the wording is asserted rather than eyeballed —
    /// this is the line that keeps the screen from claiming to be live, and a
    /// `View` body is not somewhere a test can reach.
    static func ageText(_ age: TimeInterval) -> String {
        guard age >= 60 else { return "Relevé à l'instant" }
        return "Relevé il y a \(Int(age / 60)) min"
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    /// Ends the outing — on the wrist (issue #282).
    ///
    /// The screen does not close on the tap. It closes when the watch says the
    /// outing is over, because until then it is not: `stop()` still has to fold
    /// the figures and save, and it can fail and offer « Réessayer ». Dismissing
    /// early would claim an outcome the phone has no way of knowing.
    private var stopButton: some View {
        Button(role: .destructive) {
            Task { await store.requestStop() }
        } label: {
            Label("Arrêter la séance", systemImage: "stop.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
    }

    /// Says where the session lives, so « pourquoi ça s'arrête depuis ma
    /// montre ? » has an answer on screen rather than in a support thread.
    private var origin: some View {
        Label("Mesurée par ta Apple Watch", systemImage: "applewatch")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
