import SwiftUI

/// The device probe's screen (issue #248) — « Diagnostic », reachable from the
/// home screen and from a session in flight.
///
/// Read outdoors, mid-outing, at whatever text size the owner walks around
/// with, so the layout follows the two rules #241 taught this project the hard
/// way: everything that can grow **scrolls**, and the only way out is **pinned
/// outside** the scrolled region — exactly as `WatchActivityChoiceView` pins
/// « Annuler ». There is no navigation bar behind this screen to swipe back to.
///
/// Each row stacks its label above its value instead of putting them on one
/// line: at the largest Dynamic Type sizes on a 40 mm watch a two-column row
/// truncates the value, and a truncated diagnostic reading is worse than none.
///
/// The rows are rebuilt every second by the `TimelineView` so « Écoute depuis »
/// and « Dernière reçue » keep counting — that is what makes « rien ne bouge »
/// distinguishable from « le flux est mort » while standing still. The
/// `TimelineView` sits *inside* the `ScrollView` so the per-second rebuild
/// cannot disturb the scroll offset.
struct WatchMotionProbeView: View {
    let probe: WatchMotionProbe
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Diagnostic mouvement")
                            .font(.headline)
                            .minimumScaleFactor(0.7)
                        ForEach(MotionProbeReport.rows(for: probe.state, now: context.date)) { row in
                            MotionProbeRowView(row: row)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            WatchMotionProbeCloseButton(close: onClose)
                .padding(.horizontal, 2)
                .padding(.top, 4)
        }
        .task {
            probe.start()
            // Cancelled when the screen goes away, which is also what stops
            // the polling below.
            await probe.observeCapabilities()
        }
        .onDisappear { probe.stop() }
    }
}

/// One reading. Internal rather than private so a test can walk it.
struct MotionProbeRowView: View {
    let row: MotionProbeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(row.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(row.value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
        }
        // Wraps rather than truncates — a clipped value is a wrong reading.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Colour is a hint, never the message: every row's text says what it
    /// means on its own, so the screen survives a glance in the sun and a
    /// colour-blind reader.
    private var tint: AnyShapeStyle {
        switch row.tone {
        case .plain: AnyShapeStyle(.primary)
        case .on: AnyShapeStyle(.green)
        case .off: AnyShapeStyle(.secondary)
        case .alert: AnyShapeStyle(.orange)
        }
    }
}

/// The one way into the probe, placed on the home screen and on a session in
/// flight (issue #248).
///
/// A named view for the reason `WatchActivityChoiceButton` is one: a button
/// built inline is out of reach of `ViewTreeProbe`, and « the diagnostic is
/// reachable » is the acceptance criterion this whole issue rests on — a probe
/// nobody can open answers nothing. Deliberately plain and labelled, not a long
/// press or a hidden gesture: the owner has to find it on a wrist, outdoors,
/// mid-outing.
struct WatchDiagnosticButton: View {
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            Label("Diagnostic", systemImage: "waveform.path")
                .font(.caption.weight(.semibold))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

/// The way back to the app. Named, like `WatchActivityCancelButton`, because
/// wired to nothing it strands the owner on a screen that replaced their home
/// — mid-session, outdoors.
struct WatchMotionProbeCloseButton: View {
    var close: () -> Void

    var body: some View {
        Button(action: close) {
            Text("Fermer")
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

#Preview {
    WatchMotionProbeView(probe: WatchMotionProbe(), onClose: {})
}
