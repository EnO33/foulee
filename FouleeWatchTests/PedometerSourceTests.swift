import Foundation
import Testing
@testable import FouleeWatch

/// The CoreMotion boundary of the pedometer (issue #338).
///
/// `CMPedometer` calls its handler on a queue of its own. A handler that
/// inherited the main actor's isolation was checked on entry by Swift 6 and
/// killed the app at the first update of every outing on foot — a crash no
/// simulator showed, since none has a pedometer.
@Suite("Pedometer source")
struct PedometerSourceTests {
    /// Called the way CoreMotion calls it: off the main actor. A handler
    /// isolated to the main actor traps right here.
    @Test("CoreMotion's own queue may call the handler")
    func callableOffTheMainActor() async {
        let handler = PedometerSource.updateHandler { _ in
            Issue.record("no data must forward no reading")
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                handler(nil, nil)
                handler(nil, CocoaError(.featureUnsupported))
                continuation.resume()
            }
        }
    }
}
