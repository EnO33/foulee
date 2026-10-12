import CoreLocation

/// The CoreLocation conversions both platforms need (issue #312).
///
/// Foundation-free of the `Dependencies` package so the watch target can
/// compile it: the phone's `LocationClient` and the watch's route store read
/// the same fixes, and spelling the conversion out at each call site is how
/// two of them ended up disagreeing about which field is which.
nonisolated public extension Coordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

nonisolated public extension CLAuthorizationStatus {
    /// Whether this status lets the app read a position at all. Not on macOS,
    /// which has no « when in use » grant and no Foulée to ask for one.
    @available(macOS, unavailable)
    var allowsLocation: Bool {
        self == .authorizedWhenInUse || self == .authorizedAlways
    }
}
