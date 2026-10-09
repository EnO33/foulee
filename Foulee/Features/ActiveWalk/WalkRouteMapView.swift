import MapKit
import SwiftUI

/// Sheet that draws the path walked so far as a polyline over a map. Shows a
/// friendly empty state until enough fixes have come in to draw a line.
///
/// One line per stretch, in that stretch's colour: a single stroke for the
/// phone's own walk, one per portion for an outing mirrored from the wrist
/// (issue #334).
struct WalkRouteMapView: View {
    let strokes: [RouteLines.Stroke]
    var onClose: () -> Void

    /// The live route is a single stroke; its identity never changes.
    private static let strokeID = UUID()

    /// The phone's own walk: one stroke, in the accent colour — the phone
    /// cannot tell a walk from a run while it records (issue #246).
    init(route: [Coordinate], onClose: @escaping () -> Void) {
        self.strokes = [
            RouteLines.Stroke(
                id: Self.strokeID,
                coordinates: route.map(\.locationCoordinate),
                tint: FouleeColor.accentMid
            )
        ]
        self.onClose = onClose
    }

    init(strokes: [RouteLines.Stroke], onClose: @escaping () -> Void) {
        self.strokes = strokes
        self.onClose = onClose
    }

    private var isDrawable: Bool {
        strokes.contains { $0.coordinates.count >= 2 }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isDrawable {
                map
            } else {
                emptyState
            }
            closeButton
                .padding(20)
        }
    }

    private var map: some View {
        Map(initialPosition: .automatic) {
            RouteLines(strokes: strokes)
            if let last = strokes.last?.coordinates.last {
                Annotation("Position", coordinate: last) {
                    // Neutral glyph (#222): the map is drawn from a route, and
                    // nothing here knows whether it was walked or run.
                    Image(systemName: FouleeIcon.mixedCardio)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(FouleeColor.accentGradient, in: Circle())
                        .shadow(color: FouleeColor.accentMid.opacity(0.4), radius: 6, y: 3)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var emptyState: some View {
        ZStack {
            SheetBackground()
            VStack(spacing: 12) {
                Image(systemName: FouleeIcon.location)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(FouleeColor.accentMid)
                Text("Tracé en attente")
                    .font(FouleeFont.title3)
                Text("Ton parcours apparaîtra ici dès les premiers points GPS.")
                    .font(FouleeFont.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Fermer la carte")
    }
}

#Preview("Route") {
    WalkRouteMapView(
        route: [
            Coordinate(latitude: 48.8634, longitude: 2.3270),
            Coordinate(latitude: 48.8638, longitude: 2.3285),
            Coordinate(latitude: 48.8641, longitude: 2.3301),
            Coordinate(latitude: 48.8647, longitude: 2.3318)
        ],
        onClose: {}
    )
}

#Preview("Empty") {
    WalkRouteMapView(route: [], onClose: {})
}
