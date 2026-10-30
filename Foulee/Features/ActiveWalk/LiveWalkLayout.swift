import CoreGraphics

/// How the outing in progress lays itself out in the space it is given
/// (#662): the figures and the map side by side once the space is wider than
/// tall — the iPhone Duo's inner screen held open — and the ring grown with
/// the room it has.
///
/// Decided on the size, never on the device or the orientation (#659): a
/// phone is locked in portrait and as wide as `referenceSize` at most, so it
/// keeps the layout it always had.
nonisolated struct LiveWalkLayout: Equatable {
    /// The widest phone and the height its walk screen has to share: the
    /// space the fixed sizes were drawn for.
    static let referenceSize = CGSize(width: 440, height: 860)
    /// Past this the ring's figures, fixed in size, float in empty space.
    static let maxScale: CGFloat = 1.4
    /// Between the figures and the map.
    static let spacing: CGFloat = 24

    let isSideBySide: Bool
    /// What the ring and the figure inside it are multiplied by, from 1.
    let scale: CGFloat

    init(size: CGSize) {
        isSideBySide = size.width > size.height
        // The figures get half the width beside the map, and never more than
        // the reading column (#661).
        let paneWidth = isSideBySide ? (size.width - Self.spacing) / 2 : size.width
        let pane = CGSize(width: min(paneWidth, ScreenColumn.maxWidth), height: size.height)
        let fit = min(pane.width / Self.referenceSize.width, pane.height / Self.referenceSize.height)
        scale = min(max(fit, 1), Self.maxScale)
    }
}
