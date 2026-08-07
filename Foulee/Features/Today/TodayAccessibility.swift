import Foundation

/// Stable handles on the home screen's cards, for automation only.
///
/// The App Store capture target (issue #235) drives the real app from another
/// process and has to tap the streak card, the weather card and two metric
/// cards. None of them can be found by label: a card is read out by its
/// contents ("SÉRIE 34 jours Record : 41 jours"), which is exactly the text
/// the captures exist to change. The cards that *do* hold a stable label — the
/// hydration button, « Voir le résumé », the profile button — are left alone.
///
/// An identifier is inert: VoiceOver never speaks it, it is not localized, and
/// it changes nothing on screen.
///
/// Spelled here rather than at each call site so the capture target, which
/// cannot import app code, has one list to mirror.
enum TodayAccessibility {
    static let streakCard = "today.card.streak"
    static let weatherCard = "today.card.weather"

    static func metricCard(_ metric: WalkMetric) -> String {
        "today.card.metric.\(metric.rawValue)"
    }
}
