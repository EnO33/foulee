import SwiftUI
import WidgetKit

@main
struct FouleeWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreakComplication()
        WatchStatComplication()
    }
}
