import Foundation
import SwiftUI

/// Finds a view inside an already-built SwiftUI tree.
///
/// A `body` is a plain struct holding its children, so `Mirror` can answer
/// "which screen did this branch build?" and "what closure did this container
/// wire up?" — the only way to assert on a `@ViewBuilder` `switch` or on a
/// callback passed down a hierarchy, short of a UI test. #221 shipped with
/// both of those uncovered: the step → screen mapping and the onboarding gate
/// could each be rewired with the whole suite still green.
///
/// It reads the tree SwiftUI *would* render and never renders it: no layout,
/// no `onAppear`, no `@State` updates. Anything a container stores as a
/// closure — `ForEach`'s rows, most notably — is absent from the tree and has
/// to be built by calling that closure (see `forEachRow`).
enum ViewTreeProbe {
    /// The first value of type `T` in `value`, itself included.
    ///
    /// Depth-capped rather than unbounded: SwiftUI trees hold environment
    /// boxes and closures whose mirrors go a long way down. The cap is roomy
    /// because nesting adds up fast — the activity rows sit ~15 levels in,
    /// under a `ScrollView` and three paddings.
    static func first<T>(_ type: T.Type, in value: Any, depth: Int = 24) -> T? {
        if let match = value as? T { return match }
        guard depth > 0 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let match = first(type, in: child.value, depth: depth - 1) { return match }
        }
        return nil
    }

    /// Whether a value of type `T` appears anywhere in `value`.
    static func contains<T>(_ type: T.Type, in value: Any) -> Bool {
        first(type, in: value) != nil
    }

    /// The row a `ForEach` in `value` would build for `element`.
    ///
    /// The rows themselves are never in the tree — `ForEach` keeps `data` and
    /// a `(Element) -> Row` closure and calls it during layout. Calling that
    /// closure here builds one row exactly as the screen would, tap action
    /// included, which is what makes a row's behaviour assertable at all.
    static func forEachRow<Element, ID: Hashable, Row>(
        _ element: Element,
        of forEach: ForEach<[Element], ID, Row>.Type,
        in value: Any
    ) -> Row? {
        guard let rows = first(forEach, in: value) else { return nil }
        let build = Mirror(reflecting: rows).children.first { $0.label == "content" }?.value
        return (build as? (Element) -> Row)?(element)
    }
}
