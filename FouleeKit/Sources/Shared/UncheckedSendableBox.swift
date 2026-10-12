/// Carries a non-Sendable value across a concurrency boundary — into a `Task`,
/// a continuation, or an actor hop. Use only when the value is genuinely
/// accessed safely: typically a system completion handler invoked exactly once
/// (WidgetKit timelines, HKObserverQuery, notification responses).
nonisolated public struct UncheckedSendableBox<Value>: @unchecked Sendable {
    public let value: Value
    public init(_ value: Value) { self.value = value }
}
