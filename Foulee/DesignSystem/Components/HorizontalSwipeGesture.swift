import SwiftUI
import UIKit

/// A swipe sideways that never holds up the scroll view it sits in (issue
/// #444).
///
/// A SwiftUI `DragGesture` on a scroll view's content competes with the
/// scroll's own pan: once the system's gesture gate times out, the scroll view
/// stops scrolling altogether. This pan refuses to begin unless the finger
/// sets off clearly sideways, so every vertical drag stays the scroll view's,
/// and it recognizes alongside it rather than instead of it.
struct HorizontalSwipeGesture: UIGestureRecognizerRepresentable {
    enum Direction {
        /// Finger moving right to left.
        case left
        /// Finger moving left to right.
        case right
    }

    /// How far the finger must travel sideways for the swipe to count.
    var threshold: CGFloat = 60
    var onSwipe: (Direction) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        let dx = recognizer.translation(in: recognizer.view).x
        guard abs(dx) > threshold else { return }
        onSwipe(dx < 0 ? .left : .right)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Only a pan clearly sideways from its very start.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 2
        }

        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
