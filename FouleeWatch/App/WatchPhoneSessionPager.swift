import FouleeKit
import MapKit
import SwiftUI

/// The phone's session on the wrist (issue #342): the figures, the controls
/// and the route, paged like a watch session.
///
/// The figures page **is** the watch session's own page, fed from the phone:
/// one way to read a session, whichever device records it. The phone has no
/// heart-rate sensor, so its tile shows a dash.
///
/// The same order as the wrist's own session (ADR 0008): the controls to the
/// left of the figures, which are the page it opens on.
struct WatchPhoneSessionPager: View {
    let snapshot: PhoneSessionSnapshot
    var isSending: Bool
    var errorMessage: String?
    var onCommand: (PhoneSessionCommand) -> Void

    // Opens on the figures, with the controls one swipe to the left.
    // periphery:ignore - read only through `$page`, like the route page's
    // camera: Periphery 3.8 does not count a macro `@State`'s projected value
    // as a use (issue #404).
    @State private var page: WatchSessionPage = .session

    var body: some View {
        let metrics = snapshot.metrics
        TabView(selection: $page) {
            WatchPhoneSessionControlsPage(
                snapshot: snapshot,
                metrics: metrics,
                isSending: isSending,
                onCommand: onCommand
            )
            .tag(WatchSessionPage.controls)
            WatchSessionMetricsPage(metrics: metrics, errorMessage: errorMessage)
                .tag(WatchSessionPage.session)
            WatchPhoneSessionRoutePage(portions: snapshot.routePortions)
                .tag(WatchSessionPage.route)
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

                HStack(alignment: .top, spacing: 16) {
                    WatchControlButton(
                        title: "Terminer",
                        systemImage: "xmark",
                        tint: .red,
                        role: .destructive,
                        action: { onCommand(.stop) }
                    )
                    WatchControlButton(
                        title: isPaused ? "Reprendre" : "Pause",
                        systemImage: isPaused ? "play.fill" : "pause.fill",
                        tint: isPaused ? .green : .yellow,
                        action: { onCommand(isPaused ? .resume : .pause) }
                    )
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
        .sessionPage("Contrôles")
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
        .sessionPage("Plan du parcours")
    }
}
