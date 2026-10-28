import AppIntents
import SwiftUI
import WidgetKit

/// « Commencer une sortie » in Control Center, on the Lock Screen and on the
/// iPhone's Action button (issue #606). The sport is picked when the control
/// is added; left empty, the user's own mode decides, as on the home button.
struct StartOutingControl: ControlWidget {
    static let kind = "com.eno33.foulee.startOutingControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, intent: StartOutingControlConfiguration.self) { configuration in
            ControlWidgetButton(action: StartOutingIntent(activity: configuration.activity)) {
                Label(configuration.activity?.controlTitle ?? "Commencer une sortie",
                      systemImage: configuration.activity?.symbolName ?? "figure.walk")
            }
        }
        .displayName("Commencer une sortie")
        .description("Ouvre Foulée et démarre une sortie.")
    }
}

struct StartOutingControlConfiguration: ControlConfigurationIntent {
    static var title: LocalizedStringResource { "Commencer une sortie" }

    @Parameter(title: "Sport")
    var activity: OutingActivity?
}

/// « J'ai bu un verre » in Control Center and on the Action button: logs the
/// glass from the widget process, like the hydration widget's button, without
/// opening the app.
struct LogWaterControl: ControlWidget {
    static let kind = "com.eno33.foulee.logWaterControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogWaterIntent()) {
                Label("J'ai bu un verre", systemImage: "drop.fill")
            }
        }
        .displayName("J'ai bu un verre")
        .description("Enregistre un verre d'eau dans Santé.")
    }
}

private extension OutingActivity {
    var controlTitle: LocalizedStringKey {
        switch self {
        case .walking: "Commencer une marche"
        case .running: "Commencer une course"
        case .automatic: "Commencer une sortie"
        }
    }

    var symbolName: String {
        switch self {
        case .walking, .automatic: "figure.walk"
        case .running: "figure.run"
        }
    }
}
