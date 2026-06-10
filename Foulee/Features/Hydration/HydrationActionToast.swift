import Combine
import SwiftUI

/// Floating confirmation shown when the app was opened by a hydration
/// notification action — "Verre enregistré (+250 mL)" or "Rappel dans 15 min".
/// Without it, nothing tells the user their tap counted and they log a second
/// glass by hand. Consumes the stamp the action handler wrote whenever the
/// scene comes alive (or immediately, via `actionHandled`, if already visible).
struct HydrationActionToast: View {
    /// Called when a logged glass was confirmed — lets the home re-read Health
    /// so the hydration card reflects the new intake right away.
    var onLogged: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    @State private var message: String?

    /// Stamps older than this are stale (app reopened long after the tap).
    private static let maxStampAge: TimeInterval = 25

    var body: some View {
        ZStack(alignment: .top) {
            if let message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.teal, in: Capsule())
                    .shadow(color: Color.teal.opacity(0.35), radius: 12, x: 0, y: 6)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: message)
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
        if kind == "drank" {
            onLogged()
            show("Verre enregistré (+\(amount) mL)")
        } else {
            show("Rappel dans \(amount) min")
        }
    }

    private func show(_ text: String) {
        withAnimation(.spring(duration: 0.35)) { message = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation(.easeOut(duration: 0.3)) { message = nil }
        }
    }
}
