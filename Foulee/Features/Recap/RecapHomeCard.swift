import SwiftUI

/// The way into the recaps from the home (issue #344): last week, last month.
struct RecapHomeCard: View {
    var onOpen: (RecapPeriod.Kind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tes récaps", systemImage: "chart.bar.doc.horizontal")
                .font(FouleeFont.headline)
            HStack(spacing: 10) {
                button("Semaine dernière", kind: .week)
                button("Mois dernier", kind: .month)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .fouleeGlass(cornerRadius: 22)
    }

    private func button(_ title: String, kind: RecapPeriod.Kind) -> some View {
        Button { onOpen(kind) } label: {
            Text(title)
                .font(FouleeFont.callout.weight(.semibold))
                .foregroundStyle(FouleeColor.accentMid)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(FouleeColor.accentMid.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}

/// Presents the recap the router asks for (issue #344): from the home card,
/// or from a notification — whether its tap launched the app or found the home
/// already on screen. One way in for both, and a modifier so the home's own
/// body stays short.
struct RecapPresentation: ViewModifier {
    let goalMinutes: Int
    let activeDays: Set<Weekday>
    let colorScheme: ColorScheme?
    var router: RecapRouter = .shared

    @State private var selection: RecapPeriod.Kind?

    func body(content: Content) -> some View {
        content
            .sheet(item: $selection) { kind in
                RecapScreen(kind: kind, goalMinutes: goalMinutes, activeDays: activeDays) {
                    selection = nil
                }
                .preferredColorScheme(colorScheme)
            }
            .onAppear(perform: openPending)
            .onChange(of: router.pending) { _, _ in openPending() }
    }

    private func openPending() {
        guard let kind = router.take() else { return }
        selection = kind
    }
}
