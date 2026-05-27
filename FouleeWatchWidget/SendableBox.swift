import Foundation

/// Tiny escape hatch for ferrying non-Sendable values across a Task
/// boundary when we know it's safe by inspection. Used to capture
/// WidgetKit's completion handlers (typed without `@Sendable`) inside
/// `Task { … }` under Swift 6 strict concurrency.
struct SendableBox<Value>: @unchecked Sendable {
    let value: Value
}
