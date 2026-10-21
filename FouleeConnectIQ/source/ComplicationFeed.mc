import Toybox.Complications;
import Toybox.Lang;

//! The streak, published as a complication for watch faces and Face It (ADR
//! 0009, phase C), from the open app only: the `Toybox.Complications`
//! documentation names no background context, unlike `Communications`. The
//! streak changes once a day and is published on every opening and every
//! state from the phone, which keeps it close enough.
//!
//! No active-minutes complication: published from the open app only, it would
//! go stale between two openings, and the watch's own intensity-minutes
//! complication is always current.
(:typecheck([disableBackgroundCheck, disableGlanceCheck]))
module ComplicationFeed {

    //! `resources/complications/complications.xml`. Never changes: watch faces
    //! subscribe to it.
    const STREAK = 0;

    //! Publishing is a courtesy to watch faces: it never takes the app down.
    function publish() as Void {
        if (!(Toybox has :Complications)) {
            return;
        }
        var streak = streakOf(PhoneSync.load());
        if (streak == null) {
            return;
        }
        try {
            Complications.updateComplication(STREAK, {:value => streak});
        } catch (ex) {
            // The watch refused it; the next opening tries again.
        }
    }

    //! The streak the phone sent, or null before the first state: no streak
    //! is published rather than a streak of zero.
    function streakOf(sync as Dictionary<String, Number or Boolean or String>?) as Number? {
        return sync != null ? sync["streak"] as Number : null;
    }
}
