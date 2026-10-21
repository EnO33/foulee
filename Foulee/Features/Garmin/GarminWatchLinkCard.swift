import Dependencies
import SwiftUI

/// Links the Foulée watch app to the iPhone (ADR 0009): the Connect IQ SDK
/// only talks to devices the user picked in Garmin Connect. Garmin Connect
/// answers through the `foulee-ciq://` URL, handled by `FouleeApp`.
struct GarminWatchLinkCard: View {
    @Dependency(\.garminConnectIQ) private var garminConnectIQ

    @State private var devices: [GarminDevice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Relier l'app Foulée de la montre")
                .font(FouleeFont.headline)
            Text("""
                Pour suivre une séance de la montre sur l'iPhone, noter « J'ai bu » depuis la montre \
                et y voir ta série, choisis ta montre dans Garmin Connect.
                """)
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
            if !devices.isEmpty {
                Label(devices.map(\.friendlyName).formatted(), systemImage: "checkmark.circle.fill")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(FouleeColor.success)
            }
            PrimaryButton(
                title: devices.isEmpty ? "Choisir ma montre" : "Changer de montre",
                systemIcon: FouleeIcon.watch,
                action: garminConnectIQ.presentDeviceSelection
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fouleeGlass(cornerRadius: 22)
        .onAppear(perform: refresh)
        // After `FouleeApp` stored the answer: a task runs once every handler
        // of this URL has.
        .onOpenURL { _ in Task { refresh() } }
    }

    private func refresh() {
        devices = garminConnectIQ.knownDevices()
    }
}

#Preview { GarminWatchLinkCard().padding() }
