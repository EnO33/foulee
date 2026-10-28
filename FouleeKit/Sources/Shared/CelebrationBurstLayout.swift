import Foundation

/// Where each dot of the « you did it » burst sits, before and after its one
/// animation (issue #598).
///
/// The full burst flies the dots out from the centre and shrinks them. With
/// « Réduire les animations », nothing travels: the dots appear on their circle
/// and only fade, the one change the system still allows.
nonisolated public struct CelebrationBurstLayout: Equatable, Sendable {
    public struct Piece: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let scale: Double
        public let opacity: Double
    }

    public let pieceCount: Int
    public let radius: Double
    public let reduceMotion: Bool

    public init(pieceCount: Int, radius: Double, reduceMotion: Bool) {
        self.pieceCount = pieceCount
        self.radius = radius
        self.reduceMotion = reduceMotion
    }

    /// Piece `index` before (`expanded == false`) or after the animation.
    public func piece(_ index: Int, expanded: Bool) -> Piece {
        let angle = Double(index) / Double(pieceCount) * 2 * .pi
        let distance = reduceMotion || expanded ? radius : 0
        return Piece(
            x: cos(angle) * distance,
            y: sin(angle) * distance,
            scale: reduceMotion ? 0.6 : (expanded ? 0.3 : 1),
            opacity: expanded ? 0 : 1
        )
    }
}
