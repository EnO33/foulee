import ProjectDescription

let bundleIdBase = "com.eno33.foulee"
let deploymentTargets: DeploymentTargets = .iOS("26.0")

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
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES"
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release")
        ]
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
                    "Foulée enregistre tes marches du midi comme séances dans Santé."
            ]),
            sources: ["Foulee/**"],
            resources: [
                .glob(pattern: "Foulee/Resources/**", excluding: ["Foulee/Resources/Foulee.entitlements"])
            ],
            entitlements: .file(path: "Foulee/Resources/Foulee.entitlements"),
            dependencies: [
                .package(product: "Dependencies")
            ]
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
        )
    ]
)
