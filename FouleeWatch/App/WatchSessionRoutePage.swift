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

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Group {
            if route.coordinates.count >= 2 {
                map
            } else {
                emptyState
            }
        }
        .accessibilityLabel("Plan du parcours")
    }

    private var map: some View {
        Map(position: $position, interactionModes: .zoom) {
            MapPolyline(coordinates: route.coordinates)
                .stroke(
                    .tint,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            if let start = route.coordinates.first {
                Annotation("Départ", coordinate: start) {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
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
