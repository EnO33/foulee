import Foundation
import ProjectDescription

let bundleIdBase = "com.eno33.foulee"
let deploymentTargets: DeploymentTargets = .iOS("26.0")

// URL scheme Garmin Connect Mobile calls back after the device-selection
// flow. Kept in sync by hand with `GarminConnectIQConfiguration.returnURLScheme`
// (Foulee/Connectivity/GarminConnectIQClient.swift) — a manifest can't import
// app code, and a mismatch silently breaks the authorization round-trip.
let garminReturnURLScheme = "foulee-ciq"

private let garminBluetoothUsage =
    "Foulée se connecte en Bluetooth à ta montre Garmin pour récupérer ta journée d'activité."

// Extracted from the target literal: inline, the dictionary got large enough
// that the manifest stopped type-checking in reasonable time.
let fouleeAppInfoPlist: [String: Plist.Value] = [
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
            + "ainsi que tes séances et leur fréquence cardiaque, pour afficher ta journée."
    ),
    "NSHealthUpdateUsageDescription":
        "Foulée enregistre tes sorties comme séances dans Santé, ainsi que l'eau que tu bois.",
    "NSMotionUsageDescription":
        "Foulée compte tes pas en direct pendant ta sortie.",
    "NSLocationWhenInUseUsageDescription":
        "Foulée utilise ta position pour afficher la météo à ton endroit.",
    "NSSupportsLiveActivities": true,
    // Only standard HTTPS/system crypto — declare export-compliance exemption
    // so TestFlight builds skip the manual encryption question on every upload.
    "ITSAppUsesNonExemptEncryption": false
]

// Per-developer signing — read DEVELOPMENT_TEAM from Local.xcconfig if it
// exists (gitignored). On CI the file is absent and the build targets the
// simulator with no signing, so the default empty value is fine.
let manifestDirectory = (#filePath as NSString).deletingLastPathComponent
let localXcconfigPath = "\(manifestDirectory)/Local.xcconfig"
let hasLocalXcconfig = FileManager.default.fileExists(atPath: localXcconfigPath)

let configurations: [Configuration] = hasLocalXcconfig
    ? [
        .debug(name: "Debug", xcconfig: "Local.xcconfig"),
        .release(name: "Release", xcconfig: "Local.xcconfig")
    ]
    : [
        .debug(name: "Debug"),
        .release(name: "Release")
    ]

let project = Project(
    name: "Foulee",
    organizationName: "EnO33",
    options: .options(
        defaultKnownRegions: ["fr", "en"],
        developmentRegion: "fr"
    ),
    packages: [
        .remote(
            url: "https://github.com/pointfreeco/swift-dependencies",
            requirement: .upToNextMajor(from: "1.4.0")
        ),
        // Garmin Connect IQ companion SDK — a binary xcframework, iOS-only.
        // Linked to the iPhone app target exclusively (issue #187).
        .remote(
            url: "https://github.com/garmin/connectiq-companion-app-sdk-ios",
            requirement: .upToNextMinor(from: "1.8.0")
        )
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.2",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            // Version + build number shared by every target. The release CI
            // overrides these on the xcodebuild command line (version from the
            // git tag, build number from the commit count); locally they stay
            // at the values below. Targets reference them via $(…) in Info.plist.
            "MARKETING_VERSION": "0.1.0",
            "CURRENT_PROJECT_VERSION": "1",
            // String catalog: extract Text("…") into Localizable.xcstrings at
            // build-time and generate type-safe Swift symbols for each key.
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
            "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES"
        ],
        configurations: configurations
    ),
    targets: [
        .target(
            name: "Foulee",
            destinations: [.iPhone],
            product: .app,
            bundleId: bundleIdBase,
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: fouleeAppInfoPlist),
            sources: ["Foulee/**"],
            resources: [
                .glob(pattern: "Foulee/Resources/**", excluding: ["Foulee/Resources/Foulee.entitlements"])
            ],
            entitlements: .file(path: "Foulee/Resources/Foulee.entitlements"),
            dependencies: [
                .package(product: "Dependencies"),
                // iPhone app only — the widget and watch targets must never
                // link the Connect IQ framework (iOS-only binary, and the
                // BLE session belongs to the app process).
                .package(product: "ConnectIQ"),
                .target(name: "FouleeLiveActivity"),
                .target(name: "FouleeWidget"),
                // Embeds the watchOS companion app into the iOS app so it
                // ships in the same App Store submission.
                .target(name: "FouleeWatch")
            ],
            settings: .settings(base: [
                // The Connect IQ framework ships Objective-C categories; without
                // -ObjC the linker drops them and the SDK crashes at runtime on
                // unrecognised selectors (SDK guide, "Add required linker flags").
                "OTHER_LDFLAGS": ["$(inherited)", "-ObjC"]
            ])
        ),
        .target(
            name: "FouleeWidget",
            destinations: [.iPhone],
            product: .appExtension,
            bundleId: "\(bundleIdBase).widget",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Foulée Série",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension"
                ]
            ]),
            sources: [
                "FouleeWidget/**",
                // Pure active-minutes merge shared with the app so widget
                // minutes match the hero ring (issue #181).
                "Foulee/Health/ActiveMinutes.swift",
                "Foulee/Shared/SharedWidgetData.swift",
                "Foulee/Shared/NumberFormatting.swift",
                "Foulee/Shared/UncheckedSendableBox.swift",
                "Foulee/Shared/WidgetRefresh.swift",
                "Foulee/Shared/WidgetTimelineBuilder.swift",
                "Foulee/Shared/WidgetKind.swift",
                "Foulee/Shared/LogWaterIntent.swift",
                // The activity preference and the glyph it maps to, so the
                // widget's figure follows the user's mode like the app's own
                // ring (issue #222). Both Foundation-only — `ActivityMode+Icon`
                // reads `ActivityGlyph`, not `FouleeIcon`, precisely so it can
                // be listed here.
                "Foulee/Preferences/ActivityMode.swift",
                "Foulee/Preferences/ActivityMode+Icon.swift",
                "Foulee/Shared/ActivityGlyph.swift",
                "FouleeWatchWidget/StreakEntry.swift"
            ],
            resources: [
                .glob(
                    pattern: "FouleeWidget/Resources/**",
                    excluding: ["FouleeWidget/Resources/FouleeWidget.entitlements"]
                )
            ],
            entitlements: .file(path: "FouleeWidget/Resources/FouleeWidget.entitlements"),
            dependencies: []
        ),
        .target(
            name: "FouleeLiveActivity",
            destinations: [.iPhone],
            product: .appExtension,
            bundleId: "\(bundleIdBase).liveactivity",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                // Surfaced by Réglages and by Stockage/Batterie next to the
                // app. "Sortie" is the app's user-facing noun for a session
                // (#222); "Marche" named an activity the user may not do.
                "CFBundleDisplayName": "Foulée Sortie",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension"
                ]
            ]),
            sources: [
                "FouleeLiveActivity/**",
                "Foulee/Walk/WalkActivityAttributes.swift",
                "Foulee/Shared/WalkFormatting.swift",
                "Foulee/Shared/NumberFormatting.swift",
                // Only the glyph names, not `ActivityMode`: this extension has
                // no app-group entitlement and no channel to the preference
                // (issue #225). What it needs is the neutral figure, spelled
                // once (issue #222).
                "Foulee/Shared/ActivityGlyph.swift"
            ],
            resources: [
                .glob(
                    pattern: "FouleeLiveActivity/Resources/**",
                    excluding: ["FouleeLiveActivity/Resources/FouleeLiveActivity.entitlements"]
                )
            ],
            entitlements: .file(path: "FouleeLiveActivity/Resources/FouleeLiveActivity.entitlements"),
            dependencies: []
        ),
        .target(
            name: "FouleeWatch",
            destinations: [.appleWatch],
            product: .app,
            bundleId: "\(bundleIdBase).watchkitapp",
            deploymentTargets: .watchOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Foulée",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "WKApplication": true,
                "WKWatchOnly": false,
                "WKCompanionAppBundleIdentifier": .string(bundleIdBase),
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
                )
            ]),
            sources: [
                "FouleeWatch/**",
                "Foulee/Shared/WalkFormatting.swift",
                "Foulee/Shared/NumberFormatting.swift",
                "Foulee/Shared/UncheckedSendableBox.swift",
                "Foulee/Shared/WatchSyncPayload.swift",
                "Foulee/Shared/WatchComplicationKind.swift",
                "Foulee/Shared/WatchComplicationCache.swift",
                // The watch writes its own workouts, so it needs the same
                // activity vocabulary as the phone (issue #223) — and the
                // preference it resolves from, which rides in the sync payload.
                "Foulee/Shared/SessionActivity.swift",
                "Foulee/Shared/SessionActivity+HealthKit.swift",
                "Foulee/Preferences/ActivityMode.swift",
                // « Les deux » makes the watch ask which activity before it
                // records one (issue #224): the intent is the shared decision,
                // and the glyphs are what its two buttons draw — the watch has
                // no DesignSystem, so `SessionActivity.icon` reads these.
                "Foulee/Shared/ActivityStartIntent.swift",
                "Foulee/Shared/ActivityGlyph.swift",
                "Foulee/Notifications/HydrationNotification.swift"
            ],
            resources: [
                .glob(
                    pattern: "FouleeWatch/Resources/**",
                    excluding: ["FouleeWatch/Resources/FouleeWatch.entitlements"]
                )
            ],
            entitlements: .file(path: "FouleeWatch/Resources/FouleeWatch.entitlements"),
            dependencies: [
                .target(name: "FouleeWatchWidget")
            ]
        ),
        .target(
            name: "FouleeWatchWidget",
            destinations: [.appleWatch],
            product: .appExtension,
            bundleId: "\(bundleIdBase).watchkitapp.widget",
            deploymentTargets: .watchOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Foulée Série",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension"
                ]
            ]),
            sources: [
                "FouleeWatchWidget/**",
                "Foulee/Shared/NumberFormatting.swift",
                "Foulee/Shared/UncheckedSendableBox.swift",
                "Foulee/Shared/WidgetRefresh.swift",
                "Foulee/Shared/WidgetTimelineBuilder.swift",
                "Foulee/Shared/WatchSyncPayload.swift",
                // Only because the payload above carries it — no complication
                // renders the activity mode.
                "Foulee/Preferences/ActivityMode.swift",
                "Foulee/Shared/WatchComplicationKind.swift",
                "Foulee/Shared/WatchComplicationCache.swift"
            ],
            resources: [
                .glob(
                    pattern: "FouleeWatchWidget/Resources/**",
                    excluding: ["FouleeWatchWidget/Resources/FouleeWatchWidget.entitlements"]
                )
            ],
            entitlements: .file(path: "FouleeWatchWidget/Resources/FouleeWatchWidget.entitlements"),
            dependencies: []
        ),
        .target(
            name: "FouleeTests",
            destinations: [.iPhone],
            product: .unitTests,
            bundleId: "\(bundleIdBase).tests",
            deploymentTargets: deploymentTargets,
            sources: ["FouleeTests/**"],
            dependencies: [
                .target(name: "Foulee")
            ]
        ),
        // App Store capture target (issue #235). A UI test bundle, not a unit
        // one: it drives the shipped app from another process, launches it with
        // `-FouleeScreenshotMode` and photographs each screen. Deliberately
        // absent from the `Foulee` scheme's test action — CI's "Test (iOS)"
        // step must keep running the unit suite only, not boot a simulator to
        // take pictures on every pull request.
        .target(
            name: "FouleeScreenshots",
            destinations: [.iPhone],
            product: .uiTests,
            bundleId: "\(bundleIdBase).screenshots",
            deploymentTargets: deploymentTargets,
            sources: ["FouleeScreenshots/**"],
            dependencies: [
                .target(name: "Foulee")
            ]
        ),
        .target(
            name: "FouleeWatchTests",
            destinations: [.appleWatch],
            product: .unitTests,
            bundleId: "\(bundleIdBase).watchkitapp.tests",
            deploymentTargets: .watchOS("26.0"),
            sources: [
                "FouleeWatchTests/**",
                // The SwiftUI tree walker the phone suite uses (issue #221).
                // Shared rather than copied: the watch's own start flow is now
                // a routed view too (issue #224), and two divergent probes
                // would be two things to keep true.
                "FouleeTests/ViewTreeProbe.swift"
            ],
            dependencies: [
                .target(name: "FouleeWatch")
            ]
        )
    ],
    schemes: [
        .scheme(
            name: "Foulee",
            shared: true,
            buildAction: .buildAction(targets: ["Foulee"]),
            testAction: .targets(["FouleeTests"]),
            runAction: .runAction(executable: "Foulee")
        ),
        .scheme(
            name: "FouleeScreenshots",
            shared: true,
            buildAction: .buildAction(targets: ["Foulee", "FouleeScreenshots"]),
            testAction: .targets(["FouleeScreenshots"]),
            runAction: .runAction(executable: "Foulee")
        ),
        .scheme(
            name: "FouleeWatch",
            shared: true,
            buildAction: .buildAction(targets: ["FouleeWatch"]),
            testAction: .targets(["FouleeWatchTests"]),
            runAction: .runAction(executable: "FouleeWatch")
        )
    ]
)
