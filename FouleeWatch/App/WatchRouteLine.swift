import MapKit
import SwiftUI

/// The route as drawn on every watch map — the live « Plan » page and the
/// recap (issue #312). One definition, so the two can never disagree about
/// what a route looks like.
struct WatchRouteLine: MapContent {
    let coordinates: [CLLocationCoordinate2D]

    /// A line needs two points; below that, the screens say why there is none.
    static func isDrawable(_ coordinates: [CLLocationCoordinate2D]) -> Bool {
        coordinates.count >= 2
    }

    var body: some MapContent {
        MapPolyline(coordinates: coordinates)
            .stroke(
                .tint,
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
        if let start = coordinates.first {
            Annotation("Départ", coordinate: start) {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
    }
}
