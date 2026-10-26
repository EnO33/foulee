import Foundation

/// A good moment to ask for an App Store review (issue #580): never at launch,
/// never after an error, only right after something worth celebrating.
nonisolated public enum ReviewMoment: Equatable, Sendable {
    /// The streak just beat a record of at least `minimumRecordDays` days.
    case streakRecord
    /// The streak just reached `weekStreakDays` days.
    case weekStreak
    /// The `milestoneOutings`-th outing was just finished.
    case outingsMilestone

    /// A record shorter than this is no feat to beat: going from 1 to 2 days
    /// is how every streak starts.
    static let minimumRecordDays = 2
    static let weekStreakDays = 7
    static let milestoneOutings = 10

    /// The moment reached going from `old` to `new`, if any.
    ///
    /// Only a one-step change counts: a streak or a count that jumps is a read
    /// catching up (HealthKit access granted, a refused read answering again),
    /// not the user doing something today.
    public static func reached(from old: ReviewProgress, to new: ReviewProgress) -> ReviewMoment? {
        if new.streak == old.streak + 1 {
            if old.bestStreak >= minimumRecordDays, new.streak > old.bestStreak { return .streakRecord }
            if new.streak == weekStreakDays { return .weekStreak }
        }
        if new.outings == old.outings + 1, new.outings == milestoneOutings { return .outingsMilestone }
        return nil
    }
}

/// What the review moments are measured on.
nonisolated public struct ReviewProgress: Equatable, Sendable {
    /// Active days in a row whose goal was met, through today.
    public var streak: Int
    /// The longest such run, today's included.
    public var bestStreak: Int
    /// Outings finished in the app.
    public var outings: Int

    public init(streak: Int, bestStreak: Int, outings: Int) {
        self.streak = streak
        self.bestStreak = bestStreak
        self.outings = outings
    }
}

/// When the app last asked, and whether it may ask again.
nonisolated public struct ReviewPromptHistory: Equatable, Sendable {
    /// The app has never reached the home before this process.
    public var isFirstLaunch: Bool
    /// The marketing version (`CFBundleShortVersionString`) last asked from.
    public var lastRequestVersion: String?
    public var lastRequestDate: Date?

    /// Apple shows the prompt at most three times a year anyway; asking more
    /// often only spends those three on worse moments.
    public static let minimumInterval: TimeInterval = 120 * 24 * 60 * 60

    public init(isFirstLaunch: Bool, lastRequestVersion: String? = nil, lastRequestDate: Date? = nil) {
        self.isFirstLaunch = isFirstLaunch
        self.lastRequestVersion = lastRequestVersion
        self.lastRequestDate = lastRequestDate
    }

    /// Never on the first launch, never twice for one version, and at most
    /// once every `minimumInterval`.
    public func allowsRequest(version: String, now: Date) -> Bool {
        guard !isFirstLaunch, lastRequestVersion != version else { return false }
        guard let lastRequestDate else { return true }
        return now.timeIntervalSince(lastRequestDate) >= Self.minimumInterval
    }

    public mutating func recordRequest(version: String, now: Date) {
        lastRequestVersion = version
        lastRequestDate = now
    }
}
