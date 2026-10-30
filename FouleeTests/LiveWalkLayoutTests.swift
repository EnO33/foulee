import CoreGraphics
import Testing
@testable import Foulee

/// The outing in progress decides its layout on the space it is given
/// (#662): a phone keeps the layout it always had, the inner screen held
/// open puts the map beside the figures and grows the ring.
@Suite("Live walk layout")
struct LiveWalkLayoutTests {
    @Test("A phone keeps the stacked layout and the 232 pt ring", arguments: [
        CGSize(width: 375, height: 667),
        CGSize(width: 393, height: 852),
        CGSize(width: 440, height: 956)
    ])
    func phoneKeepsItsLayout(size: CGSize) {
        let layout = LiveWalkLayout(size: size)
        #expect(!layout.isSideBySide)
        #expect(layout.scale == 1)
    }

    @Test("Wider than tall puts the map beside the figures")
    func widerThanTallIsSideBySide() {
        #expect(LiveWalkLayout(size: CGSize(width: 1000, height: 760)).isSideBySide)
    }

    @Test("A short window too narrow for two panes keeps the stacked layout", arguments: [
        CGSize(width: 440, height: 400),
        CGSize(width: 663, height: 500)
    ])
    func narrowWindowStaysStacked(size: CGSize) {
        let layout = LiveWalkLayout(size: size)
        #expect(!layout.isSideBySide)
        #expect(layout.scale == 1)
    }

    @Test("Resized, the layout follows the new size")
    func layoutFollowsTheResize() {
        let inner = CGSize(width: 1000, height: 760)
        let outer = CGSize(width: 393, height: 852)
        #expect(LiveWalkLayout(size: inner) != LiveWalkLayout(size: outer))
        #expect(LiveWalkLayout(size: outer) == LiveWalkLayout(size: CGSize(width: 393, height: 852)))
    }

    @Test("Tall and wide, the ring grows with the height it has")
    func ringGrowsWithTheRoom() {
        let layout = LiveWalkLayout(size: CGSize(width: 760, height: 1032))
        #expect(!layout.isSideBySide)
        #expect(layout.scale == 1032 / LiveWalkLayout.referenceSize.height)
    }

    @Test("The ring stops growing past its ceiling")
    func ringGrowthIsCapped() {
        let layout = LiveWalkLayout(size: CGSize(width: 2000, height: 3000))
        #expect(layout.scale == LiveWalkLayout.maxScale)
    }

    @Test("Beside the map the figures get half the width, so the ring does not grow past it")
    func sideBySideSharesTheWidth() {
        let layout = LiveWalkLayout(size: CGSize(width: 1000, height: 980))
        let pane = (1000 - LiveWalkLayout.spacing) / 2 / LiveWalkLayout.referenceSize.width
        #expect(layout.scale == pane)
    }
}
