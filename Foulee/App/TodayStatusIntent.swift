import AppIntents
import FouleeKit
import SwiftUI

/// « Où j'en suis aujourd'hui » for Siri, Raccourcis and Spotlight (issue #605).
/// Answers without opening Foulée, from the same figures as the widgets:
/// the app's snapshot with HealthKit's live reads folded in, or the snapshot
/// alone for a read HealthKit refuses.
struct TodayStatusIntent: AppIntent {
    static var title: LocalizedStringResource { "Où j'en suis aujourd'hui" }
    // periphery:ignore - read by the AppIntents runtime, never from code.
    static var description: IntentDescription { "Ta série, tes minutes et tes pas du jour." }
    // periphery:ignore - read by the AppIntents runtime, never from code.
    /// Health figures: Siri does not read them to whoever holds a locked phone.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snapshot = await WidgetLiveMetrics.freshSnapshot()
        return .result(
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: spokenTodayStatusText(snapshot))),
            view: TodayStatusSnippet(snapshot: snapshot)
        )
    }
}

/// The answer's card: the streak, then the day's two figures, drawn like the
/// home's tiles.
private struct TodayStatusSnippet: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        FigureRow(spacing: 12) {
            StatBlock(
                systemIcon: FouleeIcon.flame,
                label: "Série",
                value: "\(snapshot.streak)",
                sub: snapshot.streak == 1 ? String(localized: "jour") : String(localized: "jours"),
                spokenValue: spokenStreakText(days: snapshot.streak),
                tint: ReadablePalette.orangeText
            )
            tile(.minutes, snapshot.minutes, goal: snapshot.minutesGoal)
            tile(.steps, snapshot.steps, goal: snapshot.stepsGoal)
        }
        .padding()
    }

    private func tile(_ metric: WalkMetric, _ value: Int, goal: Int) -> some View {
        StatBlock(
            systemIcon: metric.icon,
            label: .verbatim(metric.title),
            value: value.groupedText(),
            sub: "/ \(goal.groupedText())",
            spokenValue: metric.spokenText(Double(value), goal: Double(goal)),
            tint: metric.labelTint
        )
    }
}
