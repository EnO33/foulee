import Foundation
import Testing
@testable import FouleeKit

/// One message and one action for each thing Foulée cannot do (issue #611).
@Suite("Degraded state")
struct DegradedStateTests {
    @Test("Each state points to the place that fixes it")
    func remedies() {
        #expect(DegradedState.healthUnreadable.remedy == .openHealth)
        #expect(DegradedState.waterWriteDenied.remedy == .openHealth)
        #expect(DegradedState.noData.remedy == .openHealth)
        #expect(DegradedState.locationDenied.remedy == .openSettings)
        #expect(DegradedState.motionDenied.remedy == .openSettings)
        #expect(DegradedState.weatherUnavailable.remedy == nil)
    }

    @Test("Each state has a title and a message, each remedy a label")
    func texts() {
        for state in DegradedState.allCases {
            #expect(!state.title.isEmpty)
            #expect(!state.message.isEmpty)
        }
        #expect(DegradedState.Remedy.openSettings.title == "Ouvrir les réglages")
        #expect(DegradedState.Remedy.openHealth.title == "Ouvrir Santé")
    }

    @Test("Only refused permissions are listed, most limiting first")
    func permissions() {
        #expect(DegradedState.permissions(location: .granted, motion: .granted, waterWriteDenied: false).isEmpty)
        #expect(DegradedState.permissions(location: .denied, motion: .denied, waterWriteDenied: true)
            == [.locationDenied, .motionDenied, .waterWriteDenied])
        // Not asked yet is not refused: iOS still shows its own prompt.
        #expect(DegradedState.permissions(location: .notDetermined, motion: .unknown, waterWriteDenied: false).isEmpty)
    }

    @Test("Left out, water is not refused")
    func outing() {
        #expect(DegradedState.permissions(location: .denied, motion: .granted) == [.locationDenied])
        #expect(DegradedState.permissions(location: .granted, motion: .denied) == [.motionDenied])
    }

    @Test("A refused location outranks a silent WeatherKit")
    func weather() {
        #expect(DegradedState.weather(location: .denied) == .locationDenied)
        #expect(DegradedState.weather(location: .granted) == .weatherUnavailable)
    }

    @Test("The messages read in English on an English screen")
    func english() {
        let american = Locale(identifier: "en_US")
        #expect(kitText("Localisation refusée", locale: american) == "Location denied")
        #expect(kitText("Ouvrir les réglages", locale: american) == "Open Settings")
    }
}
