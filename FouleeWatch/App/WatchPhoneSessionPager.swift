import MapKit
import SwiftUI

/// The phone's session on the wrist (issue #342): the figures, the controls
/// and the route, paged like a watch session.
///
/// The figures page **is** the watch session's own page, fed from the phone:
/// one way to read a session, whichever device records it. The phone has no
/// heart-rate sensor, so its tile shows a dash.
struct WatchPhoneSessionPager: View {
    let snapshot: PhoneSessionSnapshot
    var isSending: Bool
    var errorMessage: String?
    var onCommand: (PhoneSessionCommand) -> Void

    var body: some View {
        let metrics = snapshot.metrics
        TabView {
            WatchSessionMetricsPage(metrics: metrics, errorMessage: errorMessage)
            WatchPhoneSessionControlsPage(
                snapshot: snapshot,
                metrics: metrics,
                isSending: isSending,
                onCommand: onCommand
            )
            WatchPhoneSessionRoutePage(portions: snapshot.routePortions)
        }
        .tabViewStyle(.page)
    }
}

/// Pause, resume and stop the phone's session — next to the figures, so
/// ending it is never more than one gesture away (issue #274's rule).
///
/// The buttons ask; the screen changes when the phone says the session did.
private struct WatchPhoneSessionControlsPage: View {
    let snapshot: PhoneSessionSnapshot
    let metrics: WatchWorkoutMetrics
    var isSending: Bool
    var onCommand: (PhoneSessionCommand) -> Void

    private var isPaused: Bool { snapshot.phase == .paused }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Label("Séance de l'iPhone", systemImage: "iphone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                WatchSessionClock(metrics: metrics, size: 22)
                    .foregroundStyle(.secondary)

                Button {
                    onCommand(isPaused ? .resume : .pause)
                } label: {
                    Label(isPaused ? "Reprendre" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                Button(role: .destructive) {
                    onCommand(.stop)
                } label: {
                    Label("Terminer", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }

                // How old the figures are, rather than a pretence of live (ADR 0003, D2).
                Text("Relevé il y a \(snapshot.sentAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .disabled(isSending)
            .padding(.horizontal, 6)
            .padding(.top, 8)
        }
        .accessibilityLabel("Contrôles")
    }
}

/// The phone's route, framed to fit as it grows. Zoom only, like the watch's
/// own « Plan » page: a map that pans would swallow the pager's swipe.
private struct WatchPhoneSessionRoutePage: View {
    let portions: [WatchRoutePortion]

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Group {
            if WatchRouteLine.isDrawable(portions) {
                Map(position: $position, interactionModes: .zoom) {
                    WatchRouteLine(portions: portions)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .onAppear { position = WatchRouteLine.camera(fitting: portions) }
                .onChange(of: portions.map(\.coordinates.count)) {
                    position = WatchRouteLine.camera(fitting: portions)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "location")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Text("Tracé en attente")
                        .font(.headline)
                    Text("Le parcours de l'iPhone apparaîtra dès ses premiers points GPS.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .accessibilityLabel("Plan du parcours")
    }
}
