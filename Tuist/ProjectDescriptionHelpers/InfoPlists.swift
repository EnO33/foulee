import ProjectDescription

// The Info.plist dictionaries of the two app targets. Out of `Project.swift`
// so the manifest stays readable — and under SwiftLint's file length — as the
// usage strings keep accumulating their reasons (issue #312).

public let bundleIdBase = "com.eno33.foulee"

// URL scheme Garmin Connect Mobile calls back after the device-selection
// flow. Kept in sync by hand with `GarminConnectIQConfiguration.returnURLScheme`
// (Foulee/Connectivity/GarminConnectIQClient.swift) — a manifest can't import
// app code, and a mismatch silently breaks the authorization round-trip.
public let garminReturnURLScheme = "foulee-ciq"

private let garminBluetoothUsage =
    "Foulée se connecte en Bluetooth à ta montre Garmin pour récupérer ta journée d'activité."

// Extracted from the target literal: inline, the dictionary got large enough
// that the manifest stopped type-checking in reasonable time.
public let fouleeAppInfoPlist: [String: Plist.Value] = [
    "CFBundleDisplayName": "Foulée",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    // foulee://hydration — widget deep link to the hydration card.
    // foulee-ciq:// is the return scheme Garmin Connect Mobile calls back with
    // the device-selection response (issue #187); it has to be distinctive
    // enough not to collide with another app on the device.
    "CFBundleURLTypes": [
        [
            "CFBundleURLName": "com.eno33.foulee",
            "CFBundleURLSchemes": ["foulee"]
        ],
        [
            "CFBundleURLName": "com.eno33.foulee.connectiq",
            "CFBundleURLSchemes": [.string(garminReturnURLScheme)]
        ]
    ],
    // The Connect IQ SDK probes this scheme to tell whether Garmin Connect
    // Mobile is installed; without the declaration the check always answers
    // "missing" and the device-selection flow can't start.
    "LSApplicationQueriesSchemes": ["gcm-ciq"],
    // Background app refresh keeps the widget snapshot moving between
    // HealthKit background deliveries. `bluetooth-central` is the "Uses
    // Bluetooth LE accessories" mode — paired with the SDK's state-restoration
    // identifier it lets iOS relaunch the app when the Garmin watch has data.
    "BGTaskSchedulerPermittedIdentifiers": ["com.eno33.foulee.refresh"],
    "UIBackgroundModes": ["fetch", "bluetooth-central"],
    // Required by App Store review for any CoreBluetooth use. The SDK guide
    // still names the legacy peripheral key; iOS 13+ reads the "Always" one,
    // so declare both.
    "NSBluetoothAlwaysUsageDescription": .string(garminBluetoothUsage),
    "NSBluetoothPeripheralUsageDescription": .string(garminBluetoothUsage),
    "UILaunchScreen": [:],
    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
    // Activity-neutral, and no time of day (#222): these four alerts fire from
    // the onboarding permissions step, i.e. two taps after the user may have
    // answered "Course". "Séance" stays only where the thing really is an
    // HKWorkout record.
    "NSHealthShareUsageDescription": .string(
        "Foulée lit tes pas, ta distance, tes minutes d'exercice, tes calories actives, l'eau que tu as bue, "
            + "ainsi que tes séances, leur fréquence cardiaque et leur parcours, pour afficher ta journée."
    ),
    "NSHealthUpdateUsageDescription":
        "Foulée enregistre tes sorties comme séances dans Santé, ainsi que l'eau que tu bois.",
    // Le podomètre, et depuis #246 la reconnaissance d'activité : à la fin
    // d'une sortie « les deux », l'app relit l'historique de mouvement de la
    // séance pour savoir si tu as marché ou couru. Même registre que les
    // quatre autres alertes (#222) : tutoiement, « sortie », aucun sport nommé.
    "NSMotionUsageDescription":
        "Foulée compte tes pas en direct pendant ta sortie, et reconnaît si tu as marché ou couru.",
    "NSLocationWhenInUseUsageDescription":
        "Foulée utilise ta position pour afficher la météo à ton endroit.",
    "NSSupportsLiveActivities": true,
    // Only standard HTTPS/system crypto — declare export-compliance exemption
    // so TestFlight builds skip the manual encryption question on every upload.
    "ITSAppUsesNonExemptEncryption": false
]

public let fouleeWatchInfoPlist: [String: Plist.Value] = [
    "CFBundleDisplayName": "Foulée",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "WKApplication": true,
    "WKWatchOnly": false,
    "WKCompanionAppBundleIdentifier": .string(bundleIdBase),
    // What lets an `HKWorkoutSession` keep measuring once the
    // wrist drops and the screen goes dark. Apple documents it as
    // required for workout sessions, and it was **missing since
    // the watch app shipped** (issue #273) — no `WKBackgroundModes`
    // anywhere in the repository.
    //
    // The outing of 11/08 on v1.43 worked anyway, so watchOS is
    // evidently more forgiving than the documentation, or the
    // screen never stayed off long enough to find out. Declaring it
    // costs a line and removes the question from every wrist test
    // that follows.
    "WKBackgroundModes": ["workout-processing"],
    // Same registre as the iPhone target's four (#222): system
    // alerts can't vary with the activity preference, so they name
    // no activity. "Séance" stays only where the thing really is
    // an HKWorkout record.
    "NSHealthShareUsageDescription": .string(
        "Foulée lit tes pas, ta distance, tes minutes d'exercice, tes calories actives, l'eau que tu as bue, "
            + "ainsi que tes séances et leur fréquence cardiaque, "
            + "pour afficher ta journée au poignet."
    ),
    "NSHealthUpdateUsageDescription": .string(
        "Foulée enregistre tes sorties comme séances dans Santé, avec les pas, la distance, les calories et "
            + "la fréquence cardiaque mesurés au poignet, ainsi que l'eau que tu bois."
    ),
    // CoreMotion, for the automatic walk/run detection of issue
    // #249. It arrived with the device probe of issue #248 and
    // stayed when issue #252 removed it: the probe was measuring
    // the very capability the shipped feature now uses.
    //
    // Apple's documentation does not list watchOS for this key.
    // Declaring it is strictly safer than betting: if it is
    // required and absent, the failure mode is a crash the first
    // time the activity stream opens — on a wrist, outdoors,
    // mid-outing, which is the one place a crash costs a whole
    // trip.
    //
    // Same registre as the four alerts above (#222): tutoiement, the
    // app's « sortie », and no activity named — a system alert can't
    // vary with the mode, and this one is shown before anything is
    // known about what the wearer is doing.
    "NSMotionUsageDescription": .string(
        "Foulée lit les mouvements détectés au poignet pour reconnaître ton activité pendant ta sortie."
    ),
    // The « Plan » page (issue #312). Asked when an outing starts,
    // never before. Same registre as the alerts above. No
    // `location` background mode: the running `HKWorkoutSession`
    // keeps the app alive, and `allowsBackgroundLocationUpdates`
    // is deliberately left off.
    "NSLocationWhenInUseUsageDescription": .string(
        "Foulée utilise ta position pendant ta sortie pour tracer ton parcours sur le plan."
    )
]
