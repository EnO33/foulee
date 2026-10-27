import FouleeKit
import SwiftUI
import WatchKit

/// Each kilometre, announced (issue #382): a tap on the wrist, and the
/// kilometre that just ended laid over the whole session.
///
/// Over every page, because a kilometre is crossed whatever page is on screen —
/// most often with the wrist down, which is what the haptic is for. It leaves
/// on its own after `shownFor`, or at a touch: the wearer glances, and the
/// session comes back without a gesture.
struct WatchKilometreAlertModifier: ViewModifier {
    let splits: [WalkSplit]

    /// Long enough to raise the wrist after the tap and read four figures.
    static let shownFor: Duration = .seconds(10)

    @State private var shown: WalkSplit?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let shown {
                    WatchKilometreAlert(split: shown)
                        .onTapGesture { self.shown = nil }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeOut(duration: 0.25), value: shown)
            // Only a kilometre crossed while the screen is up: `onChange` skips
            // the value the session opens with. Several crossed in one late
            // reading show only the last — the one just run.
            .onChange(of: splits.last) { _, latest in
                guard let latest else { return }
                shown = latest
                WKInterfaceDevice.current().play(.notification)
            }
            .task(id: shown?.kilometre) {
                guard shown != nil else { return }
                try? await Task.sleep(for: Self.shownFor)
                if !Task.isCancelled { shown = nil }
            }
    }
}

extension View {
    /// Announce each new kilometre of `splits` (issue #382).
    func kilometreAlert(_ splits: [WalkSplit]) -> some View {
        modifier(WatchKilometreAlertModifier(splits: splits))
    }
}

/// The kilometre just run: its time first, then how it was run.
struct WatchKilometreAlert: View {
    let split: WalkSplit

    var body: some View {
        VStack(spacing: 4) {
            Text("Kilomètre \(split.kilometre)")
                .font(.headline)
                .foregroundStyle(MetricPalette.distance)
            Text(split.duration.walkClockText)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let pace = split.paceText {
                Text(pace)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            // Steps and cadence on one line, in the steps' colour: both count
            // the same thing, and the cadence already carries its unit.
            Text(rhythmText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MetricPalette.steps)
                .monospacedDigit()
                .padding(.top, 2)
            if !split.activityText.isEmpty {
                Label(split.activityText, systemImage: split.activity?.icon ?? "figure.mixed.cardio")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(split.activity?.tint ?? .secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Touche pour revenir à la séance")
    }

    /// « 812 pas · 160 pas/min ».
    private var rhythmText: String {
        ["\(split.steps.groupedText()) pas", split.cadenceText].compactMap { $0 }.joined(separator: " · ")
    }

    private var accessibilityText: String {
        [
            "Kilomètre \(split.kilometre) en \(split.duration.walkClockText)",
            split.activityText,
            "\(split.steps.groupedText()) pas",
            split.cadenceText,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}
