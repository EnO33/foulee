import Foundation
import Testing
@testable import FouleeKit

/// The keys below are the contract with
/// `FouleeConnectIQ/source/SessionCommand.mc`.
@Suite("Garmin session command")
struct GarminSessionCommandTests {
    @Test("Stop is the command message the watch recognises")
    func stop() {
        let message = GarminSessionCommand.stop
        #expect(message["t"] as? String == "command")
        #expect(message["v"] as? Int == 1)
        #expect(message["action"] as? String == "stop")
        #expect(message.count == 3)
    }
}
