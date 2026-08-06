import Foundation
import SwiftUI
import Testing
@testable import Foulee

@Suite("Onboarding")
@MainActor
struct OnboardingFlowTests {
    @Test("The flow walks every step in order and stops on the last one")
    func stepsAdvanceInOrder() {
        var visited: [OnboardingStep] = [.welcome]
        // Bounded so a `next` that ever loops fails the assertion below
        // instead of hanging the suite.
        while let current = visited.last, current != current.next, visited.count < 10 {
            visited.append(current.next)
        }

        #expect(visited == [.welcome, .activity, .goal, .permissions])
        // The old clamp was `min(step + 1, 2)`, a literal that had to be
        // remembered whenever a screen was added. The last case now clamps
        // itself, so this stays true for free.
        #expect(OnboardingStep.permissions.next == .permissions)
    }

    @Test("Ranks are contiguous from zero, so the dots line up with the screens")
    func ranksAreContiguous() {
        #expect(OnboardingStep.allCases.count == 4)
        #expect(OnboardingStep.allCases.map(\.rawValue) == Array(0..<4))
    }

    @Test("Every step renders its own screen — one each, and no stand-in")
    func eachStepRendersItsOwnScreen() {
        let (defaults, suiteName) = cleanDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserPreferences(defaults: defaults)

        // A step that renders the wrong screen is invisible from the outside:
        // the `default:` catch-all before #221 showed permissions for every
        // unknown index, and a `switch` can be miswired the same way with the
        // build green. So assert the mapping itself, step by step.
        #expect(rendered(.welcome, preferences) == ["welcome"])
        #expect(rendered(.activity, preferences) == ["activity"])
        #expect(rendered(.goal, preferences) == ["goal"])
        #expect(rendered(.permissions, preferences) == ["permissions"])
    }

    @Test("The last screen's CTA finishes the flow instead of advancing it")
    func theLastScreenFinishes() {
        let (defaults, suiteName) = cleanDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var advanced = false
        var finished = false
        let screen = OnboardingStepScreen(
            step: .permissions,
            preferences: UserPreferences(defaults: defaults),
            advance: { advanced = true },
            finish: { finished = true }
        )

        ViewTreeProbe.first(OnboardingPermissionsView.self, in: screen.body)?.onFinish()

        #expect(finished)
        #expect(advanced == false)
    }

    @Test("Tapping a row puts the choice on disk before the flow completes")
    func tappingARowWritesImmediately() {
        let (defaults, suiteName) = cleanDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserPreferences(defaults: defaults)
        let screen = OnboardingActivityView(preferences: preferences, onContinue: {})
        // Marche is the default, so it is the row that starts out ticked.
        #expect(row(.walking, screen)?.isSelected == true)
        #expect(row(.running, screen)?.isSelected == false)

        // The row's own action, built the way the screen builds it.
        row(.running, screen)?.select()

        // Committed on tap rather than held in local state until the end: an
        // onboarding abandoned midway still leaves the answer behind, and it
        // lands well before `hasCompletedOnboarding`.
        #expect(defaults.string(forKey: "preferences.activityMode") == "running")
        #expect(defaults.bool(forKey: "preferences.hasCompletedOnboarding") == false)
        #expect(row(.running, screen)?.isSelected == true)
        #expect(row(.walking, screen)?.isSelected == false)
    }

    @Test("Continuer commits the untouched default, so the key is never left blank")
    func continueCommitsTheUntouchedDefault() {
        let (defaults, suiteName) = cleanDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserPreferences(defaults: defaults)
        // A blank key is what an install predating the question looks like
        // (#219), so accepting marche has to be told apart from never asking.
        #expect(defaults.string(forKey: "preferences.activityMode") == nil)
        var continued = false
        let screen = OnboardingActivityView(preferences: preferences, onContinue: { continued = true })

        // The CTA the screen actually wires up, not a re-implementation of it.
        let cta = ViewTreeProbe.first(PrimaryButton.self, in: screen.body)
        #expect(cta?.title == "Continuer")
        cta?.action()

        #expect(continued)
        #expect(defaults.string(forKey: "preferences.activityMode") == "walking")
    }

    @Test("A fresh install runs the flow, and finishing it closes the gate for good")
    func finishingTheFlowClosesTheGate() {
        let (defaults, suiteName) = cleanDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunch = RootView(defaults: defaults).body
        #expect(ViewTreeProbe.contains(HomeView.self, in: firstLaunch) == false)
        let flow = ViewTreeProbe.first(OnboardingFlow.self, in: firstLaunch)
        #expect(flow != nil)

        // Followed the whole way down rather than calling `flow.onFinish`
        // straight: the flow forwarding its own callback to the last screen is
        // a link that can be cut on its own.
        ViewTreeProbe.first(OnboardingStepScreen.self, in: flow!.body)?.finish()

        #expect(defaults.bool(forKey: "preferences.hasCompletedOnboarding") == true)
        let relaunch = RootView(defaults: defaults).body
        #expect(ViewTreeProbe.contains(HomeView.self, in: relaunch))
        #expect(ViewTreeProbe.contains(OnboardingFlow.self, in: relaunch) == false)
    }

    @Test("An install that finished the 3-step flow doesn't replay onboarding")
    func completedOnboardingSurvivesTheNewStep() {
        // Exactly what a pre-#221 install left on disk: the completion flag,
        // and no activity key at all. Keys are spelled out rather than read
        // from `UserPreferences` — renaming one is the very way this
        // regression would ship, and the literal is what would catch it.
        let (defaults, suiteName) = cleanDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "preferences.hasCompletedOnboarding")
        defaults.set(30, forKey: "preferences.minutesGoal")

        // The gate as `RootView` really applies it: the update opens on the
        // home screen, not on a fourth onboarding screen.
        let launch = RootView(defaults: defaults).body
        #expect(ViewTreeProbe.contains(HomeView.self, in: launch))
        #expect(ViewTreeProbe.contains(OnboardingFlow.self, in: launch) == false)

        let preferences = UserPreferences(defaults: defaults)
        #expect(preferences.minutesGoal == 30)
        // And the step they never saw leaves them on the walking behaviour
        // they already had (#219).
        #expect(preferences.activityMode == .walking)
    }

    /// The activity screen's row for one mode, rebuilt from the live screen on
    /// every call — a row holds the selection it was built with, so re-reading
    /// it after a tap is what shows the tick moving.
    private func row(_ mode: ActivityMode, _ screen: OnboardingActivityView) -> ActivityChoiceRow? {
        ViewTreeProbe.forEachRow(
            mode, of: ForEach<[ActivityMode], ActivityMode.ID, ActivityChoiceRow>.self, in: screen.body
        )
    }

    /// Which onboarding screens a step builds — names rather than types so a
    /// step rendering two screens, or the wrong one, reads plainly in the
    /// failure message.
    private func rendered(_ step: OnboardingStep, _ preferences: UserPreferences) -> [String] {
        let body = OnboardingStepScreen(
            step: step, preferences: preferences, advance: {}, finish: {}
        ).body
        var found: [String] = []
        if ViewTreeProbe.contains(OnboardingWelcomeView.self, in: body) { found.append("welcome") }
        if ViewTreeProbe.contains(OnboardingActivityView.self, in: body) { found.append("activity") }
        if ViewTreeProbe.contains(OnboardingGoalView.self, in: body) { found.append("goal") }
        if ViewTreeProbe.contains(OnboardingPermissionsView.self, in: body) { found.append("permissions") }
        return found
    }

    private func cleanDefaults() -> (UserDefaults, String) {
        let suiteName = "foulee-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
