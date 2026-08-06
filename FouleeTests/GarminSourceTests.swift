import Dependencies
import Foundation
import Testing
@testable import Foulee

@Suite("Garmin source classification")
struct GarminSourceClassificationTests {
    @Test("The Garmin Connect app itself is Garmin")
    func garminConnectApp() {
        #expect(GarminSource.isGarmin(
            sourceName: "Garmin Connect", bundleIdentifier: "com.garmin.connect.mobile"
        ))
    }

    @Test("A watch-named source is Garmin even without the brand in the name")
    func watchNamedSources() {
        // Garmin Connect attributes samples to the device: the name is the
        // model, the brand only shows up in the bundle id (or not at all).
        #expect(GarminSource.isGarmin(sourceName: "Forerunner 965", bundleIdentifier: ""))
        #expect(GarminSource.isGarmin(sourceName: "fēnix 8", bundleIdentifier: ""))
        #expect(GarminSource.isGarmin(sourceName: "vívoactive 5", bundleIdentifier: ""))
        #expect(GarminSource.isGarmin(sourceName: "Instinct 2X", bundleIdentifier: ""))
    }

    @Test("The bundle identifier alone is enough")
    func bundleIdentifierOnly() {
        #expect(GarminSource.isGarmin(sourceName: "Montre de Matthieu", bundleIdentifier: "com.garmin.connect"))
    }

    @Test("Unrelated sources are not Garmin")
    func unrelatedSources() {
        #expect(!GarminSource.isGarmin(sourceName: "Foulée", bundleIdentifier: "com.eno33.foulee"))
        #expect(!GarminSource.isGarmin(sourceName: "Strava", bundleIdentifier: "com.strava.stravaride"))
        #expect(!GarminSource.isGarmin(
            sourceName: "Apple Watch de Matthieu", bundleIdentifier: "com.apple.health.A1B2"
        ))
        #expect(!GarminSource.isGarmin(sourceName: "iPhone de Matthieu", bundleIdentifier: "com.apple.health.C3D4"))
        #expect(!GarminSource.isGarmin(sourceName: "", bundleIdentifier: ""))
    }

    @Test("Device families match whole words only")
    func wholeWordMatching() {
        // "Venus" must not pass for a "Venu", "Marquis" for a "MARQ".
        #expect(!GarminSource.isGarmin(sourceName: "Venus Fitness", bundleIdentifier: "com.venus.fitness"))
        #expect(!GarminSource.isGarmin(sourceName: "Marquis Tracker", bundleIdentifier: "com.marquis.tracker"))
    }

    @Test("An Apple-written source is never Garmin, whatever the user named it")
    func appleSourcesShortCircuit() {
        // Health source names are user-chosen device names: someone can call
        // their iPhone "Venu" or their Watch "Instinct". Apple writes those,
        // so the device-family guess must not apply to them.
        #expect(!GarminSource.isGarmin(sourceName: "Venu", bundleIdentifier: "com.apple.health.A1B2"))
        #expect(!GarminSource.isGarmin(sourceName: "Instinct", bundleIdentifier: "com.apple.Health"))
        #expect(!GarminSource.isGarmin(sourceName: "Descent de Lily", bundleIdentifier: "com.apple.health.C3D4"))
    }

    @Test("A first name isn't a watch model")
    func commonFirstNamesAreNotDevices() {
        // "Lily" is a Garmin family *and* a common first name — the name loses.
        #expect(!GarminSource.isGarmin(sourceName: "iPhone de Lily", bundleIdentifier: "com.acme.tracker"))
        #expect(!GarminSource.isGarmin(sourceName: "Lily", bundleIdentifier: ""))
    }
}

@Suite("Garmin freshness hint")
struct GarminFreshnessTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    /// 2024-05-27 00:00 UTC — stable anchor, same as ActiveMinutesTests.
    private var startOfDay: Date { Date(timeIntervalSince1970: 1_716_768_000) }

    private func at(hour: Double) -> Date {
        startOfDay.addingTimeInterval(hour * 3_600)
    }

    private func garminOnly(latest: Date?) -> GarminStatus {
        GarminStatus(hasGarminSource: true, hasAppleWatchData: false, latestGarminSample: latest)
    }

    private func needsHint(_ status: GarminStatus, at hour: Double) -> Bool {
        GarminFreshness.needsSyncHint(status: status, now: at(hour: hour), calendar: calendar)
    }

    @Test("Nothing detected: no hint")
    func nothingDetected() {
        #expect(!needsHint(GarminStatus(), at: 14))
    }

    @Test("A gap during the day means Garmin Connect hasn't pushed")
    func staleDuringDaytime() {
        #expect(needsHint(garminOnly(latest: at(hour: 8)), at: 14))
    }

    @Test("A recent Garmin sample keeps the hint away")
    func freshDataNoHint() {
        #expect(!needsHint(garminOnly(latest: at(hour: 13)), at: 14))
    }

    @Test("Nothing since midnight is the case the hint is for")
    func noSampleToday() {
        #expect(needsHint(garminOnly(latest: nil), at: 14))
    }

    @Test("Yesterday's sample is floored at midnight — same verdict as no sample")
    func yesterdaySampleFloorsAtMidnight() {
        let yesterdayEvening = at(hour: -2)
        for hour in [11.0, 14.0, 20.0] {
            #expect(needsHint(garminOnly(latest: yesterdayEvening), at: hour)
                == needsHint(garminOnly(latest: nil), at: hour))
        }
    }

    @Test("An Apple Watch in the mix silences the hint")
    func appleWatchPresent() {
        let hybrid = GarminStatus(hasGarminSource: true, hasAppleWatchData: true, latestGarminSample: nil)
        #expect(!needsHint(hybrid, at: 14))
    }

    @Test("No hint outside daytime hours")
    func outsideDaytime() {
        #expect(!needsHint(garminOnly(latest: nil), at: 7))
        #expect(!needsHint(garminOnly(latest: nil), at: 22))
        // 11:00 is the first hour the hint may show.
        #expect(needsHint(garminOnly(latest: nil), at: 11))
        #expect(!needsHint(garminOnly(latest: nil), at: 10.5))
    }

    @Test("A sample dated in the future can't trigger the hint")
    func futureSample() {
        #expect(!needsHint(garminOnly(latest: at(hour: 20)), at: 14))
    }

    @Test("The gap must reach the threshold")
    func thresholdBoundary() {
        let now = at(hour: 14)
        let justUnder = now.addingTimeInterval(-GarminFreshness.staleAfter + 60)
        let justOver = now.addingTimeInterval(-GarminFreshness.staleAfter)
        #expect(!needsHint(garminOnly(latest: justUnder), at: 14))
        #expect(needsHint(garminOnly(latest: justOver), at: 14))
    }
}

@Suite("TodayStore Garmin hint wiring")
struct TodayStoreGarminHintTests {
    /// 14:00 local today — inside the hint's daytime window in any timezone.
    private var earlyAfternoon: Date {
        Calendar.current.startOfDay(for: .now).addingTimeInterval(14 * 3_600)
    }

    private func healthKitStub(status: GarminStatus) -> HealthKitClient {
        HealthKitClient(
            requestAuthorization: { true },
            todayMetrics: { .zero },
            saveWorkout: { _ in },
            dailyMinutes: { _ in [] },
            recentWorkouts: { _ in [] },
            workoutDetail: { summary in
                WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
            },
            garminStatus: { status }
        )
    }

    @Test("A stale Garmin-only setup raises the hint")
    @MainActor
    func garminOnlyRaisesHint() async {
        let status = GarminStatus(hasGarminSource: true, hasAppleWatchData: false, latestGarminSample: nil)
        await withDependencies {
            $0.date = .constant(earlyAfternoon)
            $0.healthKit = healthKitStub(status: status)
        } operation: {
            let store = TodayStore()
            await store.refresh()
            #expect(store.showsGarminSyncHint)
        }
    }

    @Test("No detection, no hint — the default state stays silent")
    @MainActor
    func noDetectionKeepsHintOff() async {
        await withDependencies {
            $0.date = .constant(earlyAfternoon)
            $0.healthKit = healthKitStub(status: GarminStatus())
        } operation: {
            let store = TodayStore()
            await store.refresh()
            #expect(!store.showsGarminSyncHint)
        }
    }
}
