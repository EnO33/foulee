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
- **Location** — used while in use (midday weather + walk route).

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

## 9. Promote to the public App Store (manual, when you're ready)

TestFlight is the CI's final step on purpose — promotion to the store stays a
deliberate, manual action:

1. App Store Connect → your app → **+ Version**, set the version string.
2. Attach the processed build.
3. Fill the listing: description, keywords, support URL, **screenshots**
   (6.9" iPhone + Apple Watch are the required sizes), age rating, category.
4. **Submit for Review**.

> Screenshots and the full listing are only needed at this promotion step, not
> for TestFlight. If you later want CI to submit for review too (via
> `fastlane deliver` with versioned metadata/screenshots), that's a small
> follow-up to the `release` lane.

### Regenerating the screenshots

```bash
tools/capture_screenshots.sh                       # iPhone 6.9" (1320 × 2868)
tools/capture_screenshots.sh "iPhone 17 Pro" iphone-6.3
tools/capture_screenshots.sh 02175924-56FF-…-0216  # by UDID
```

The script boots the simulator, pins its status bar to 09:41 / full bars /
charged, runs the `FouleeScreenshots` UI-test target and exports the ten PNGs
into `appstore-screenshots/raw/<set>/`. It takes about two minutes and needs no
supervision — there is no Health data to enter by hand any more.

What makes it repeatable is the **capture mode** (issue #235): the target
launches the app with `-FouleeScreenshotMode`, which swaps every `@Dependency`
client for a deterministic double and freezes the clock at Thursday 14 May
2026, 14:35. Two runs on two different days, **on the same simulator**, produce
byte-identical files — that is checked by running it twice and comparing
checksums. The numbers live in `Foulee/Screenshots/ScreenshotSeed.swift`;
`FouleeTests/ScreenshotSeedTests` holds them consistent (the 34-day streak on
the card really is what the seeded history computes).

Four things worth knowing:

- The mode is **compiled out of Release builds** — everything under
  `Foulee/Screenshots/` and its single call site in `FouleeApp.init()` are
  inside `#if DEBUG` — and inside a Debug build it still needs the explicit
  launch argument. `FouleeTests/ScreenshotModeTests` asserts a normal launch
  doesn't activate it.
- A capture run **leaves nothing behind**. The doubles write no `HKWorkout`, no
  `dietaryWater` and no Connect IQ session, so capturing a session records
  nothing in Santé; the preferences and the widget app group are both diverted
  into throwaway suites, so the fabricated counters never reach the widgets;
  and the Watch push is muted. `ScreenshotModeTests` checks each of those, the
  HealthKit one at the source — no file under `Foulee/Screenshots/` may name an
  `HKHealthStore`.
- The **runtime is part of the output**: the same device model on iOS 26.0 and
  on 26.5 renders all ten PNGs differently. That is why the script refuses a
  simulator name shared by two available devices and asks for a UDID instead —
  reproducibility that depends on which runtimes happen to be installed is not
  reproducibility.
- `appstore-screenshots/` is **not tracked by git** (issue #72) and must stay
  that way. `raw/` is the capture output; the finished marketing boards are
  composed from it separately.

Not automated: the three Apple Watch captures and the five iPad ones. The watch
app has no capture mode of its own, and the iPad set was taken with the iPhone
app running on an iPad — both are still done by hand.

## 10. The Garmin watch app (separate store, separate cadence)

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
