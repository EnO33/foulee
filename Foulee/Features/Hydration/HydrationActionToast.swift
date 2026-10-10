import Combine
import SwiftUI

/// Floating confirmation shown when the app was opened by a hydration
/// notification action — "Verre enregistré (+250 mL)" or "Rappel dans 15 min".
/// Without it, nothing tells the user their tap counted and they log a second
/// glass by hand. A "failed" stamp (denied authorization or failed save in the
/// background action) surfaces as an error toast for the same reason. Consumes
/// the stamp the action handler wrote whenever the scene comes alive (or
/// immediately, via `actionHandled`, if already visible).
///
/// A logged glass comes with « Annuler » (issue #354), kept on screen a little
/// longer so there is time to reach it.
struct HydrationActionToast: View {
    /// Called when a logged glass was confirmed — lets the home re-read Health
    /// so the hydration card reflects the new intake right away.
    var onLogged: () -> Void = {}
    /// Takes a glass back; `false` when Santé refused.
    var onUndo: (HydrationNotification.Undo) async -> Bool = { _ in false }

    @Environment(\.scenePhase) private var scenePhase
    @State private var message: String?
    @State private var isError = false
    @State private var undo: HydrationNotification.Undo?
    @State private var hideTask: Task<Void, Never>?

    /// Stamps older than this are stale (app reopened long after the tap).
    private static let maxStampAge: TimeInterval = 25

    var body: some View {
        ZStack(alignment: .top) {
            if let message {
                HStack(spacing: 12) {
                    Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    if let undo {
                        Button("Annuler") { take(back: undo) }
                            .font(FouleeFont.footnote.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.22), in: Capsule())
                            .buttonStyle(.pressable)
                            .accessibilityLabel("Annuler ce verre")
                    }
                }
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(tint, in: Capsule())
                .shadow(color: tint.opacity(0.35), radius: 12, x: 0, y: 6)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sensoryFeedback(isError ? .error : .success, trigger: message)
        .onAppear(perform: consumeStamp)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consumeStamp() }
        }
        .onReceive(NotificationCenter.default.publisher(for: HydrationNotification.actionHandled)) { _ in
            consumeStamp()
        }
    }

    private func consumeStamp() {
        let defaults = UserDefaults.standard
        guard let stamp = defaults.dictionary(forKey: HydrationNotification.confirmKey),
              let at = stamp["at"] as? TimeInterval,
              let kind = stamp["kind"] as? String else { return }
        defaults.removeObject(forKey: HydrationNotification.confirmKey)
        guard Date().timeIntervalSince1970 - at < Self.maxStampAge else { return }

        let amount = stamp["amount"] as? Int ?? 0
        switch kind {
        case "drank":
            onLogged()
            show("Verre enregistré (+\(amount) mL)", undo: HydrationNotification.Undo(stamp: stamp))
        case "failed":
            show("Verre non enregistré — vérifie Santé", asError: true)
        default:
            show("Rappel dans \(amount) min")
        }
    }

    private var tint: Color {
        isError ? .orange : .teal
    }

    /// Delete the glass, then say how it went in the same toast.
    private func take(back glass: HydrationNotification.Undo) {
        undo = nil
        hideTask?.cancel()
        Task {
            if await onUndo(glass) {
                show("Verre annulé (−\(glass.milliliters) mL)")
            } else {
                show("Impossible d'annuler ce verre — vérifie Santé", asError: true)
            }
        }
    }

    private func show(_ text: String, asError: Bool = false, undo: HydrationNotification.Undo? = nil) {
        isError = asError
        withAnimation(.spring(duration: 0.35)) {
            message = text
            self.undo = undo
        }
        // Cancellable so a rapid second toast isn't hidden by the first's timer.
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(undo == nil ? 2.8 : 5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                message = nil
                self.undo = nil
            }
        }
    }
}
