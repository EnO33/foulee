import SwiftUI

/// The wrist's outing, presented over the home (issue #279).
///
/// In a modifier of its own because `TodayScreen` is at SwiftLint's file limit,
/// and because these two behaviours are one idea: the phone shows the outing it
/// did not start, and steps aside for it if it had started one.
extension View {
    func mirroredWalkCover(
        store: MirroredSessionStore,
        isPresented: Binding<Bool>,
        isWalking: Binding<Bool>,
        scheme: ColorScheme
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            MirroredWalkScreen(store: store, onDismiss: { isPresented.wrappedValue = false })
                .preferredColorScheme(scheme)
        }
        // A mirror arriving *during* a phone walk: the watch wins. Closing the
        // cover is the whole of it — `ActiveWalkScreen` owns the walk's store
        // and already calls `reset()` on disappear, which cancels the sensors
        // and ends the Live Activity. A `discard()` of our own would duplicate
        // an exit path that is already correct.
        .onChange(of: store.isMirroring) { _, mirroring in
            guard mirroring else {
                // The wrist finished — by « Arrêter la séance » here (issue
                // #282) or on the watch itself. Either way the screen has
                // nothing left to show, and it closes on the *outcome* rather
                // than on the tap: `stop()` still has to fold and save, and can
                // fail. Dismissing on the tap would claim a result the phone
                // cannot know.
                isPresented.wrappedValue = false
                return
            }
            guard isWalking.wrappedValue else { return }
            isWalking.wrappedValue = false
            isPresented.wrappedValue = true
        }
    }
}
