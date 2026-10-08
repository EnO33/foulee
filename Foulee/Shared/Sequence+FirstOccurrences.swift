extension Sequence where Element: Equatable {
    /// Each element once, where it first appears: walk, run, walk, run →
    /// walk, run.
    ///
    /// Linear search rather than a `Set`, on purpose: the sequences this
    /// serves are the sports of one outing — a handful of elements, of a type
    /// that needs no `Hashable` to be named.
    var firstOccurrences: [Element] {
        reduce(into: []) { seen, element in
            if !seen.contains(element) { seen.append(element) }
        }
    }
}
