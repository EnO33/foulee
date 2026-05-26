# Foulée

> Bouge un peu, chaque midi.

iOS 26 app that helps you keep a daily lunchtime walk streak going. Reads from HealthKit, reminds you just before noon, runs a Live Activity during the walk, and ships an Apple Watch companion.

## Stack

- **Swift 6.2**, **SwiftUI**, iOS 26 + watchOS 26
- **HealthKit** — steps, distance, calories, walking workouts
- **ActivityKit** — Live Activity for the active walk (Dynamic Island + Lock Screen)
- **WeatherKit** — midday weather card
- **WidgetKit** — Watch complications
- **UserNotifications** — pre-walk reminder
- **SwiftData** — local preferences + session history
- **Tuist** — project generation (no `.xcodeproj` churn in git)
- **swift-dependencies** ([Point-Free](https://github.com/pointfreeco/swift-dependencies)) — testable wrappers around system frameworks

## Prerequisites

- macOS with Xcode 26+
- [Tuist](https://tuist.dev) (`brew install --cask tuist`)
- [SwiftLint](https://github.com/realm/SwiftLint) (`brew install swiftlint`)

## Run locally

```sh
tuist install        # fetch SPM dependencies
tuist generate       # generate Foulee.xcworkspace
open Foulee.xcworkspace
```

Then pick the **Foulee** scheme and run on an iOS 26 simulator.

## Layout

```
.
├── Project.swift          # Tuist manifest (targets, deps, settings)
├── Tuist.swift            # Tuist global config
├── Foulee/                # iPhone app sources
│   ├── App/               # Entry point + root view
│   ├── DesignSystem/      # Colors, typography, glass material, icons
│   ├── Features/          # Today, Active, Stats, Onboarding, Settings
│   └── Resources/         # Assets, Info.plist
├── FouleeTests/           # Unit tests
└── .github/workflows/     # CI (lint + build)
```

## Conventions

- **Commits** — [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`, `ci:`)
- **PRs** — small, focused, one PR per task
- **Style** — SwiftLint + `swift-format` (CI-enforced)
- **Errors** — no `try`/`catch` blocks; use `throws` + propagation, `Result`, or `do { try await … }` at the highest sensible boundary only
- **Positive code** — guard-based early returns, declarative SwiftUI, no flag-based branches when a value-based one will do

## License

MIT — see [LICENSE](LICENSE).
