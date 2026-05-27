import SwiftUI

/// Owns the workout store and routes to idle / active / ended screens.
struct WatchRootView: View {
    @State private var store = WatchWorkoutStore()

    var body: some View {
        Group {
            switch store.state {
            case .idle:
                WatchIdleView(store: store)
            case .active(let metrics):
                WatchActiveWalkView(metrics: metrics) {
                    Task { await store.stop() }
                }
            case .ended(let metrics):
                WatchFinishedView(metrics: metrics) {
                    store.reset()
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.state)
    }
}
