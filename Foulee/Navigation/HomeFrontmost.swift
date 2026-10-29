import UIKit

extension UIApplication {
    /// Nothing is presented over the home — no sheet, no session cover —
    /// whoever presented it. A cover on its way out counts as gone: the walk's
    /// own refresh lands while it closes. What the review request (issue #580)
    /// and the « Nouveautés » (issue #621) wait for.
    var isHomeFrontmost: Bool {
        let root = connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        guard let presented = root?.presentedViewController else { return root != nil }
        return presented.isBeingDismissed
    }
}
