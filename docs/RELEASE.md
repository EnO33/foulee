# Releasing Foulée

Foulée ships to **TestFlight automatically** from CI. Push a version tag and
the [`Release` workflow](../.github/workflows/release.yml) builds the app (iOS
app + widget + Live Activity + embedded Watch app), signs it, and uploads it to
App Store Connect.

```sh
git tag v0.1.0
git push origin v0.1.0
```

- **Marketing version** (`CFBundleShortVersionString`) comes from the tag — `v0.1.0` → `0.1.0`.
- **Build number** (`CFBundleVersion`) is the commit count (`git rev-list --count HEAD`), so it always increases.

Everything below is **one-time setup**. Once it's done, releasing is just the two commands above.

---

## 1. Apple Developer Program

You need a paid **Apple Developer Program** membership ($99/year) and your
**Team ID** (10 characters, e.g. `A1B2C3D4E5`) — find it at
<https://developer.apple.com/account> (top right) or Xcode → Settings →
Accounts. This is the value for the `DEVELOPMENT_TEAM` secret below.

## 2. Register the App IDs (Identifiers)

In the [Developer Portal → Identifiers](https://developer.apple.com/account/resources/identifiers/list),
register one App ID per bundle id, each with the capabilities it needs:

| Bundle ID | Capabilities to enable |
|-----------|------------------------|
| `com.eno33.foulee` | HealthKit, WeatherKit, Associated Domains |
| `com.eno33.foulee.widget` | HealthKit |
| `com.eno33.foulee.liveactivity` | _(none)_ |
| `com.eno33.foulee.watchkitapp` | HealthKit |
| `com.eno33.foulee.watchkitapp.widget` | HealthKit |

> `com.eno33.foulee` was likely already created when you first built with
> WeatherKit. The four extension/Watch IDs probably aren't yet — Xcode can
> also create them the first time you build with automatic signing, but
> registering them up front makes the CI build deterministic.

Associated Domains carries the universal links of `getfoulee.app` and
`www.getfoulee.app`. iOS opens the app only once the site serves
`/.well-known/apple-app-site-association` listing the app ID
`<team id>.com.eno33.foulee` and its paths (getfoulee/web); until then the
links open Safari.

The `FouleeKit` framework needs no App ID: it is signed with the app that
embeds it. It is embedded twice, in the iPhone app and in the watch app, under
two identifiers (`com.eno33.foulee.kit`, `com.eno33.foulee.kit.watch`): App
Store Connect rejects two bundles with one identifier under an iOS app
(ITMS-90685). To check an archive before tagging, without signing:

```sh
xcodebuild archive -workspace Foulee.xcworkspace -scheme Foulee \
  -destination 'generic/platform=iOS' -archivePath /tmp/Foulee.xcarchive \
  CODE_SIGNING_ALLOWED=NO
find /tmp/Foulee.xcarchive -name "*.framework" -o -name "*.appex" -o -name "*.app" \
  | while read -r b; do /usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$b/Info.plist"; done \
  | sort | uniq -d   # prints nothing when every identifier is unique
```

## 3. Create the app record in App Store Connect

[App Store Connect → Apps → +](https://appstoreconnect.apple.com/apps):

- **Platform**: iOS
- **Bundle ID**: `com.eno33.foulee`
- **Name**: `Foulée`
- **Primary language**: French
- **SKU**: anything stable, e.g. `foulee-ios`

This record must exist before the first TestFlight upload.

## 4. App privacy (required — the app reads Health + Location)

Under the app's **App Privacy** section, declare:

- **Health & Fitness** — read access (steps, distance, exercise minutes, heart rate, workouts).
- **Location** — used while in use (local weather + the route of an outing).

A **privacy policy URL** is mandatory because the app touches Health and
Location data.

The policy is [`docs/privacy.md`](privacy.md), published on the site at
<https://getfoulee.app/confidentialite> (the site's repository, getfoulee/web,
keeps a copy: update it with this file). Its English version,
[`docs/privacy.en.md`](privacy.en.md), is published at
<https://getfoulee.app/en/privacy>: change both files in the same pull request,
and the Garmin FAQ with [`docs/faq-garmin.en.md`](faq-garmin.en.md) the same
way. The app links to the page in its own language from
**Réglages › À propos** (`AppLinks.privacyPolicy`). The listing in
`fastlane/metadata/fr-FR/` (§ 10.1) gives App Store Connect the same URL, and
<https://getfoulee.app/assistance> as the support URL, so the app and the store
page never point to two different texts.

## 5. Distribution certificate (`.p12`)

If you don't already have an **Apple Distribution** certificate, create one in
Xcode (Settings → Accounts → Manage Certificates → +) or the Developer Portal.
Then export it **with its private key** from **Keychain Access** as a `.p12`
(set a password), and base64-encode it for the GitHub secret:

```sh
base64 -i Distribution.p12 | pbcopy   # → DIST_CERT_P12_BASE64
```

## 6. App Store Connect API key (`.p8`)

[Users and Access → Integrations → App Store Connect API → Team Keys → +](https://appstoreconnect.apple.com/access/integrations/api):

- **Access**: `Admin`. App Manager is **not** enough — the CI uses the key for
  cloud signing (`-allowProvisioningUpdates` creates the distribution
  provisioning profiles), and managing certificates/profiles requires Admin.
  An App Manager key fails export with *"Cloud signing permission error /
  No profiles … were found"*.
- Download the `.p8` **once** (you can't re-download it) and note the
  **Key ID** and the team **Issuer ID** shown on that page.

```sh
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy   # → ASC_KEY_P8_BASE64
```

This single key authenticates both the provisioning-profile creation
(`-allowProvisioningUpdates`) and the TestFlight upload — no Apple ID password
or app-specific password needed.

## 7. GitHub Actions secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|--------|-------|
| `DEVELOPMENT_TEAM` | Your 10-char Team ID |
| `DIST_CERT_P12_BASE64` | base64 of the distribution `.p12` (step 5) |
| `DIST_CERT_PASSWORD` | The password you set when exporting the `.p12` |
| `ASC_KEY_ID` | Key ID from step 6 |
| `ASC_ISSUER_ID` | Issuer ID from step 6 |
| `ASC_KEY_P8_BASE64` | base64 of the `.p8` (step 6) |
| `DEV_CERT_P12_BASE64` | *(optional)* base64 of an **Apple Development** `.p12` — see note |
| `DEV_CERT_PASSWORD` | *(optional)* password for that dev `.p12` |

The workflow decodes the `.p8`/`.p12` to disk at runtime, writes a
`Local.xcconfig` with your team, and deletes them again at the end. None of
this material is ever committed (see `.gitignore`).

> **Why the optional dev cert?** Cloud signing (`-allowProvisioningUpdates`)
> runs in a throwaway keychain, so with no development identity present it
> mints a fresh "Apple Development" certificate on *every* release — they
> accumulate until the account hits its certificate limit and archives start
> failing with *"Your account has reached the maximum number of certificates."*
> Providing a persistent dev cert lets signing reuse it. To set it up: in
> **Keychain Access** export your *Apple Development* certificate (with its
> private key) as a `.p12`, then `base64 -i Development.p12 | pbcopy` and paste
> into `DEV_CERT_P12_BASE64`. If the account ever fills up again, revoke the
> old `Created via API` development certs in the Developer portal.

---

## 8. Cut a release

First write the release notes in `docs/releases/X.Y.Z.md`, and their English
translation in `X.Y.Z.en.md`, and merge them to `main` (issue #638): they
become the GitHub release that the website's « Nouveautés » and « What's new »
pages read (the English notes under a « ## English » heading), the French
« What to Test » text of the TestFlight build, and the App Store's « What's
New » in each language (issue #622). Start from the
draft release « Prochaine version » under **Releases**: the « Release draft »
workflow rewrites it on every push to `main` with the titles of the pull
requests merged since the last `v*` tag. It is a list for you, not for users:
only the repository's writers see a draft, and the tag never publishes it. They are for users, addressing them as « tu »
(« you » in English), 2 to 5 highlights, with no issue numbers
([`docs/releases/README.md`](releases/README.md)). The release workflow stops in
its first seconds when the tagged commit has no notes for its version; add
them, then move the tag to the new commit.

```sh
# bump the tag; the workflow reads the version from it
git tag v0.1.0
git push origin v0.1.0
```

Watch **Actions → Release**. After it's green, the build shows up in
**App Store Connect → TestFlight** within a few minutes (processing time).
Add it to an internal testing group to install via the TestFlight app. The
last job publishes the GitHub release « Foulée 0.1.0 » with the notes; it
runs only once TestFlight has the build, and re-running it rewrites the notes.

The release runs on GitHub's `xcode-27` image with the **latest stable Xcode**
it ships (`setup-xcode` with `latest-stable`: no beta; a Release Candidate
counts as stable). CI, the release and the Swift packages job all select it the
same way (issue #404), so the build that ships is the one the tests ran
against, and nothing needs bumping when the image gains a newer Xcode (issue
#462). The version each run used is printed by the « Show Xcode version »
step. It therefore links the **iOS 27 / watchOS 27 SDK**: system
controls take the iOS 27 look even where no code changed. Review the screens
and recapture the screenshots on the iOS 27 runtime before promoting a build to
the store (issue #408).

## 9. Screenshots

The store boards live in `appstore-screenshots/` and are **not** versioned
(they're in `.gitignore` — binary churn, regenerated on demand). What *is*
versioned is the way to rebuild them:
[`tools/compose_appstore_screenshots.swift`](../tools/compose_appstore_screenshots.swift).

```
appstore-screenshots/
├── raw/                 ← what you capture (untouched simulator grabs)
│   ├── iphone-6.9/
│   ├── ipad-13/
│   └── watch/
├── iphone-6.9/          ← what the composer writes (what you upload)
├── ipad-13/
├── watch/
└── en-US/               ← the English set (issue #592), the same tree again
    ├── raw/
    ├── iphone-6.9/
    ├── ipad-13/
    └── watch/
```

French is the default everywhere. `tools/capture_screenshots.sh --language en`
(with or without `--watch`) runs the app in US English and writes under
`en-US/raw/`; `swift tools/compose_appstore_screenshots.swift --locale en-US`
reads it and writes the English boards under `en-US/`.

### 9.1 Capture

One simulator per size class. The names matter only through their native
resolution — App Store Connect accepts exactly these, and the composer refuses
any raw that doesn't measure them (it lists the offenders and exits non-zero,
just like a missing capture):

| Folder | Simulator | Native resolution | Automated? |
|--------|-----------|-------------------|------------|
| `iphone-6.9` | iPhone 17 Pro Max (any 6.9" iPhone) | 1320 × 2868 | yes |
| `ipad-13` | iPad Pro 13-inch (M4 or M5) | 2064 × 2752 | no — by hand |
| `watch` | Apple Watch Series 11 (46 mm) | 416 × 496 | yes |

#### iPhone — one command

```bash
tools/capture_screenshots.sh                       # iPhone 6.9"
tools/capture_screenshots.sh 02175924-56FF-…-0216  # by UDID
```

It boots the simulator, pins the status bar to 09:41 / full bars / charged,
runs the `FouleeScreenshots` UI-test target and exports the thirteen PNGs into
`appstore-screenshots/raw/iphone-6.9/`. About two minutes, unsupervised, no
Health data to enter by hand.

The set follows the app, not the other way round: when a screen changes, its
capture step in `FouleeScreenshots/ScreenshotCaptureTests.swift` and its
caption in the composer's `shots` table change in the same PR (issue #378).
The numbers are the store order (issue #582): the streak, the watch, the
walk/run detection, the Bilan, Garmin, then the rest.

| Capture | Screen |
|---------|--------|
| `01_home` | Aujourd'hui: the ring and the streak |
| `02_watch` | An outing running on the Apple Watch, as the iPhone shows it |
| `03_outing` | Today's outing in the Bilan, a walk that became a run, with its portions |
| `04_summary` | The Bilan on the current week |
| `05_garmin` | An outing running on a Garmin, as the iPhone shows it |
| `06_streak` | The Bilan opened from the streak badge, on the month in progress |
| `07_session` | An outing recorded by the iPhone alone |
| `08_hydration` | The Hydratation screen, opened from its card |
| `09_stats` | The steps statistics |
| `10_weather` | The weather sheet |
| `11_minutes`, `12_settings`, `13_onboarding` | For the review sets only: never boarded |

`03_outing`, `04_summary`, `06_streak`, `08_hydration` and `10_weather` are
sheets, so their boards trim the dimmed band above them. The two wrist boards
each need their own launch, with `-FouleeScreenshotWatchOuting` or
`-FouleeScreenshotGarminOuting`: once a wrist is recording, the home offers
that outing instead of « Repartir », which `07_session` needs. The doubles
state the watch board's own session (18:24, 2 480 pas), and nothing reaches a
watch.

What makes it repeatable is the **capture mode** (issue #235): the target
launches the app with `-FouleeScreenshotMode`, which swaps every `@Dependency`
client for a deterministic double and freezes the clock at Thursday 14 May
2026, 14:35. Two runs on two different days, **on the same simulator**, produce
byte-identical files. The numbers live in `Foulee/Screenshots/` —
`ScreenshotSeedCore.swift` for the constants (the half the watch compiles too)
and `ScreenshotSeed*.swift` for everything derived from them;
`FouleeTests/ScreenshotSeedTests` holds them consistent — the 34-day streak on
the card really is what the seeded history computes.

Four things worth knowing:

- The mode is **compiled out of Release builds** — everything under
  `Foulee/Screenshots/` and its single call site in `FouleeApp.init()` sit
  inside `#if DEBUG` — and inside a Debug build it still needs the explicit
  launch argument. `FouleeTests/ScreenshotModeTests` asserts a normal launch
  doesn't activate it.
- A capture run **leaves nothing behind**. The doubles write no `HKWorkout`, no
  `dietaryWater` and no Connect IQ session; the preferences and the widget app
  group are diverted into throwaway suites, so the fabricated counters never
  reach your real widgets; the Watch push is muted.
- The **runtime is part of the output**: the same device model on iOS 26.0 and
  on 26.5 renders every PNG differently. That is why the script refuses a
  simulator name shared by two available devices and asks for a UDID instead —
  reproducibility that depends on which runtimes happen to be installed is not
  reproducibility.
- `appstore-screenshots/` is **not tracked by git** (issue #72) and must stay
  that way. `raw/` is the capture output; the boards are composed from it.

Review sets come from three options of the script, for checking a new SDK, a
redesign or a translation (issues #408, #594). They refuse the default set
name, so they can never overwrite a store set:

```bash
tools/capture_screenshots.sh --dark "" review-dark
tools/capture_screenshots.sh --text-size accessibility-large "" review-a11y
tools/capture_screenshots.sh --language en --pseudo "" review-pseudo
tools/capture_screenshots.sh --watch --language en --pseudo "" review-pseudo
```

`--pseudo` adds Xcode's double-length pseudo-language
(`-NSDoubleLocalizedStrings YES`): every string written twice, to see what a
longer translation would cut. It doubles the *format*, so an interpolated
string reads « Session under way on @ Session under way on your Watch your
Watch » and a count « lld 34 »: judge the lengths, not the words. The capture
tests then find their way by « contains the label » instead of the exact
label. What it cut on 27 October 2026, and was left as it is because the real
English fits: the session ring's captions (a fixed 232 pt ring), the stats
totals, the outing detail's one-line scrubbing hint and the hydration serving
names — all one line by design, shrinking before they cut. The watch wraps
rather than cuts.

`--dark` seeds the dark theme through a third launch argument
(`-FouleeScreenshotDark`); `--text-size` sets the simulator's text size for the
run and puts it back afterwards. Both capture targets launch the app in French
(`-AppleLanguages (fr) -AppleLocale fr_FR`) whatever the host's language: a
runner in English grouped thousands as « 8,240 » on the boards.

#### Apple Watch — one command

```bash
tools/capture_screenshots.sh --watch                                    # 46 mm
tools/capture_screenshots.sh --watch "Apple Watch SE 3 (40mm)" probe-40  # a probe
```

Same script, same result bundle, same export; another platform, another scheme
(`FouleeWatchScreenshots`) and another folder — the four PNGs land in
`appstore-screenshots/raw/watch/`. About a minute.

**Only the 46 mm run may omit the set name.** The `watch` folder is the one the
composer reads, and it accepts 416 × 496 and nothing else; another watch grabs
another size (`Apple Watch Ultra 3 (49mm)` grabs 422 × 514), so a run that
defaulted into `watch/` would overwrite a good set with files the composer then
rejects one by one. The script now takes one throwaway grab after boot and
refuses that case before writing anything. A named set is never checked — it is
a probe, it is not composed, and it cannot clobber the real one. Probes are
worth running: the 40 mm is the smallest wrist the app ships on and the first
place a layout runs out of room.

The watch has its **own** capture mode (issue #239), because the phone's is a
set of `@Dependency` doubles and the watch target has no dependency container:
`WatchTodayStore` builds an `HKHealthStore` itself. So the same launch argument
(`-FouleeScreenshotMode`) instead flips one flag, `WatchScreenshotMode`, and
each of the watch's HealthKit entry points takes a one-line `#if DEBUG` early
return on it — the home serves `ScreenshotSeed`, « Démarrer » shows a seeded
session with no `HKWorkoutSession` behind it, and the observers, the background
delivery and the crash-recovery write are all skipped.

Five things worth knowing, beyond the four listed for the iPhone (which all
hold here too — compiled out of Release, explicit argument, runtime is part of
the output, nothing tracked by git):

- **The numbers are the phone's numbers.** Both apps compile
  `Foulee/Screenshots/ScreenshotSeedCore.swift` — the Foundation-only half of
  the seed — so the 34-day streak on the wrist board is the same constant as
  the one on the phone board, not a second number that happens to match.
  `FouleeWatchTests/WatchScreenshotModeTests` asserts it field by field, and
  proves the seeded session reaches HealthKit not at all (a trap double counts
  every call; the count is zero).
- **The clock in the corner is not ours.** watchOS draws the time over every
  app and `simctl status_bar` refuses on this platform ("Status bar overrides
  not supported"). Everything Foulée draws is byte-identical between runs; that
  one overlay follows the host clock, so two runs in the same minute produce
  identical files and two runs across a minute boundary differ in those few
  hundred pixels alone. Nothing else varies — and never crop it out (see the
  rules below).

  Two consequences, both of them the operator's to carry:

  - **Issue #239's « deux exécutions produisent des fichiers identiques » is not
    literally true on the watch, and must not be ticked as if it were.** Two
    consecutive runs give six different md5s. A pixel diff says why, and says it
    narrowly: every differing pixel on all the boards falls in
    **y 39…63 from the top, and roughly x 300…383** — the clock glyphs, ~1 100 of
    206 336 pixels — and nowhere else. (Both the count *and* the box's left
    edge move with which digits changed: 306 and 1 098 at one measurement,
    300 and 1 104 at another. The right edge and the two rows do not.) Restate the criterion when closing: *identical
    except the watchOS clock overlay, bounded to the top-right corner*. A ticked
    box would otherwise read as a byte-for-byte guarantee the tooling cannot
    give.
  - **The overlay is the host's wall clock, so run the watch capture at a time
    that reads plausibly beside the iPhone boards**, which `simctl status_bar`
    pins to Apple's 09:41. A listing carrying 09:41 on the phone and 17:52 on
    the wrist is the kind of detail a reviewer notices. No app content sits
    under the corner any more (see below), so the only thing left to get right
    is the hour on the clock.
- **No board may put content under that corner.** The live session screen used
  to: a bare `VStack` with a 38 pt elapsed clock at the top overflowed its
  container at both ends, which pushed the clock up into the overlay — the two
  overprinted into unreadable glyphs on the finished board — and pushed
  « Arrêter » off the bottom. On a 40 mm SE the stop button was off screen
  entirely, with nothing to scroll: **a session could not be stopped**. Issue
  #241 answered with a scroll view, so content starts below the system time like
  the home's does; issue #274 split the screen into pages, and « Arrêter » now
  has one to itself. If a future watch screen draws large text across the top,
  check it on the 40 mm probe before capturing.
- **The session board no longer scrolls, and that was measured, not assumed.**
  Its `Shot` carries no `scrolls` flag since issue #274. Do not restore one
  without re-running the 40 mm probe: the first paged version of this screen
  still cut « kcal » and « bpm » off the bottom of a **46 mm**, because a paged
  `TabView` keeps more room above its content than a scroll view does. What made
  it fit was two-line metric tiles, a 34 pt clock and no divider — all of it
  verified on `appstore-screenshots/raw/probe-40mm/watch-02-session.png`, not on
  paper.
- **The capture seed must draw what the app draws, or the probe measures
  nothing.** Issue #299: the seed left `activityTotals` empty, so the board
  photographed a « Séance » page one line shorter than the one on a wrist — and
  two « it fits with room to spare » conclusions were drawn from it. With the
  seed telling the truth, the page overflowed a 40 mm and the capture sentinel
  caught it. Any figure the app fills from the first ingest belongs in the seed.
- **Run the 40 mm probe whenever the session pager changes.** It is not a
  formality. Issue #274 shipped the pager on the *vertical* axis; issue #276's
  probe run found that a swipe on a 40 mm never left the first page, because the
  page's own scroll view took the gesture — so « Arrêter » was unreachable by
  swiping, which is issue #241's defect returning by another route. The 46 mm
  capture passed throughout. The axis is horizontal now; the probe is what
  found out.
- **The watch is uninstalled first**, which clears its app-group container, so
  « Démarrer » starts a session outright instead of asking which activity. That
  question depends on what the phone last synced; the uninstall is what keeps
  the session capture from depending on the developer's own wrist. (The phone
  stopped asking altogether in issue #246 — the watch still does, because it
  freezes its `activityType` when the session is created.)
- **The seeded outing changed sport, and the third board is where that shows.**
  Since issue #276 the seed carries two legs — a 12:04 walk that became a 06:20
  run — and `watch-03-jambes` photographs them. The « Séance » board is
  unaffected: it shows the outing's totals and the sport being done, never a
  breakdown.
  The legs **add up to those totals exactly** (1 650 + 830 pas, 1 000 + 830 m,
  60 + 48 kcal, 12:04 + 06:20), asserted by `seededLegsAddUp`. A listing whose
  own arithmetic does not close is one a reviewer can catch.
  Both legs are **closed**, though a real outing's newest leg is still running:
  a running leg measures itself against the instant it is drawn, which would
  make the board depend on when the shutter fired.
  Whatever a future board shows here, check the app can actually draw it: the
  seed once advertised a breakdown the app could not produce, and the composed
  board shipped that lie for an afternoon (see
  [ADR 0002](adr/0002-detection-marche-course.md)).

#### iPad — nothing to capture

The iPad boards are composed from the **iPhone** captures. There is nothing to
grab on an iPad, and trying is a dead end worth documenting so nobody repeats
it (issue #240).

Foulée is an iPhone app — `destinations: [.iPhone]` in Project.swift — that
runs on iPad in compatibility mode. Capturing it on an iPad simulator gives a
narrow phone window sitting on the iPad wallpaper, with the iPad's own status
bar and its **real** date outside the window. Verified: unusable as a store
screenshot. The June boards were never iPad captures either — they are the
iPhone grabs recomposed onto a 2064 × 2752 canvas, which is exactly what App
Store Connect's iPad tab wants.

The composer expresses that with `sourceFamily` on `Shot`: the iPad boards read
`raw/iphone-6.9/` and draw onto the iPad canvas. So once the iPhone captures
exist, the iPad set needs no extra step — `swift tools/compose_appstore_screenshots.swift`
writes both.

### 9.2 Compose

```sh
swift tools/compose_appstore_screenshots.swift
```

It reads `appstore-screenshots/raw/`, writes `appstore-screenshots/<family>/`,
prints one line per board and exits non-zero listing any raw capture it
couldn't find or that isn't at its family's native resolution. `--input` and
`--output` override both roots if you want to try a set somewhere else — either
spelling (`--input /tmp/raw` or `--input=/tmp/raw`); anything else it doesn't
recognise stops the run instead of quietly falling back to the defaults.

Each board is the brand gradient, the two caption lines in white, and the
capture below with rounded corners and a shadow. **Captions are data**: the
`shots` table at the top of the script is the one place to edit them. Keep them
short (they auto-shrink to fit, which is a safety net, not a licence), keep the
tutoiement, and keep the vocabulary the app uses — « sortie » is the noun for
what the user does, « séance » is reserved for a HealthKit workout record.
Each board carries its French `lines` and its `english` ones; « outing » and
« recap » are the English words for « sortie » and « bilan », as in the app.

### 9.3 Upload

**Actions → Store screenshots → Run workflow** (`.github/workflows/store-screenshots.yml`,
lane `screenshots`), with the version string. It creates its own iPhone and
Apple Watch simulators, captures both sets in French then in English, composes
the boards and keeps them
as the `store-screenshots` artifact. Run it once with « publish » unticked and
look at the artifact; run it again ticked, with that run's id in « boards_from_run », to publish exactly those boards in place of the version's screenshots
in App Store Connect. It never uploads a binary or the listing, and never
submits.

The lane reads the boards from `appstore-screenshots/`, so a set composed on a
Mac goes up the same way (`fastlane screenshots`, with the App Store Connect
key of step 6 in the environment):

| App Store Connect tab | Folder | Uploaded as |
|-----------------------|--------|-------------|
| iPhone 6.9" Display | `appstore-screenshots/iphone-6.9/` | `iphone-01_home.png` … |
| iPad 13" Display | `appstore-screenshots/ipad-13/` | `ipad-01_home.png` … |
| Apple Watch | `appstore-screenshots/watch/` | `watch-01-today.png` … |

The English boards go up the same way from `appstore-screenshots/en-US/` to
the English (U.S.) localization; the lane stops if either language is missing.

deliver files each board under its tab by its size and orders a tab by file
name, so the numbers are the store order. The first three are what shows on
the product page without scrolling, and App Store Connect takes ten per tab at
most: the composer refuses an eleventh. On CI the watch boards show the
runner's hour (UTC) in the corner, where watchOS draws its clock.
Screenshots are only needed at promotion (step 10), never for TestFlight.

## 10. Promote to the public App Store

TestFlight is the release's final step on purpose: the store gets a build only
when you run the submission and approve it.

1. Nothing to write for « What's New »: the workflows take it, as plain
   text, from the notes the release needed, `docs/releases/X.Y.Z.md` in
   French and `X.Y.Z.en.md` in English, and stop when either is missing.
2. Upload the **screenshots** (step 9.3) when the set has changed.
3. Wait until TestFlight has processed the tag's build.
4. **Actions → App Store submission → Run workflow**, with the tag (e.g.
   `v1.55.0`). The run waits for the approval of the `app-store` environment;
   approve it from the run page. It then writes the listing (§ 10.1) as it is
   on `main`, attaches the tag's build (the same commit count as the release)
   and submits the version for review.
5. Once Apple approves, the version goes out by itself as a **phased release**
   over 7 days (1 %, 2 %, 5 %, 10 %, 20 %, 50 %, 100 % of the users with
   automatic updates; anyone can update by hand from the first day). Pause it,
   or release to everyone, in **App Store Connect → Distribution → Phased
   Release** when something goes wrong or right.

The **Store listing** workflow still writes the listing alone, without
submitting, to prepare a version ahead of its build.

A notable feature also gets a featuring nomination, filed weeks before the
publish date: see [LAUNCH.md](LAUNCH.md#1-featuring-nominations), with the
campaign links used to announce it.

### 10.0 The `app-store` environment (once)

**Settings → Environments → New environment**, named `app-store`:

- **Required reviewers**: yourself. Without one, GitHub creates the
  environment on the first run with no protection, and the submission starts
  without approval.
- **Deployment branches and tags**: *Selected branches and tags*, with the
  branch rule `main`, so that the run uses the reviewed workflow. The tag
  to submit is the input, not the branch the run starts from.

The secrets stay those of the repository (step 7): the environment only gates
the job.

### 10.1 The listing lives in the repository

The listing is versioned in [`fastlane/metadata/`](../fastlane/metadata/)
(issue #581), one text file per field. To change it, edit the file in a PR and
run the workflow. A change made directly in App Store Connect is overwritten
the next time the workflow runs.

| File (`fr-FR/`) | Field | Limit |
|-----------------|-------|-------|
| `name.txt` | App name | 30 characters |
| `subtitle.txt` | Subtitle | 30 characters |
| `keywords.txt` | Keywords, comma-separated, no spaces | 100 bytes |
| `promotional_text.txt` | Promotional text | 170 characters |
| `description.txt` | Description | 4000 characters |
| `support_url.txt`, `privacy_url.txt`, `marketing_url.txt` | URLs (getfoulee.app) | https |

`en-US/` holds the same files in English (issue #592), written for the US
store. Its URLs point at the French pages until the site has English ones
(getfoulee/web#36).

The name and the subtitle are indexed for search as well as the keywords, so
`keywords.txt` does not repeat their words. Search already covers « marche »
and « course » through the name, and « podomètre », « série » and « habitude »
through the subtitle. The keywords add what is left: Apple Watch, Garmin, the
goal, the reminders, hydration. The count is in bytes, so each accented letter
takes two.

[`tools/check_store_metadata.py`](../tools/check_store_metadata.py) checks all
of this. It runs in the CI **Store listing** job, on every pull request that
touches the listing, and again before the workflow uploads anything:

```sh
tools/check_store_metadata.py
```

The workflows (`.github/workflows/store-listing.yml`, lane `metadata`, and
`.github/workflows/app-store.yml`, lane `submit`) use the same App Store Connect
key as the release (step 6), with no binary and no screenshots: those go
through the release and step 9.3.

## 11. The Garmin watch app (separate store, separate cadence)

The Connect IQ app in [`FouleeConnectIQ/`](../FouleeConnectIQ/README.md) goes to
the **Connect IQ Store**, not App Store Connect, and is versioned independently
of the `v*` tags. Its own workflow,
[`garmin-release.yml`](../.github/workflows/garmin-release.yml), runs on
`garmin-v*` tags:

```sh
git tag garmin-v1.0.0-beta1 && git push origin garmin-v1.0.0-beta1   # beta store entry
git tag garmin-v1.0.0       && git push origin garmin-v1.0.0         # production
```

It validates the project, builds the signed `.iq` for every device of the
manifest and attaches it to a GitHub release (a pre-release for a beta),
titled « Garmin X.Y.Z » so the website can leave it out, and never marked
« Latest », which stays on the app's release. Garmin
offers no upload API, so uploading that `.iq` on
<https://apps.garmin.com/developer/upload> stays a browser step; the job summary
lists it. Listing copy, images, the beta channel and the ERA crash-report loop:
[`FouleeConnectIQ/store/README.md`](../FouleeConnectIQ/store/README.md).

Every PR compiles the Monkey C too (`Connect IQ build`). Secrets and variable:

| Name | Kind | Value |
|---|---|---|
| `CIQ_SDK_TOKEN_BASE64` | secret | base64 of `~/.Garmin/ConnectIQ/token.json`, from an SSO login (never a password) |
| `CIQ_AGREEMENT_HASH` | variable | hash of the accepted Connect IQ developer agreement |
| `CIQ_DEVELOPER_KEY_BASE64` | secret | base64 of `$HOME/.garmin/foulee_developer_key.der`, release only |

Setup of the first two: [`FouleeConnectIQ/README.md`](../FouleeConnectIQ/README.md),
« Intégration continue ».

## Troubleshooting

- **"Cloud signing permission error" / "No profiles … were found"** — almost
  always the API key role: it must be **Admin** (step 6), not App Manager.
  Failing that, an App ID from step 2 is missing or lacks a capability —
  register/fix it and `-allowProvisioningUpdates` creates the profile next run.
- **"The build number must be higher"** — shouldn't happen (commit count only
  grows), but if you rewrote history, push an empty commit to bump it.
- **First upload rejected for missing privacy policy** — complete step 4.
