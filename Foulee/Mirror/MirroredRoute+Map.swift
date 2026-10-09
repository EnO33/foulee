import MapKit
import SwiftUI

extension MirroredRoutePortion {
    /// The mirrored route as the phone's map draws it: one stroke per portion,
    /// in its sport's colour (issue #334).
    ///
    /// Identities derived from the position, not drawn at random: the route is
    /// resent whole at every wake, and a stroke that changed identity each time
    /// would be torn down and redrawn instead of simply growing.
    static func strokes(_ portions: [MirroredRoutePortion]) -> [RouteLines.Stroke] {
        portions.enumerated().map { index, portion in
            RouteLines.Stroke(
                id: strokeID(at: index),
                coordinates: portion.coordinates.map(\.locationCoordinate),
                tint: portion.activity.tint
            )
        }
    }

    static func strokeID(at index: Int) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0,
            UInt8(truncatingIfNeeded: index >> 8),
            UInt8(truncatingIfNeeded: index)
        ))
    }
}
