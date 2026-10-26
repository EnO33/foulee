import Dependencies
import FouleeKit
import Foundation
import Observation

/// Decides, on the home, whether a just-reached moment earns a review request
/// (issue #580), and remembers the outings and the requests it is counted on.
/// The rules themselves are `ReviewMoment` and `ReviewPromptHistory`.
@Observable
final class ReviewPromptStore {
    /// The screenshot mode's throwaway suite in a capture, so a capture leaves
    /// the real install's counters alone.
    static let shared = ReviewPromptStore(defaults: FouleeApp.preferencesDefaults)

    /// Outings finished in the app since it was installed.
    private(set) var outings: Int {
        didSet { defaults.set(outings, forKey: Keys.outings) }
    }

    @ObservationIgnored private var history: ReviewPromptHistory
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let version: String

    @ObservationIgnored
    @Dependency(\.date) private var date

    init(defaults: UserDefaults = .standard, version: String = AppVersion.marketing) {
        self.defaults = defaults
        self.version = version
        self.outings = defaults.integer(forKey: Keys.outings)
        self.history = ReviewPromptHistory(
            isFirstLaunch: !defaults.bool(forKey: Keys.hasLaunched),
            lastRequestVersion: defaults.string(forKey: Keys.lastRequestVersion),
            lastRequestDate: defaults.object(forKey: Keys.lastRequestDate) as? Date
        )
    }

    /// Once per process, from `FouleeApp`: the next launch is no longer the
    /// first. This one still is, as `history` was read before.
    func recordLaunch() {
        defaults.set(true, forKey: Keys.hasLaunched)
    }

    func recordOuting() {
        outings += 1
    }

    /// Whether to ask now, going from `old` to `new`. Answering yes records
    /// the request: the caller must ask.
    func shouldRequest(from old: ReviewProgress, to new: ReviewProgress) -> Bool {
        let now = date.now
        guard ReviewMoment.reached(from: old, to: new) != nil,
              history.allowsRequest(version: version, now: now) else { return false }
        history.recordRequest(version: version, now: now)
        defaults.set(version, forKey: Keys.lastRequestVersion)
        defaults.set(now, forKey: Keys.lastRequestDate)
        return true
    }

    private enum Keys {
        static let outings = "review.outings"
        static let hasLaunched = "review.hasLaunched"
        static let lastRequestVersion = "review.lastRequestVersion"
        static let lastRequestDate = "review.lastRequestDate"
    }
}
