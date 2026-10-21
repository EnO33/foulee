import Foundation

/// What the phone asks of the session running on the Garmin watch (ADR 0009,
/// D7): « Arrêter la séance » on the mirror screen. The watch saves the
/// session as its own pause menu does, and the end reaches the phone the usual
/// way, through the outbox: the screen closes on the outcome, not on the tap.
///
/// The keys are the contract with `FouleeConnectIQ/source/SessionCommand.mc`.
nonisolated public enum GarminSessionCommand {
    public static let messageType = "command"
    public static let schemaVersion = 1

    public static var stop: [String: Any] {
        ["t": messageType, "v": schemaVersion, "action": "stop"]
    }
}
