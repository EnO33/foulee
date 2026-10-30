import Dependencies
import FouleeKit
import SwiftUI

/// The outing running on the wrist, as the phone can show it (issue #279).
///
/// **Read-only, and that is not a limitation to apologise for.** The watch owns
/// the session — there is no API that would let the phone measure one and mirror
/// it back — so this screen states what the wrist says and nothing else. Issue
/// #282 adds a stop button; it will still be a remote control, not a second
/// engine. A Garmin outing (ADR 0009, D7) shows the same screen, stop button
/// included.
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

    /// The app's clock, not the timeline's: the same instant in production,
    /// and the pinned one in a capture run, where the outing's start is seeded
    /// against it.
    @Dependency(\.date) private var date

    @State private var isShowingRoute = false
    /// Measured, never guessed from the device (#662).
    @State private var layout = LiveWalkLayout(size: LiveWalkLayout.referenceSize)

    private var device: MirroredDevice { store.session?.device ?? .appleWatch }

    var body: some View {
        NavigationStack {
            HStack(spacing: LiveWalkLayout.spacing) {
                ScrollView {
                    VStack(spacing: 24) {
                        clock
                        figures
                        routeButton
                        stopButton
                        origin
                    }
                    .screenColumn()
                    .padding(.top, 12)
                }
                // Wider than tall, the route sits beside the figures rather
                // than behind « Voir le parcours » (#662).
                if isRouteDrawable && layout.isSideBySide {
                    WalkRouteMap(strokes: routeStrokes)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .padding([.trailing, .bottom], 20)
                }
            }
            .onGeometryChange(for: LiveWalkLayout.self) { LiveWalkLayout(size: $0.size) } action: { layout = $0 }
            .navigationTitle("Sortie en cours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer", action: onDismiss)
                }
            }
            .sheet(isPresented: $isShowingRoute) {
                // Read inside the sheet, so the map grows with each wake
                // rather than freezing on the route it opened with.
                WalkRouteMapView(strokes: routeStrokes) { isShowingRoute = false }
            }
        }
    }

    private var routeStrokes: [RouteLines.Stroke] {
        MirroredRoutePortion.strokes(store.figures?.route ?? [])
    }

    /// The route the wrist is recording (issue #334) — offered only once there
    /// is a line to draw: location refused, or no fix yet, and the button
    /// would open an empty map.
    private var isRouteDrawable: Bool {
        store.figures?.route.isDrawable == true
    }

    @ViewBuilder
    private var routeButton: some View {
        if isRouteDrawable && !layout.isSideBySide {
            Button {
                isShowingRoute = true
            } label: {
                Label("Voir le parcours", systemImage: "map")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            // The accent is too light for its text (issue #658).
            .tint(ReadablePalette.purpleText)
        }
    }

    /// The one figure that can be honest between two deliveries: derived from
    /// the outing's start date, so it advances on this device's own clock.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = date.now
            VStack(spacing: 4) {
                Text(elapsed(at: now).walkClockText)
                    .scaledNumericFont(size: 56, weight: .semibold)
                Text(store.figures?.isPaused == true ? String(localized: "En pause") : activityLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(
                "\(activityLabel) en cours depuis \(spokenDurationText(seconds: elapsed(at: now)))"
            ))
        }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        // Paused on the wrist: the figures' own clock, which stands still
        // (issue #384).
        if let figures = store.figures, figures.isPaused { return figures.elapsed(at: date) }
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
                    tile("\(figures.steps.groupedText())", "pas")
                    tile(figures.distanceKm.kmValue(), "km")
                }
                HStack(spacing: 12) {
                    // The Garmin watch states no calories: a dash, not a
                    // measured zero.
                    tile(device == .garmin ? "—" : "\(figures.activeCalories)", "kcal")
                    tile(figures.heartRate.map { "\($0)" } ?? "—", "bpm", spokenUnit: "battements par minute")
                }
                // The outing's average, the only pace honest enough to state:
                // over a whole sortie the relative error of a wrist-estimated
                // distance averages out and the duration is exact (issue #298).
                if let pace = figures.averagePaceText {
                    Label(pace, systemImage: "speedometer")
                        .font(.subheadline)
                        .monospacedDigit()
                        .accessibilityLabel("Allure moyenne \(figures.averagePaceSpokenText ?? pace)")
                }
                // The wrist's climb and descent, when its barometer measured
                // any (issue #535).
                if let elevation = figures.elevationText {
                    Label(elevation, systemImage: FouleeIcon.climb)
                        .font(.subheadline)
                        .monospacedDigit()
                        .accessibilityLabel(figures.elevationSpokenText ?? elevation)
                }
                freshness(figures)
            }
        } else {
            Text("En attente des chiffres de \(device.name)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// « Relevé il y a 2 min ». The line that keeps this screen from lying.
    private func freshness(_ figures: WatchSessionSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            Text(Self.ageText(figures.age(at: date.now)))
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
    private var activityLabel: String {
        store.session?.activity.label ?? String(localized: "Séance")
    }

    static func ageText(_ age: TimeInterval) -> String {
        guard age >= 60 else { return String(localized: "Relevé à l'instant") }
        return String(localized: "Relevé il y a \(Int(age / 60)) min")
    }

    /// `spokenUnit` when the written one is an abbreviation VoiceOver spells
    /// out letter by letter — « bpm ».
    private func tile(_ value: String, _ label: LocalizedStringResource, spokenUnit: LocalizedStringResource? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .scaledNumericFont(size: 28, weight: .semibold)
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
        .accessibilityLabel(Text("\(value) \(spokenUnit ?? label)"))
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
        Label(device == .garmin ? "Mesurée par ta montre Garmin" : "Mesurée par ta Apple Watch", systemImage: device.icon)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
