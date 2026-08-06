import Dependencies
import SwiftUI
import UserNotifications

/// Fourth onboarding screen — Santé / Watch / Notifications / Position.
/// Tapping each row triggers the underlying iOS permission sheet.
/// Notifications + Position run real authorization here; HealthKit is
/// deferred to `TodayStore.bootstrap()` since it requires a HKHealthStore.
struct OnboardingPermissionsView: View {
    var preferences: UserPreferences
    var onFinish: () -> Void

    @Dependency(\.healthKit) private var healthKit
    @Dependency(\.location) private var location

    @State private var healthGranted = false
    @State private var locationGranted = false
    @State private var notificationsGranted = false
    @State private var isShowingGarminGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Five glass rows plus the heading no longer fit a fixed stack —
            // they clipped the title and the button at larger Dynamic Type
            // sizes. Scroll the rows, keep the CTA pinned to the bottom.
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    OnboardingStepIndicator(step: .permissions)
                        .frame(maxWidth: .infinity)
                    heading
                    rows
                }
                .padding(.horizontal, 24)
                .padding(.top, 70)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
        }
        .sheet(isPresented: $isShowingGarminGuide) {
            GarminSetupSheet { isShowingGarminGuide = false }
        }
    }

    private var rows: some View {
        VStack(spacing: 12) {
            permissionRows
            // A Garmin user has nothing to toggle here — their setup happens
            // in Garmin Connect, so the guide is offered right where the watch
            // question comes up.
            GarminSetupLink { isShowingGarminGuide = true }
                .padding(14)
                .fouleeGlass(cornerRadius: 18)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 20) {
            hint
            PrimaryButton(title: "Terminer l'installation", systemIcon: nil, action: onFinish)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connectons\nSanté & ta montre")
                .scaledSystemFont(size: 30, weight: .bold)
                .lineSpacing(2)
            Text("Foulée lit uniquement tes pas et tes séances.\nAucune donnée n'est partagée.")
                .font(FouleeFont.body)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionRows: some View {
        VStack(spacing: 12) {
            PermissionRow(
                systemIcon: FouleeIcon.heart,
                color: FouleeColor.danger,
                title: "Santé (HealthKit)",
                subtitle: "Pas, distance, calories",
                isOn: $healthGranted,
                request: requestHealth
            )
            PermissionRow(
                systemIcon: FouleeIcon.watch,
                color: Color(hex: 0x0A84FF),
                title: "Montre",
                subtitle: "Apple Watch ou Garmin",
                isOn: .constant(true),
                request: { true }
            )
            PermissionRow(
                systemIcon: FouleeIcon.bell,
                color: FouleeColor.warning,
                title: "Notifications",
                subtitle: "Rappel juste avant ta fenêtre",
                isOn: $notificationsGranted,
                request: requestNotifications
            )
            PermissionRow(
                systemIcon: FouleeIcon.location,
                color: FouleeColor.success,
                title: "Position",
                subtitle: "Optionnel · pour la météo locale",
                isOn: $locationGranted,
                request: requestLocation
            )
        }
    }

    private var hint: some View {
        HStack(spacing: 8) {
            Image(systemName: FouleeIcon.sparkle)
                .scaledSystemFont(size: 14)
                .foregroundStyle(.secondary)
            Text("Tu peux changer ces autorisations dans Réglages à tout moment.")
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func requestHealth() async -> Bool {
        let granted = (try? await healthKit.requestAuthorization()) ?? false
        return granted
    }

    private func requestLocation() async -> Bool {
        await location.requestWhenInUse()
    }

    private func requestNotifications() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        // Persist the outcome: the toggle used to live only in local @State,
        // so the choice made here never reached the reminder scheduler.
        if granted { preferences.notificationsEnabled = true }
        return granted
    }
}

private struct PermissionRow: View {
    var systemIcon: String
    var color: Color
    var title: String
    var subtitle: String
    @Binding var isOn: Bool
    var request: () async -> Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: systemIcon)
                        .font(.system(size: 22))
                        .foregroundStyle(color)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FouleeFont.headline)
                Text(subtitle).font(FouleeFont.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(FouleeColor.success)
                .onChange(of: isOn) { _, new in
                    guard new else { return }
                    Task {
                        let granted = await request()
                        if !granted { isOn = false }
                    }
                }
        }
        .padding(14)
        .fouleeGlass(cornerRadius: 18)
    }
}
