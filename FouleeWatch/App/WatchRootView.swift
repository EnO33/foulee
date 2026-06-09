import SwiftUI

/// Owns the workout store and routes to home / active / ended screens.
struct WatchRootView: View {
    @State private var store = WatchWorkoutStore()
    @State private var todayStore = WatchTodayStore()

    var body: some View {
        Group {
            switch store.state {
            case .idle:
                WatchTodayView(store: todayStore, errorMessage: store.lastError) {
                    Task { await store.start() }
                }
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
