import Foundation
import ProjectDescription

let bundleIdBase = "com.eno33.foulee"
let deploymentTargets: DeploymentTargets = .iOS("26.0")

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
        )
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.2",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
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
            destinations: .iOS,
            product: .app,
            bundleId: bundleIdBase,
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Foulée",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "UILaunchScreen": [:],
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "NSHealthShareUsageDescription":
                    "Foulée lit tes pas, ta distance et tes minutes d'activité pour t'aider à suivre tes marches du midi.",
                "NSHealthUpdateUsageDescription":
                    "Foulée enregistre tes marches du midi comme séances dans Santé.",
                "NSMotionUsageDescription":
                    "Foulée compte tes pas en direct pendant la marche du midi.",
                "NSLocationWhenInUseUsageDescription":
                    "Foulée utilise ta position pour afficher la météo de midi à ton endroit.",
                "NSSupportsLiveActivities": true
            ]),
            sources: ["Foulee/**"],
            resources: [
                .glob(pattern: "Foulee/Resources/**", excluding: ["Foulee/Resources/Foulee.entitlements"])
            ],
            entitlements: .file(path: "Foulee/Resources/Foulee.entitlements"),
            dependencies: [
                .package(product: "Dependencies"),
                .target(name: "FouleeLiveActivity")
            ]
        ),
        .target(
            name: "FouleeLiveActivity",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "\(bundleIdBase).liveactivity",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Foulée Marche",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension"
                ]
            ]),
            sources: [
                "FouleeLiveActivity/**",
                "Foulee/Walk/WalkActivityAttributes.swift"
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
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "WKApplication": true,
                "WKWatchOnly": false,
                "WKCompanionAppBundleIdentifier": .string(bundleIdBase),
                "NSHealthShareUsageDescription":
                    "Foulée lit tes pas, ta distance et tes minutes d'activité pour t'aider à suivre tes marches du midi.",
                "NSHealthUpdateUsageDescription":
                    "Foulée enregistre tes marches du midi comme séances dans Santé."
            ]),
            sources: ["FouleeWatch/**"],
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
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension"
                ]
            ]),
            sources: [
                "FouleeWatchWidget/**",
                "Foulee/Streak/StreakCalculator.swift",
                "Foulee/Health/DailyMinutes.swift"
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
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdBase).tests",
            deploymentTargets: deploymentTargets,
            sources: ["FouleeTests/**"],
            dependencies: [
                .target(name: "Foulee")
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
            name: "FouleeWatch",
            shared: true,
            buildAction: .buildAction(targets: ["FouleeWatch"]),
            runAction: .runAction(executable: "FouleeWatch")
        )
    ]
)
