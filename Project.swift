import Foundation
import ProjectDescription
import ProjectDescriptionHelpers

let deploymentTargets: DeploymentTargets = .iOS("26.0")

/// The tests read figures and dates the way a French device writes them —
/// « 4 218 », « 1,5 km », « 20:05 » — whatever the Mac or simulator running
/// them is set to (issue #586).
let frenchTests: TestActionOptions = .options(language: "fr", region: "FR")

// Main-actor isolation by default (issue #407, ADR 0006): code is on the main
// actor unless it says otherwise, so what leaves it is marked `nonisolated` or
// `@concurrent` where it is declared. Enabled target by target; a target
// without it keeps the Swift default (nonisolated).
let mainActorByDefault: SettingsDictionary = [
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES"
]

// The kit's macOS build exists for its tests alone (issue #425): signed to run
// locally, so it needs no team, on CI or on a developer's Mac.
let kitMacSigning: SettingsDictionary = [
    "CODE_SIGN_IDENTITY[sdk=macosx*]": "-",
    "CODE_SIGN_STYLE[sdk=macosx*]": "Manual"
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
        // 1.17 is the floor: it depends on swift-issue-reporting 2, whose
        // reading of Swift Testing's private layout matches Swift 6.4. Older
        // releases pull in xctest-dynamic-overlay, which crashed the test host
        // on Xcode 27 below 1.10.0 (issues #404, #414).
        .remote(
            url: "https://github.com/pointfreeco/swift-dependencies",
            requirement: .upToNextMajor(from: "1.17.0")
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
            // Language mode, not compiler version: Swift 6.4 (Xcode 27) compiles
            // in the Swift 6 mode, which has no minor versions.
            "SWIFT_VERSION": "6",
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
        // The pure logic and the models every target shares (issue #425, ADR
        // 0007): one module, compiled once per platform, instead of the same
        // files listed in each target. macOS is there for the tests alone:
        // they run on the runner itself, with no simulator to boot.
        .target(
            name: "FouleeKit",
            destinations: [.iPhone, .appleWatch, .mac],
            product: .framework,
            bundleId: "\(bundleIdBase).kit",
            deploymentTargets: .multiplatform(iOS: "26.0", macOS: "15.0", watchOS: "26.0"),
            sources: ["FouleeKit/Sources/**"],
            // The text the kit writes itself — activity names, highlights —
            // read through `kitText` (issue #587).
            resources: ["FouleeKit/Resources/**"],
            settings: .settings(base: kitMacSigning.merging([
                // Linked by the widgets and the Live Activity.
                "APPLICATION_EXTENSION_API_ONLY": "YES",
                // The iPhone app embeds the framework, and so does the watch
                // app it carries: two bundles under one iOS app. App Store
                // Connect rejects two bundles with one identifier there
                // (ITMS-90685), so the watch's copy takes its own.
                "PRODUCT_BUNDLE_IDENTIFIER[sdk=watchos*]": "\(bundleIdBase).kit.watch",
                "PRODUCT_BUNDLE_IDENTIFIER[sdk=watchsimulator*]": "\(bundleIdBase).kit.watch",
                // Signed when the apps embed it (Code Sign On Copy), with
                // their identity. Signing it on its own needs a development
                // certificate in the keychain, which a framework cannot get
                // from cloud signing: the release archive failed on it.
                "CODE_SIGNING_ALLOWED[sdk=iphoneos*]": "NO",
                "CODE_SIGNING_ALLOWED[sdk=watchos*]": "NO"
            ]) { $1 })
        ),
        .target(
            name: "FouleeKitTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "\(bundleIdBase).kit.tests",
            deploymentTargets: .macOS("15.0"),
            sources: ["FouleeKitTests/**"],
            dependencies: [
                .target(name: "FouleeKit")
            ],
            settings: .settings(base: kitMacSigning.merging([
                // No host app embeds the framework on macOS: the bundle finds
                // it next to itself, in the build products directory.
                "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@loader_path/../../.."]
            ]) { $1 })
        ),
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
                .target(name: "FouleeKit"),
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
            settings: .settings(base: mainActorByDefault.merging([
                // The Connect IQ framework ships Objective-C categories; without
                // -ObjC the linker drops them and the SDK crashes at runtime on
                // unrecognised selectors (SDK guide, "Add required linker flags").
                "OTHER_LDFLAGS": ["$(inherited)", "-ObjC"]
            ]) { $1 })
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
                // The intents the app registers too: an App Intent is declared
                // in each process that runs it, not linked.
                "Foulee/Shared/LogWaterIntent.swift",
                "Foulee/Shared/StartOutingIntent.swift",
                // Shared with « Où j'en suis aujourd'hui » (#605), so Siri
                // answers with the widgets' own figures.
                "Foulee/Shared/WidgetLiveMetrics.swift",
                "FouleeWatchWidget/StreakEntry.swift"
            ],
            resources: [
                .glob(
                    pattern: "FouleeWidget/Resources/**",
                    excluding: ["FouleeWidget/Resources/FouleeWidget.entitlements"]
                )
            ],
            entitlements: .file(path: "FouleeWidget/Resources/FouleeWidget.entitlements"),
            dependencies: [
                .target(name: "FouleeKit")
            ]
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
                // ActivityKit, which FouleeKit does not import: macOS has none.
                // `SessionActivity+HealthKit` stays out of this extension too,
                // so no HealthKit is pulled into a process that writes nothing.
                "Foulee/Walk/WalkActivityAttributes.swift"
            ],
            resources: [
                .glob(
                    pattern: "FouleeLiveActivity/Resources/**",
                    excluding: ["FouleeLiveActivity/Resources/FouleeLiveActivity.entitlements"]
                )
            ],
            entitlements: .file(path: "FouleeLiveActivity/Resources/FouleeLiveActivity.entitlements"),
            dependencies: [
                .target(name: "FouleeKit")
            ]
        ),
        .target(
            name: "FouleeWatch",
            destinations: [.appleWatch],
            product: .app,
            bundleId: "\(bundleIdBase).watchkitapp",
            deploymentTargets: .watchOS("26.0"),
            infoPlist: .extendingDefault(with: fouleeWatchInfoPlist),
            sources: [
                "FouleeWatch/**",
                // The route recorder the phone's map already uses (issue
                // #312): one accuracy rule, one stream lifetime, one place
                // that asks for location. Main-actor state, so not in the kit.
                "Foulee/Location/RouteRecorder.swift",
                // The watch writes its own workouts, with the phone's mapping
                // to HealthKit (issue #223). HealthKit stays out of the kit.
                "Foulee/Shared/SessionActivity+HealthKit.swift",
                // Its climb and descent too, under the same keys (issue #564).
                "Foulee/Shared/Elevation+HealthKit.swift",
                // The colours an outing is drawn in by sport, shared with the
                // phone's detail (issue #320), and the colour of each daily
                // metric, the phone's rings' (#372). SwiftUI, so not in the kit.
                "Foulee/Shared/ActivityPalette.swift",
                "Foulee/Shared/SessionActivity+Tint.swift",
                "Foulee/Shared/MetricPalette.swift",
                // Their light-mode shades (#599); the watch keeps the dark ones.
                "Foulee/Shared/ReadablePalette.swift",
                // Fixed-size counters that follow Dynamic Type (#600).
                "Foulee/Shared/ScaledSystemFont.swift",
                // The App Store capture seed (issue #239). Only the
                // Foundation-only half: the watch board and the phone board
                // must show the same day, and the way to guarantee that is to
                // compile the same constants, not to copy them. The rest of
                // Foulee/Screenshots/ names phone types and stays out.
                // Everything in this file is `#if DEBUG`.
                "Foulee/Screenshots/ScreenshotSeedCore.swift"
            ],
            resources: [
                .glob(
                    pattern: "FouleeWatch/Resources/**",
                    excluding: ["FouleeWatch/Resources/FouleeWatch.entitlements"]
                )
            ],
            entitlements: .file(path: "FouleeWatch/Resources/FouleeWatch.entitlements"),
            dependencies: [
                .target(name: "FouleeKit"),
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
                "FouleeWatchWidget/**"
            ],
            resources: [
                .glob(
                    pattern: "FouleeWatchWidget/Resources/**",
                    excluding: ["FouleeWatchWidget/Resources/FouleeWatchWidget.entitlements"]
                )
            ],
            entitlements: .file(path: "FouleeWatchWidget/Resources/FouleeWatchWidget.entitlements"),
            dependencies: [
                .target(name: "FouleeKit")
            ]
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
            ],
            settings: .settings(base: mainActorByDefault)
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
        // Xcode's accessibility audit on the main screens (issue #602). A UI
        // test bundle like `FouleeScreenshots`, whose capture mode and
        // plumbing it reuses so every screen shows the same seeded day; its
        // own scheme and CI job, so the unit suite stays fast.
        .target(
            name: "FouleeAccessibilityAudit",
            destinations: [.iPhone],
            product: .uiTests,
            bundleId: "\(bundleIdBase).accessibilityaudit",
            deploymentTargets: deploymentTargets,
            sources: [
                "FouleeAccessibilityAudit/**",
                "FouleeScreenshots/ScreenshotCapture.swift"
            ],
            resources: ["FouleeAccessibilityAudit/AccessibilityAuditBaseline.json"],
            dependencies: [
                .target(name: "Foulee")
            ]
        ),
        // The watch half of the capture set (issue #239). Same shape as
        // `FouleeScreenshots`, and absent from the `FouleeWatch` scheme's test
        // action for the same reason: CI's "Test (watchOS)" step runs the unit
        // suite, it does not boot a watch to take pictures on every pull
        // request.
        .target(
            name: "FouleeWatchScreenshots",
            destinations: [.appleWatch],
            product: .uiTests,
            bundleId: "\(bundleIdBase).watchkitapp.screenshots",
            deploymentTargets: .watchOS("26.0"),
            sources: ["FouleeWatchScreenshots/**"],
            dependencies: [
                .target(name: "FouleeWatch")
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
        // The kit's tests, on macOS (issue #425): no simulator, seconds.
        .scheme(
            name: "FouleeKit",
            shared: true,
            buildAction: .buildAction(targets: ["FouleeKit"]),
            testAction: .targets(["FouleeKitTests"], options: frenchTests)
        ),
        .scheme(
            name: "Foulee",
            shared: true,
            buildAction: .buildAction(targets: ["Foulee"]),
            testAction: .targets(["FouleeTests"], options: frenchTests),
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
            name: "FouleeAccessibilityAudit",
            shared: true,
            buildAction: .buildAction(targets: ["Foulee", "FouleeAccessibilityAudit"]),
            testAction: .targets(["FouleeAccessibilityAudit"])
        ),
        .scheme(
            name: "FouleeWatch",
            shared: true,
            buildAction: .buildAction(targets: ["FouleeWatch"]),
            testAction: .targets(["FouleeWatchTests"], options: frenchTests),
            runAction: .runAction(executable: "FouleeWatch")
        ),
        .scheme(
            name: "FouleeWatchScreenshots",
            shared: true,
            buildAction: .buildAction(targets: ["FouleeWatch", "FouleeWatchScreenshots"]),
            testAction: .targets(["FouleeWatchScreenshots"]),
            runAction: .runAction(executable: "FouleeWatch")
        )
    ]
)
