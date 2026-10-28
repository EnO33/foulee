import SwiftUI
import WatchKit

/// The music, without leaving the session (issue #383).
///
/// `NowPlayingView` is the system's own « À l'écoute » — the controls the
/// Exercice app shows beside its workout. It drives whichever app is playing,
/// on the watch through Bluetooth headphones or on the phone, with the crown as
/// the volume. Rebuilding those controls would mean a media integration per
/// app; the system view already is one, and it knows when nothing is playing.
struct WatchSessionMusicPage: View {
    var body: some View {
        NowPlayingView()
            // A named container, so VoiceOver and the capture run both find
            // the page without depending on the system view's own labels.
            .sessionPage("Musique")
    }
}
