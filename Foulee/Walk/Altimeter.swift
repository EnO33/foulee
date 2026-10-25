import Dependencies
import FouleeKit
import Foundation

/// CoreMotion's `CMAltimeter` wrapped as a struct-of-closures (DI parity with
/// `Pedometer`). `startUpdates()` yields the cumulative climb and descent in
/// metres each time the barometer reports a fresh reading (issue #564).
nonisolated struct Altimeter: Sendable {
    var startUpdates: @Sendable () -> AsyncStream<Elevation>
    var stop: @Sendable () -> Void
}

nonisolated extension Altimeter: DependencyKey {
    static let previewValue = Altimeter(
        startUpdates: {
            AsyncStream { continuation in
                Task {
                    var elevation = Elevation.zero
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        elevation.ascent += 1.5
                        elevation.descent += 0.5
                        continuation.yield(elevation)
                    }
                    continuation.finish()
                }
            }
        },
        stop: {}
    )

    static let testValue = Altimeter(
        startUpdates: { AsyncStream { $0.finish() } },
        stop: {}
    )
}

nonisolated extension DependencyValues {
    var altimeter: Altimeter {
        get { self[Altimeter.self] }
        set { self[Altimeter.self] = newValue }
    }
}
