import CoreGraphics
import Testing
@testable import Foulee

/// The backdrop's blobs fill the window they are given (#663): a phone keeps
/// the backdrop it always had, the inner screen stretches it to its edges.
@Suite("Wallpaper")
struct WallpaperTests {
    @Test("A phone keeps the blobs where they were drawn", arguments: [
        CGSize(width: 375, height: 667),
        CGSize(width: 393, height: 852),
        CGSize(width: 440, height: 956)
    ])
    func phoneKeepsItsBackdrop(size: CGSize) {
        #expect(Wallpaper.spread(in: size) == CGSize(width: 1, height: 1))
    }

    @Test("A wider window spreads the blobs across its width only")
    func widerWindowSpreadsSideways() {
        let spread = Wallpaper.spread(in: CGSize(width: 1100, height: 900))
        #expect(spread.width == 1100 / Wallpaper.referenceSize.width)
        #expect(spread.height == 1)
    }
}
