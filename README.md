# Foulée

> Bouge un peu, chaque jour.

iOS 26 app that helps you keep a daily activity streak going — walking or running. Reads from HealthKit, reminds you just before your window, runs a Live Activity during the session, and ships an Apple Watch companion.

Since the walk/run epic it also **recognises which of the two you are doing** and
records each stretch under its own sport: on the Watch a change of activity ends
one workout and opens the next — the way Apple's own Workouts app does when you
add an activity by hand — so Health ends up with a walk *and* a run rather than
one mislabelled outing. On the iPhone the session's motion history is read when
you stop, so a « both » user is never asked. The design, and the HealthKit limit
that cost two releases to find, are written up in
[ADR 0002](docs/adr/0002-detection-marche-course.md) (French).

An outing recorded on the Watch is **mirrored to the iPhone** — figures and,
when there is a GPS fix, the route on a map, coloured by sport. The phone shows
how old each figure is rather than pretending to be live. The other way
round, an outing started on the iPhone is **shown on the Watch** — figures,
route, and pause / stop buttons — while the iPhone keeps recording it as one
workout: see [ADR 0003](docs/adr/0003-seance-partagee-iphone-watch.md) (French).

In an outing's detail, the map numbers each kilometre along the route and
marks which way it ran — a loop's start and finish meet, its arrows don't.

The **Bilan** opens on the streak and its record, then reviews the week or
the month in progress — minutes, steps, distance, outings, the days the goal
was met, the change from the period before, and the water drunk when hydration
is on — and pages back a week or a month at a time over twelve months, whose
totals and most regular weekdays close it. A tap on a day lays out its outings
on a timeline; the streak badge on the home opens it on the month. The Bilan can be shared as an image —
square or story — with the period's headline figures and nothing that says
where or when you go out. A notification announces it every Sunday
evening and every 1st of the month: see
[ADR 0004](docs/adr/0004-recap-semaine-mois.md) (French).

**Hydration** is logged to Santé one glass per tap, or another amount with a
long press. The home card draws the goal as a row of glasses filling up, and
says where the day stands against the hydration window set in Réglages — on
track, a glass behind, ahead. A tap on the card opens the day glass by glass
and the week so far: see [ADR 0005](docs/adr/0005-hydratation.md) (French).

**Réglages** opens from the gear on the home screen: one row per theme —
goals, planning, hydration, notifications, appearance, the Garmin guide and
*À propos* — each showing its current value, and a tap away from its page.
The notifications page gathers every reminder, and says so — with a way to
fix it — when iOS blocks Foulée's notifications.

**After an outing** from a watch or another app, one notification says it
arrived, with what it has best against the six months before — a record, a
pace better than usual, a trend, the week or the month — and opens it in the
Bilan. An outing recorded on the iPhone shows the same on its end screen: see
[ADR 0010](docs/adr/0010-notification-de-seance.md) (French).

An outing **cut in two** — the watch app relaunched mid-walk, a stop pressed
by mistake — is merged back from its detail in the Bilan, with the outing
right before or after it, an hour apart at most. Santé is not rewritten: the
merge is kept on the iPhone and can be undone. The watch now picks up a
session that outlived its app rather than finishing it: see
[ADR 0011](docs/adr/0011-fusion-de-sorties.md) (French).

## Compatible watches

- **Apple Watch** — native support (companion app, complications, live workouts).
- **Garmin** — via the **Garmin Connect → Apple Health** sync:
  steps, distance, workouts and water intake flow into HealthKit, which Foulée
  already reads. The streak's active-minutes metric uses the
  source-agnostic fallback shipped in
  [#181](https://github.com/getfoulee/foulee/issues/181). Architecture
  decision: [ADR 0001](docs/adr/0001-garmin-integration.md) (French).
  Troubleshooting: [Garmin FAQ](docs/faq-garmin.en.md) ([French](docs/faq-garmin.md)).
- **Garmin Connect IQ app** — [on the Connect IQ Store](https://apps.garmin.com/apps/8c11aa2c-7fc7-4e3d-8441-b2771626cbc7):
  the streak and the day's counters on the wrist, outings started from the
  watch, and direct watch↔iPhone sync (freshness + Garmin-native intensity
  minutes, ingested without double counting —
  [#189](https://github.com/getfoulee/foulee/issues/189)). The Monkey C side
  lives in [`FouleeConnectIQ/`](FouleeConnectIQ/README.md), outside the
  Tuist build.

## Stack

- **Swift 6.4** (Swift 6 language mode, complete strict concurrency), **SwiftUI**, iOS 26 + watchOS 26
- **HealthKit** — steps, distance, calories, workouts (walks and runs)
- **CoreMotion** — pedometer during a session (live cadence and pace on the
  Watch), and activity recognition to tell a walk from a run (live on the
  Watch, post-hoc on the iPhone)
- **ActivityKit** — Live Activity for the active walk (Dynamic Island + Lock Screen)
- **WeatherKit** — local weather card
- **WidgetKit** — iPhone + Watch streak widgets and complications; Control Center and Action button controls (start an outing, log a glass)
- **UserNotifications** — pre-walk reminder, weekly and monthly recap, the
  outing just landed
- **CoreLocation / MapKit** — walk route recording + map
- **UserDefaults** — on-device preferences (goal, walk window, theme). Walk
  history isn't stored locally — it's read live from HealthKit.
- **Tuist** — project generation (no `.xcodeproj` churn in git)
- **swift-dependencies** ([Point-Free](https://github.com/pointfreeco/swift-dependencies)) — testable wrappers around system frameworks

## Prerequisites

- macOS Tahoe 26.6+ on Apple silicon, with Xcode 27+ (Swift 6.4)
- [Tuist](https://tuist.dev) (`brew install --cask tuist`)
- [SwiftLint](https://github.com/realm/SwiftLint) (`brew install swiftlint`)

## Run locally

```sh
tuist install        # fetch SPM dependencies
tuist generate       # generate Foulee.xcworkspace
open Foulee.xcworkspace
```

Then pick the **Foulee** scheme and run on an iOS 26 simulator.

Before pushing, `tools/check_build.sh` compiles what CI compiles — SwiftLint,
the FouleeKit tests on macOS, the iPhone app with its extensions and tests, the
watch app with its tests — and prints only the errors.

### Signing (required for WeatherKit)

Code signing with your Apple Developer team is required for **WeatherKit** to authenticate. Without it the midday weather card falls back to `—`.

```sh
cp Local.xcconfig.template Local.xcconfig
# Edit Local.xcconfig — set DEVELOPMENT_TEAM to your 10-char team ID
tuist generate   # picks up the new xcconfig
```

Your **Team ID** is at <https://developer.apple.com/account> (top-right) or in Xcode → Settings → Accounts → your account → Team. The file is gitignored, so each developer (and CI) gets their own.

For the first WeatherKit build to succeed you also need the App ID `com.eno33.foulee` registered in the [Apple Developer portal](https://developer.apple.com/account/resources/identifiers/list) with the **WeatherKit** capability enabled (Xcode does this automatically the first time you build with "Automatically manage signing").

## Layout

```
.
├── Project.swift          # Tuist manifest (targets, deps, settings)
├── Tuist.swift            # Tuist global config
├── FouleeKit/             # Shared models and pure logic (iOS, watchOS, macOS)
├── FouleeKitTests/        # Their tests, on macOS — no simulator
├── Foulee/                # iPhone app sources
│   ├── App/               # Entry point + root view
│   ├── DesignSystem/      # Colors, typography, glass material, icons
│   ├── Features/          # Today, Active, Stats, Onboarding, Settings
│   └── Resources/         # Assets, Info.plist
├── FouleeTests/           # Unit tests that need the app
├── FouleeAccessibilityAudit/ # Accessibility audit (UI tests) + its baseline
├── FouleeLaunchTime/      # Launch time (UI test) + its budget
├── FouleeConnectIQ/       # Garmin Connect IQ app (Monkey C) — not part of the Tuist build
├── .github/actions/       # Shared CI steps (project setup, failure reports)
└── .github/workflows/     # CI (lint + build)
```

## CI

A first job, **Changes** (`dorny/paths-filter`), sorts the change into the
app side and the Garmin side, and each job below runs only when its side is
touched (a change to `ci.yml` itself counts as both). The app side is
**Lint**, **Kit**, **iOS**, **Accessibility audit**, **Launch time**, **watchOS** and **Dead code**; the Garmin side is
**Connect IQ** and **Connect IQ build**. **Kit** runs the FouleeKit tests on macOS, with
no simulator. The two simulator jobs compile once each (`build-for-testing`,
then `test-without-building`). **Dead code** builds the three schemes for their
index only and runs the Periphery scan on it, beside the test jobs instead of
after the iOS tests. **Build & Test** waits for every job, allows the ones the
change did not need to skip, and is the required check on `main`; on a push to
`main`, Dead code is skipped.

**Accessibility audit** runs Xcode's accessibility audit (labels, contrast,
hit regions, clipped text, Dynamic Type) on eleven screens of the iPhone app,
in capture mode so every run sees the same day. A finding fails it unless
`FouleeAccessibilityAudit/AccessibilityAuditBaseline.json` lists it: that file
is the known debt, screen by screen, like Periphery's baseline. After fixing a
finding, `tools/accessibility_audit.sh --record` rewrites it — or take the
`accessibility-audit` artifact of the CI run, recorded on CI's simulator; read
the diff before committing, since a line added there is a regression accepted.
`tools/accessibility_audit.sh` alone runs the same check as CI.

**Launch time** launches the iPhone app seven times, cold and in capture mode,
and measures each launch until the app answers a touch. It fails when the
median is more than `tolerancePercent` above the one
`FouleeLaunchTime/LaunchTimeBudget.json` records. Capture mode exists only in
Debug, so the figure is a Debug launch, meaningful only against itself. After
a change that is slower on purpose, take the `launch-time` artifact of the CI
run — recorded on CI's simulator, not on a faster Mac — or run
`tools/launch_time.sh --record`; `tools/launch_time.sh` alone runs the same
check as CI.

Dependencies update themselves: Dependabot for the GitHub Actions, and the
**Swift packages** workflow for the packages in `Project.swift` — every Monday,
or by hand from the Actions tab, it resolves them afresh on the CI image and
opens a pull request when `.package.resolved` changes. That pull request starts
no CI by itself (GitHub's rule for pull requests opened with the workflow
token): push to it, or close and reopen it, to run the checks.

## App icon

A 1024×1024 PNG, generated by a small Swift script so the icon is
reproducible from source:

```sh
swift tools/generate_app_icon.swift
```

It draws the accent gradient (`D97AFF → BF5AF2 → 7C3AED`, 135°) and
overlays `figure.walk.motion` in bold white. Outputs to both the iOS
and watchOS targets' `AppIcon.appiconset/AppIcon.png`. The PNG is
committed so contributors don't have to run the script every time.

## App Store screenshots

Same idea, one step further out: raw simulator captures go in
`appstore-screenshots/raw/`, and

```sh
swift tools/compose_appstore_screenshots.swift
```

turns them into the final boards at the exact sizes App Store Connect
demands. Captions live in the script's `shots` table. Neither the raws nor
the boards are versioned — the capture and upload procedure is, in
[`docs/RELEASE.md`](docs/RELEASE.md#9-screenshots).

## Localization

Strings are localized via **String Catalogs** (`.xcstrings`) — one per target:
- `Foulee/Resources/Localizable.xcstrings` (iPhone app, French and English)
- `FouleeKit/Resources/Localizable.xcstrings` (text the kit writes itself — activity names, highlights — French and English)
- `FouleeWatch/Resources/Localizable.xcstrings` (Watch app)
- `FouleeWatchWidget/Resources/Localizable.xcstrings` (Watch widget)
- `FouleeWidget/Resources/Localizable.xcstrings` and `FouleeLiveActivity/Resources/Localizable.xcstrings` (iPhone widgets and Live Activity, French and English), with an `InfoPlist.xcstrings` each for the extension's name

`Project.swift` enables:
- `SWIFT_EMIT_LOC_STRINGS` — the compiler extracts every localizable literal (`Text("…")`, `String(localized:)`, a `LocalizedStringResource` argument).
- `STRING_CATALOG_GENERATE_SYMBOLS` — generates type-safe accessors (`Text(.welcomeTitle)` works once a key is in the catalog).
- `LOCALIZATION_PREFERS_STRING_CATALOGS` — makes `.xcstrings` the canonical store.

Source language is **French**. The rules that keep a string translatable:

- A component takes its text as `LocalizedStringResource`, never `String`: `Text(someString)` is shown verbatim. Text already in the screen's language (a figure, a label the kit wrote) goes through `.verbatim(_:)`.
- Text built outside a view is `String(localized: "…")` in the apps, `kitText("…")` in FouleeKit. `kitText` reads the kit's catalog in `Locale.app`, the language of the app showing it, so an English iPhone and a French-only watch never mix.
- One literal per sentence: `"a " + "b"` is never extracted. Counts are plural variations in the catalog (`%lld jours` → « 1 jour », "1 day"), not `count > 1 ? "s" : ""`.
- `Locale.app` follows the languages whose `Localizable` table the app actually ships, plus French, the source: a target speaks English once its catalog does.

To refresh the catalogs from the code: `xcodebuild -exportLocalizations -project Foulee.xcodeproj -localizationPath <dir> -exportLanguage en`, then translate the new keys in Xcode.

## Release

Foulée ships to **TestFlight automatically** when you push a version tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The version comes from the tag, the build number from the commit count. See
[docs/RELEASE.md](docs/RELEASE.md) for the one-time App Store Connect setup and
the GitHub secrets the workflow needs.

## Conventions

- **Commits** — [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`, `ci:`)
- **PRs** — small, focused, one PR per task
- **Style** — SwiftLint + `swift-format` (CI-enforced)
- **Errors** — no `try`/`catch` blocks; use `throws` + propagation, `Result`, or `do { try await … }` at the highest sensible boundary only
- **Shared code** — models and pure logic go in `FouleeKit`, tested on macOS; what other targets use is `public` ([ADR 0007](docs/adr/0007-fouleekit-logique-pure.md))
- **Concurrency** — the iPhone app is main-actor by default: data types, pure logic and system clients are `nonisolated`, heavy async work is `@concurrent` ([ADR 0006](docs/adr/0006-isolation-main-actor-par-defaut.md))
- **Watch screens** — one main action per screen, pinned at the bottom; a choice closes with the system's close button; session pages follow the Exercice app's order ([ADR 0008](docs/adr/0008-interface-montre.md)). On Garmin, the same content with the native activity app's buttons and system components ([ADR 0009](docs/adr/0009-app-garmin-seance.md))
- **Tests** — never read the real clock: inject it (`@Dependency(\.date)` on the phone, `clock:` on the watch's workout store); a precondition is `try #require(…)`, not a `guard` that records an issue and returns
- **Positive code** — guard-based early returns, declarative SwiftUI, no flag-based branches when a value-based one will do

## License

MIT — see [LICENSE](LICENSE).
