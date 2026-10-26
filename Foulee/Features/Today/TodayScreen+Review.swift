import FouleeKit
import StoreKit
import SwiftUI
import UIKit

/// The App Store review request (issue #580), asked from the home the moment
/// it celebrates: a streak record, seven days in a row, the tenth outing.
///
/// In a modifier of its own because `TodayScreen` is at SwiftLint's file limit.
extension View {
    /// `progress` is `nil` until the home has loaded, so the first snapshot is
    /// never mistaken for a moment. `isAllowed` is false while the home shows
    /// an error: the request must come from the moment, not land on a problem.
    func reviewRequest(store: ReviewPromptStore, at progress: ReviewProgress?, isAllowed: Bool) -> some View {
        modifier(ReviewRequest(store: store, progress: progress, isAllowed: isAllowed))
    }
}

private struct ReviewRequest: ViewModifier {
    let store: ReviewPromptStore
    let progress: ReviewProgress?
    let isAllowed: Bool

    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content.onChange(of: progress) { old, new in
            guard isAllowed, Self.isHomeFrontmost, let old, let new,
                  store.shouldRequest(from: old, to: new) else { return }
            requestReview()
        }
    }

    /// Nothing is presented over the home — no sheet, no session cover —
    /// whoever presented it. A cover on its way out counts as gone: the walk's
    /// own refresh lands while it closes.
    private static var isHomeFrontmost: Bool {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        guard let presented = root?.presentedViewController else { return root != nil }
        return presented.isBeingDismissed
    }
}

extension ReviewProgress {
    init(_ snapshot: TodaySnapshot, outings: Int) {
        self.init(streak: snapshot.streak, bestStreak: snapshot.bestStreak, outings: outings)
    }
}
