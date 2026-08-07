import Dependencies
import Foundation
import Testing
@testable import Foulee

/// A store screenshot is read closely, so the seeded numbers have to *be*
/// consistent, not look consistent. Nothing here re-implements the app's
/// arithmetic: the suite drives the real stores over `ScreenshotDoubles` and
/// checks that what they publish is what the marketing copy will claim.
///
/// It is also the regression guard on the seed: change a pinned duration and
/// the streak, the week bars or the résumé stop agreeing, and this fails.
@Suite("Screenshot seed")
struct ScreenshotSeedTests {
    private static let suiteName = "screenshot-seed-tests"

    @MainActor
    private static func seededPreferences() -> UserPreferences {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = UserPreferences(defaults: defaults)
        ScreenshotSeed.seed(preferences, hasCompletedOnboarding: true)
        return preferences
    }

    // MARK: - The streak really is what the history says

    /// The 34 days on the hero card and the 41-day record are not written into
    /// the seed — they are derived from the seeded history by the app's own
    /// calculator. This is the assertion that keeps the two in step.
    @Test("The advertised streak and record are what the seeded history computes")
    func streakMatchesHistory() {
        let history = ScreenshotSeed.dailyMinutes(daysBack: StreakCalculator.historyWindowDays)
        let current = StreakCalculator.current(
            history: history,
            goalMinutes: ScreenshotSeed.minutesGoal,
            activeDays: Weekday.workWeek,
            today: ScreenshotSeed.instant
        )
        let best = StreakCalculator.best(
            history: history,
            goalMinutes: ScreenshotSeed.minutesGoal,
            activeWeekdays: Weekday.workWeek.calendarWeekdays
        )
        #expect(current == ScreenshotSeed.currentStreak)
        #expect(best == ScreenshotSeed.bestStreak)
        // The record has to beat the running streak, or the "Record" line on
        // the card reads as a bug.
        #expect(best > current)
    }

    // MARK: - Today

    @Test("The seeded Today screen agrees with itself")
    @MainActor
    func todayScreenIsConsistent() async {
        let preferences = Self.seededPreferences()
        await withDependencies {
            $0.date = .constant(ScreenshotSeed.instant)
            $0.healthKit = ScreenshotDoubles.healthKit
            $0.weather = ScreenshotDoubles.weather
            $0.location = ScreenshotDoubles.location
            $0.notifications = ScreenshotDoubles.notifications
            $0.garminConnectIQ = ScreenshotDoubles.garminConnectIQ
        } operation: {
            let store = TodayStore()
            store.apply(preferences: preferences)
            await store.refresh()
            let snapshot = store.snapshot
            #expect(snapshot?.steps == ScreenshotSeed.todaySteps)
            #expect(snapshot?.stepsGoal == ScreenshotSeed.stepsGoal)
            #expect(snapshot?.minutes == 42)
            #expect(snapshot?.minutesGoal == ScreenshotSeed.minutesGoal)
            #expect(snapshot?.calories == 386)
            #expect(snapshot?.streak == ScreenshotSeed.currentStreak)
            #expect(snapshot?.bestStreak == ScreenshotSeed.bestStreak)
            // The ring closes and the hero says "Sortie terminée" — the state
            // the capture is composed around.
            #expect(snapshot?.hasWalkedToday == true)
            #expect(snapshot?.isRestDay == false)
            #expect(snapshot?.weather.temperatureCelsius == 21)
            // Mon → Thu of the seeded week, then three days that haven't
            // happened yet. Same numbers as the résumé's session durations.
            #expect(snapshot?.weekMinutes == [38, 33, 36, 42, 0, 0, 0])
            // No banner, no Garmin hint: both would sit above the hero card.
            #expect(store.lastError == nil)
            #expect(store.showsGarminSyncHint == false)
        }
    }

    /// The header prints `snapshot.date`, so it has to be the pinned day —
    /// this is what stops the capture from changing because today is Tuesday.
    @Test("The header date is the pinned day, not the real one")
    @MainActor
    func headerDateIsPinned() async {
        let preferences = Self.seededPreferences()
        await withDependencies {
            $0.date = .constant(ScreenshotSeed.instant)
            $0.healthKit = ScreenshotDoubles.healthKit
            $0.weather = ScreenshotDoubles.weather
            $0.location = ScreenshotDoubles.location
            $0.notifications = ScreenshotDoubles.notifications
        } operation: {
            let store = TodayStore()
            store.apply(preferences: preferences)
            await store.refresh()
            let shown = store.snapshot?.date ?? .distantPast
            #expect(Calendar.current.isDate(shown, inSameDayAs: ScreenshotSeed.instant))
        }
    }

    // MARK: - The other screens read the same history

    @Test("The calendar sheet answers the same streak as the home card")
    @MainActor
    func calendarSheetAgreesWithHome() async {
        await withDependencies {
            $0.date = .constant(ScreenshotSeed.instant)
            $0.healthKit = ScreenshotDoubles.healthKit
        } operation: {
            let store = StreakCalendarStore(
                goalMinutes: ScreenshotSeed.minutesGoal,
                goalSteps: ScreenshotSeed.stepsGoal,
                activeDays: Weekday.workWeek
            )
            await store.load()
            #expect(store.currentStreak == ScreenshotSeed.currentStreak)
            #expect(store.bestStreak == ScreenshotSeed.bestStreak)
            #expect(store.months.count == StreakCalendarStore.monthsBack)
            #expect(store.lastError == nil)
        }
    }

    @Test("The daily charts end on today's counters")
    func chartsEndOnToday() {
        let minutes = ScreenshotSeed.metricSeries(.minutes, daysBack: 7)
        let steps = ScreenshotSeed.metricSeries(.steps, daysBack: 7)
        #expect(minutes.last?.value == 42)
        #expect(steps.last?.value == Double(ScreenshotSeed.todaySteps))
        #expect(minutes.count == 7)
        // Oldest → newest, as every consumer of the series assumes.
        #expect(minutes.first?.date ?? .distantFuture < (minutes.last?.date ?? .distantPast))
    }

    /// The "Auj." range sums its hourly buckets into the headline total, so the
    /// curve has to add back up to the number the home screen shows.
    @Test("The hourly curve sums to the day's totals")
    func hourlyCurveSumsToTheDay() {
        let steps = ScreenshotSeed.hourlyToday(.steps).reduce(0) { $0 + $1.value }
        let minutes = ScreenshotSeed.hourlyToday(.minutes).reduce(0) { $0 + $1.value }
        #expect(steps == Double(ScreenshotSeed.todaySteps))
        #expect(minutes == 42)
        // Only the hours that have happened at 14:35.
        #expect(ScreenshotSeed.hourlyToday(.steps).count == 15)
    }

    @Test("The résumé lists a session on every day the week bars fill")
    func resumeMatchesTheWeekBars() throws {
        let workouts = ScreenshotSeed.recentWorkouts(daysBack: 7)
        // Mon → Thu recorded, the weekend empty: the placeholder row the sheet
        // shows on a rest day is part of the capture.
        #expect(workouts.count == 5)
        let today = try #require(workouts.first)
        #expect(today.durationSeconds == TimeInterval(42 * 60))
        #expect(today.sourceName == "Foulée")
        let calendar = Calendar.current
        for workout in workouts {
            let minutes = Int(workout.durationSeconds / 60)
            let offset = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: workout.startedAt),
                to: ScreenshotSeed.today
            ).day ?? -1
            #expect(minutes == ScreenshotSeed.minutes(offset: offset))
            // A session is never longer than the exercise minutes credited
            // that day, and it always ends before the pinned instant.
            #expect(workout.endedAt <= ScreenshotSeed.instant)
        }
    }

    /// The session-in-progress boards show one walk on two devices, and the two
    /// numbers under the flame differ — 99 kcal on the phone, 108 on the wrist.
    /// That is deliberate (the phone estimates from steps, the watch measures),
    /// but it is the kind of deliberate that rots into a typo nobody can date.
    /// So both are pinned here, each against the rule it comes from, and the
    /// wrist's is asserted to be the *larger* of the two — the direction the
    /// product claims.
    @Test("Both session boards' calories come from a rule, not from a guess")
    func sessionCaloriesAreDerivedOnBothDevices() {
        // Phone: steps × the activity's per-step estimate (no energy sensor).
        let phone = WalkSession(
            startedAt: ScreenshotSeed.instant,
            steps: ScreenshotSeed.sessionSteps,
            distanceMeters: ScreenshotSeed.sessionDistanceMeters,
            activity: .walking
        )
        #expect(phone.estimatedCalories == 99)

        // Watch: the seeded day's own marginal rate over the session's minutes.
        // The rate is recovered from `calories(minutes:)` itself rather than
        // restated, so this fails if the two ever stop being the same rule.
        // Over 100 minutes so the function's rounding can't blur it.
        let marginalPerMinute = Double(
            ScreenshotSeed.calories(minutes: 100) - ScreenshotSeed.calories(minutes: 0)
        ) / 100
        #expect(marginalPerMinute == 5.85)
        #expect(
            ScreenshotSeed.sessionCalories
                == Int((ScreenshotSeed.sessionElapsed / 60 * marginalPerMinute).rounded())
        )
        #expect(ScreenshotSeed.sessionCalories == 108)
        #expect(ScreenshotSeed.sessionCalories > phone.estimatedCalories)
    }
}
