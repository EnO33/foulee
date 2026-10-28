import MapKit
import SwiftUI

/// The path walked so far, on a map that follows the wearer (issue #312).
///
/// **Zoom only — no panning.** The pager pages horizontally, and a map that
/// pans takes every drag for itself: on this page, a swipe would move the map
/// instead of the page, and « Arrêter » would stop being one gesture away —
/// the defect of issues #241 and #274 by a third route. The Digital Crown
/// zooms; the map recentres on the wearer by itself.
struct WatchSessionRoutePage: View {
    let route: WatchRouteStore
    /// For the legs the route is cut at, and the sport being done now (#320).
    let metrics: WatchWorkoutMetrics

    // periphery:ignore - read only through `$` bindings. Since Xcode 27,
    // `@State` is a macro and Periphery 3.8 no longer counts the projected
    // value as a use of the property (issue #404).
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        // Cut once per render, in one pass over the fixes.
        let portions = WatchRoutePortion.portions(
            of: route.locations,
            legs: metrics.legs,
            current: metrics.activity
        )
        Group {
            if WatchRouteLine.isDrawable(portions) {
                map(portions)
            } else {
                emptyState
            }
        }
        .sessionPage("Plan du parcours")
    }

    private func map(_ portions: [WatchRoutePortion]) -> some View {
        Map(position: $position, interactionModes: .zoom) {
            WatchRouteLine(portions: portions)
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .overlay(alignment: .top) { elevation }
    }

    /// « ↑ 120 m · ↓ 115 m » over the map (issue #535). Here rather than on
    /// the counters' page: a 40 mm has no room there for a fifth tile, and the
    /// climb is the route's, the way Exercice puts it beside its own map.
    @ViewBuilder
    private var elevation: some View {
        if let text = metrics.elevation.text {
            Text(text)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityLabel(metrics.elevation.spokenText ?? text)
        }
    }

    /// Two cases, two sentences: waiting for GPS resolves on its own, a refusal
    /// never will — the wearer has to know where to undo it.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: route.isDenied ? "location.slash" : "location")
                .font(.title2)
                .foregroundStyle(.tint)
            Text(route.isDenied ? "Position désactivée" : "Tracé en attente")
                .font(.headline)
            Text(
                route.isDenied
                    ? "Autorise la position pour Foulée dans Réglages."
                    : "Ton parcours apparaîtra dès les premiers points GPS."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }
}
