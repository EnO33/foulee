import CoreLocation

/// The wrist's side of the mirrored map (issue #334): the « Plan » page's
/// portions, thinned for the phone by the shared rules.
extension MirroredRoutePortion {
    /// The route the phone is sent.
    static func mirrored(_ portions: [WatchRoutePortion]) -> [MirroredRoutePortion] {
        thinning(portions.map { (activity: $0.activity, points: $0.coordinates) })
    }
}
