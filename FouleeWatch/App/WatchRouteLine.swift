import MapKit
import SwiftUI

/// The route as drawn on every watch map — the live « Plan » page and the
/// recap (issues #312, #320). One definition, so the two can never disagree
/// about what a route looks like.
///
/// One line per leg, in its sport's colour. **Never the colour alone**: there
/// is no room for a legend on a 40 mm, so each change of sport is marked where
/// it happened, with the new sport's glyph.
struct WatchRouteLine: MapContent {
    let portions: [WatchRoutePortion]

    /// Something to draw; below that, the screens say why there is none.
    static func isDrawable(_ portions: [WatchRoutePortion]) -> Bool {
        !portions.isEmpty
    }

    /// A camera that frames every point, with a margin so the line does not
    /// touch the edges (#320).
    ///
    /// Explicit rather than `.automatic`: on the recap's small map inside a
    /// scroll view, the automatic camera was measured to frame nothing — the
    /// whole route collapsed into a dot on an empty grid.
    static func camera(fitting portions: [WatchRoutePortion]) -> MapCameraPosition {
        let points = portions.flatMap(\.coordinates).map(MKMapPoint.init)
        guard let first = points.first else { return .automatic }
        var rect = MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
        for point in points.dropFirst() {
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        // A quarter of the larger side on every edge, and never less than about
        // 150 m across, so a short walk is not drawn at street-sign scale.
        let side = max(rect.width, rect.height, 150 * MKMapPointsPerMeterAtLatitude(first.coordinate.latitude))
        return .rect(rect.insetBy(dx: -side / 4, dy: -side / 4))
    }

    var body: some MapContent {
        ForEach(portions) { portion in
            MapPolyline(coordinates: portion.coordinates)
                .stroke(
                    portion.activity.tint,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
        }
        if let start = portions.first?.coordinates.first {
            Annotation("Départ", coordinate: start) {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            // The marks say it; on a 40 mm the words would cover the route.
            // VoiceOver still reads them.
            .annotationTitles(.hidden)
        }
        ForEach(portions.dropFirst()) { portion in
            if let change = portion.coordinates.first {
                Annotation(portion.activity.label, coordinate: change) {
                    Image(systemName: portion.activity.icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(portion.activity.tint, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 1))
                }
                .annotationTitles(.hidden)
            }
        }
    }
}
