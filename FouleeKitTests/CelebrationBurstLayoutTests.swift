import Foundation
import Testing
@testable import FouleeKit

@Suite("CelebrationBurstLayout")
struct CelebrationBurstLayoutTests {
    @Test("The full burst flies every dot from the centre out to its circle")
    func fullBurstTravels() {
        let layout = CelebrationBurstLayout(pieceCount: 4, radius: 100, reduceMotion: false)
        let start = layout.piece(0, expanded: false)
        let end = layout.piece(0, expanded: true)
        #expect(start.x == 0 && start.y == 0)
        #expect(abs(end.x - 100) < 0.001)
        #expect(start.scale == 1 && end.scale == 0.3)
        #expect(start.opacity == 1 && end.opacity == 0)
    }

    @Test("With reduced motion, no dot moves or resizes: it only fades", arguments: 0..<16)
    func reducedOnlyFades(index: Int) {
        let layout = CelebrationBurstLayout(pieceCount: 16, radius: 130, reduceMotion: true)
        let start = layout.piece(index, expanded: false)
        let end = layout.piece(index, expanded: true)
        #expect(start.x == end.x && start.y == end.y)
        #expect(start.scale == end.scale)
        #expect(start.opacity == 1 && end.opacity == 0)
        #expect(abs(hypot(start.x, start.y) - 130) < 0.001)
    }
}
