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
| `com.eno33.foulee` | HealthKit, WeatherKit |
| `com.eno33.foulee.widget` | HealthKit |
| `com.eno33.foulee.liveactivity` | _(none)_ |
| `com.eno33.foulee.watchkitapp` | HealthKit |
| `com.eno33.foulee.watchkitapp.widget` | HealthKit |

> `com.eno33.foulee` was likely already created when you first built with
> WeatherKit. The four extension/Watch IDs probably aren't yet — Xcode can
> also create them the first time you build with automatic signing, but
> registering them up front makes the CI build deterministic.

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
Location data. Host a short policy somewhere stable (GitHub Pages works) and
paste the URL in App Store Connect.

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

```sh
# bump the tag; the workflow reads the version from it
git tag v0.1.0
git push origin v0.1.0
```

Watch **Actions → Release**. After it's green, the build shows up in
**App Store Connect → TestFlight** within a few minutes (processing time).
Add it to an internal testing group to install via the TestFlight app.

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
└── watch/
```

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
runs the `FouleeScreenshots` UI-test target and exports the ten PNGs into
`appstore-screenshots/raw/iphone-6.9/`. About two minutes, unsupervised, no
Health data to enter by hand.

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
  on 26.5 renders all ten PNGs differently. That is why the script refuses a
  simulator name shared by two available devices and asks for a UDID instead —
  reproducibility that depends on which runtimes happen to be installed is not
  reproducibility.
- `appstore-screenshots/` is **not tracked by git** (issue #72) and must stay
  that way. `raw/` is the capture output; the boards are composed from it.

#### Apple Watch — one command

```bash
tools/capture_screenshots.sh --watch                                    # 46 mm
tools/capture_screenshots.sh --watch "Apple Watch SE 3 (40mm)" probe-40  # a probe
```

Same script, same result bundle, same export; another platform, another scheme
(`FouleeWatchScreenshots`) and another folder — the three PNGs land in
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
    narrowly: every differing pixel on all three boards falls in
    **x 306…383, y 39…63 counted from the bottom** — the clock glyphs, 1 098 of
    206 336 pixels — and nowhere else. (The count moves with which digits
    changed; the box does not.) Restate the criterion when closing: *identical
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
  entirely, with nothing to scroll: **a session could not be stopped**.
  `WatchActiveWalkView` is a scroll view now, so its content starts below the
  system time like the home's does. If a future watch screen draws large text
  across the top, check it on the 40 mm probe before capturing.
- **The watch is uninstalled first**, which clears its app-group container, so
  « Démarrer » starts a session outright instead of asking which activity. That
  question depends on what the phone last synced; the uninstall is what keeps
  the third capture from depending on the developer's own wrist.

#### iPad — still by hand

Not automated: the iPad set is the iPhone app running on an iPad, so it belongs
to the iOS target rather than to a size class of its own. Create the tree once
— `appstore-screenshots/` is gitignored, so a fresh clone has nowhere to write
and `simctl io` fails with `No such file or directory`:

```sh
mkdir -p appstore-screenshots/raw/ipad-13
```

Then, per device:

```sh
xcrun simctl boot "iPad Pro 13-inch (M4)"
xcrun simctl status_bar "iPad Pro 13-inch (M4)" override --time 09:41 \
  --cellularBars 4 --wifiBars 3 --batteryState charging --batteryLevel 100
xcrun simctl io "iPad Pro 13-inch (M4)" screenshot appstore-screenshots/raw/ipad-13/02_home-ipad.png
```

The file names the composer expects are the `file:` values in its `shots`
table — `02_home-ipad`, `04_streak-ipad`, and so on.

Three rules for a hand-taken capture, each of them a defect the previous set
actually shipped (the third one binds the automated sets too — it is why the
watch capture scrolls to the bottom, which clamps, rather than to a card):

- **Never crop, never resize a raw capture.** The composer scales the whole
  thing to fit; anything you shave off by hand shows up as a wrong aspect ratio.
- **A sheet drags its dimmed parent in with it.** A modal presented over a
  dimmed screen leaks a grey band above itself into the grab. Capture the sheet
  full-screen if you can; otherwise shave the band explicitly with `trimTop:`
  on that shot rather than cropping the PNG. The iPhone sheets already do this
  — see `sheetDimBand`, whose value was measured rather than guessed. **That
  number is 6.9"-specific**: re-measure against an iPad capture instead of
  reusing it.
- **Park scrolling screens on a boundary.** Leave the scroll where a card edge —
  not a button cut in half — meets the bottom of the display. Screens flagged
  `scrolls: true` also get a short fade into the background, so what remains
  reads as "there's more below" instead of a bad crop.

  One board knowingly breaks the *top* half of that rule, and it is a choice
  rather than an oversight: `watch-02-hydration` scrolls to the clamped bottom
  of the watch home, and the window that lands there begins mid-tile — the
  bottom sliver of the stats grid, two orphan « km » and « kcal » labels above
  the hydration card. The fade only softens the bottom of a board, so nothing
  hides it. The alternative is parking the scroll partway up, and a partial
  scroll is exactly what is not reproducible: only the clamped end gives the
  same pixels whatever the swipe momentum did. Reproducibility wins; if that
  ever stops being true, reframe the shot rather than leaving both broken.

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

### 9.3 Upload

App Store Connect → your app → the version → **Media Manager**, one tab per
size class:

| Tab | Folder | Required |
|-----|--------|----------|
| iPhone 6.9" Display | `appstore-screenshots/iphone-6.9/` | yes |
| iPad 13" Display | `appstore-screenshots/ipad-13/` | yes — the app runs on iPad |
| Apple Watch | `appstore-screenshots/watch/` | yes — the app ships a Watch app |

Order matters: the first three are what shows on the product page without
scrolling. Screenshots are only needed at promotion (step 10), never for
TestFlight.

## 10. Promote to the public App Store (manual, when you're ready)

TestFlight is the CI's final step on purpose — promotion to the store stays a
deliberate, manual action:

1. App Store Connect → your app → **+ Version**, set the version string.
2. Attach the processed build.
3. Fill the listing: description, keywords, support URL, **screenshots**
   (step 9), age rating, category.
4. **Submit for Review**.

> The full listing is only needed at this promotion step, not for TestFlight.
> If you later want CI to submit for review too (via `fastlane deliver` with
> versioned metadata/screenshots), that's a small follow-up to the `release`
> lane.

## 11. The Garmin watch app (separate store, separate cadence)

The Connect IQ app in [`FouleeConnectIQ/`](../FouleeConnectIQ/README.md) is not
part of this pipeline. It goes to the **Connect IQ Store**, not App Store
Connect, it is versioned independently of the `v*` tags, and nothing here
builds it — the Connect IQ SDK can't be installed on a GitHub runner without a
Garmin *account* password, so the compile gate stays on the developer's
machine. The full reasoning is in that README, under « Intégration continue ».

What CI does check on every PR is the `Connect IQ` job: manifest, device matrix,
launcher icon sizes and that the manifest still carries the *production* app id
(a beta package needs a different one), via `FouleeConnectIQ/build.sh validate`.
It does **not** compile the Monkey C — a green CI says nothing about that.

Publishing is `./build.sh package` (→ `bin/foulee.iq`) then an upload at
<https://apps.garmin.com/developer/upload>; the listing copy, the required
image sizes, the beta channel and the ERA crash-report loop are all in
[`FouleeConnectIQ/store/README.md`](../FouleeConnectIQ/store/README.md).

No new GitHub secret is needed today. If a Monkey C compile is ever wired into
CI it will want `CIQ_DEVELOPER_KEY_BASE64` (base64 of
`$HOME/.garmin/foulee_developer_key.der`) alongside Garmin account credentials
— the exact recipe, and why it isn't enabled, are in the Connect IQ README.

## Troubleshooting

- **"Cloud signing permission error" / "No profiles … were found"** — almost
  always the API key role: it must be **Admin** (step 6), not App Manager.
  Failing that, an App ID from step 2 is missing or lacks a capability —
  register/fix it and `-allowProvisioningUpdates` creates the profile next run.
- **"The build number must be higher"** — shouldn't happen (commit count only
  grows), but if you rewrote history, push an empty commit to bump it.
- **First upload rejected for missing privacy policy** — complete step 4.
