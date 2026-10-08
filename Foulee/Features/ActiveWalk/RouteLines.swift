import MapKit
import SwiftUI

/// A route as the phone draws it: one line per stretch, in that stretch's
/// colour, and a start marker (issue #319).
///
/// Shared by the live walk's map and the detail's, so a route looks the same
/// whether it is being walked or remembered.
struct RouteLines: MapContent {
    struct Stroke: Identifiable {
        var id: UUID
        var coordinates: [CLLocationCoordinate2D]
        var tint: Color
    }

    let strokes: [Stroke]
    /// The stroke a finger picked (#319): drawn thicker, the others faded.
    var highlighted: UUID?

    var body: some MapContent {
        ForEach(strokes) { stroke in
            MapPolyline(coordinates: stroke.coordinates)
                .stroke(
                    stroke.tint.opacity(highlighted.map { $0 == stroke.id ? 1 : 0.35 } ?? 1),
                    style: StrokeStyle(
                        lineWidth: highlighted == stroke.id ? 8 : 5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
        if let start = strokes.first?.coordinates.first {
            Annotation("Départ", coordinate: start) {
                Circle()
                    .fill(FouleeColor.success)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
    }
}
