# Privacy Policy — Foulée

_Last updated: October 29, 2026_

Foulée is a **local** app. It helps you keep up a streak of outings — walks or
runs — from your activity data. **No data is sent to any server of ours, and
there is no account to create.** Everything stays on your devices: your iPhone,
your Apple Watch, and your Garmin watch if you install Foulée's Connect IQ app
on it.

## Health data (HealthKit)

With your permission, Foulée **reads** from the Health app: your steps, your
distance, your exercise minutes, your active calories, your heart rate, the
water you drank, your workouts and their routes. This data is used only to show
your statistics and your outings in the app, and to work out your streak. The
Hydration screen also shows each of the day's glasses with the name of the app
that logged it in Health.

Foulée also **writes** to the Health app, if you want it to: your outings (as
workouts, with their route when they are recorded on the Apple Watch) and the
water you log in the hydration tracker. When you **undo a glass**, Foulée
deletes from Health the entry it has just written, and only that one: Health
does not let an app delete data written by another.

This health data **never leaves your device**: it is neither passed on to a
third party nor stored anywhere other than Apple's Health app, which you fully
control.

## Garmin watches

If you wear a Garmin watch, your data reaches Foulée **through the Health
app**, like all the rest: Garmin Connect writes it there, and Foulée reads it on
your device, whatever its source.

Foulée **never talks to Garmin's servers**: no Garmin account sign-in, no
Garmin API, no exchange with any server — neither ours nor Garmin's. The
promise stays the same — your health data **never leaves your devices**.

### The Foulée app for Garmin watches (Connect IQ)

Foulée also offers a small app to install **on the watch itself**, from the
Connect IQ Store. It is optional: without it, everything keeps working through
the Health app, as described above.

**What it reads on the watch** — only the day's counters the watch already
keeps (`ActivityMonitor`): your steps, your distance, your active minutes, your
vigorous active minutes and your calories. Outside a session, no GPS, no heart
rate, no sensor switched on for the occasion.

**During a session you start on the watch** — the watch records the activity
itself, with its own recorder, like its sports apps: duration, distance, **GPS
position** and **heart rate**. GPS and the heart rate sensor are only on from
"Start" to "Save" or "Discard". A saved session goes to **Garmin Connect** like
any other activity from your watch, and Garmin Connect writes it to Health; a
discarded session leaves no trace. Of your position, Foulée's watch app keeps
only the session's route, thinned out, for your iPhone (see below): it stays on
the watch only until the iPhone receives it.

**During the session**, when your iPhone is in range, it also sends it, every
ten seconds as well as on pause, resume and finish, where the session stands:
walk or run, time of the reading, duration, distance, steps, **current heart
rate**, paused or not, finished or not. The iPhone shows it on its session
screen and does not keep it once the session is over. Only the "finished" state
waits until the iPhone has received it, so that its screen does not stay open.

**What it sends** — a snapshot of these **five values**, plus the time of the
reading, the time your day starts on the watch (to count the values on the
right day when the watch and the phone are not in the same time zone), the
message type, the format's version number and a send number that lets the
iPhone ignore a snapshot it has already received. All of it goes **straight to
your iPhone over Bluetooth**, at most once every five minutes, and **only if
these values have changed** since the last send. When the phone is out of
range, the watch sends nothing and simply waits for the next chance.

**At the end of a saved session**, it also sends its summary: walk or run, start
and end time, duration, distance, ascent and descent, steps and **the session's
route**, reduced to 64 points at most. The iPhone uses it to show the outing and
its map until Garmin Connect writes it to Health, which receives it without a
route. The summary waits on the watch until the iPhone has received it (along
with session ends and glasses, the last thirty-two messages at most); heart rate
is not part of it. The iPhone keeps the route with the pending outing, and
forgets it along with it.

**When you tap "Log a glass"** in the watch's menu, it sends the glass: its
time, its amount and an identifier. The watch cannot write to Health: the
iPhone writes it there, with that identifier, so that a glass received twice
only counts once.

**On your watch face**, if you add the "Foulee streak" complication, the watch
shows your streak. The complication is public, like the watch's own: any
installed watch face can read it. It does not leave the watch.

**What it receives** — from your iPhone, over the same Bluetooth link: your
streak, your step and minute goals, your walk / run choice and your hydration
settings (on or off, goal, glass size). That is what the Apple Watch already
receives. During a session, if you tap "Stop the session" on the iPhone, the
watch also receives the order to save it. The watch keeps the last state it
received to show it when the phone is out of range.

**What it does not send** — nothing goes to Garmin's servers, nor to ours (we
have none). There is no account to create in this app, no setting, and nothing
is stored anywhere but on the watch and on your iPhone.

Once on the iPhone, these values follow exactly the same path as the others:
they are used to show your statistics and work out your streak, and stay on
your device.

**It is of no use without the iPhone app.** Installed on its own, it only shows
your day's counters on the watch.

## Location

With your permission ("while using the app"), Foulée uses your location for two
things, and never anything else:

- showing the **weather** where you are, on the iPhone;
- drawing your outing's **route** on a map, on the iPhone or on the Apple
  Watch — **during the outing only**. On the watch, your location is only asked
  for when an outing starts and is no longer read once the outing is over. The
  same goes for a **Garmin watch**: GPS is only on during a session, and the
  route stays in the activity recorded by the watch (see "Garmin watches").
  During an outing started on the watch, its route is also sent to **your
  iPhone**, directly between your two devices, to show it on the session's map.
  The other way round, during an outing started on the iPhone, its route and
  figures (duration, steps, distance, calories) are sent to **your Apple
  Watch**, directly between your two devices, to show them on your wrist.

For the weather, your coordinates are sent to **Apple WeatherKit**, which
returns the local conditions (see
[Apple's privacy policy](https://www.apple.com/legal/privacy/)).

The route of an outing made with the **Apple Watch** is saved **in the Health
app**, with the workout, as Apple's Fitness app does: that is what lets you see
it again on a map in Foulée, in Fitness or in any app you give access to Health.
It stays on your devices, in Health, which you fully control, and is sent to no
one. The route traced by the iPhone, for its part, is not kept after the outing.

## Motion and fitness

Foulée uses the **pedometer** (CoreMotion) to count your steps live during your
outing and, on the **Apple Watch**, to read your current cadence and pace: they
are shown on your wrist and help tell whether you are walking or running. This
data is processed locally, in real time.

With your permission, Foulée also reads the system's **motion detection** to
tell on its own whether you are walking or running:

- on the **Apple Watch**, during the session, to show the current sport;
- on the **iPhone**, once only, **when the session stops**, by reading back the
  history of the outing that has just ended — nothing is read while you walk,
  and nothing runs in the background.

In both cases, the reading is used to save your outing under the right sport in
Health. Nothing is sent, nothing is kept outside the session itself.

During a session, the **barometer** of the iPhone and the Apple Watch measures
the elevation you climb and the elevation you descend. Only these two totals
are kept: they are saved with the session in Health, like its distance.

## What Foulée does not do

- ❌ No account, no sign-up, no email address collected.
- ❌ No analytics tool, no third-party tracker, no advertising.
- ❌ No selling or sharing of your data.

## Preferences

Your settings (goal, activity, window, theme, reminders) are stored **locally**
on your device. Uninstalling the app deletes them.

The **summary** of the last 7 days and of the month is worked out on your
iPhone, from the Health data Foulée already reads. Its notification is
scheduled locally: nothing is sent anywhere to produce it.

The **notification that follows a session** arriving from a watch is worked out
the same way: your iPhone compares the outing with those of the last six months,
read from Health, and schedules the notification itself. Nothing leaves your
iPhone to write it.

When you **merge two outings**, Foulée remembers on your iPhone which workouts
make up one, and nothing else: Health is not changed, and the merge does not
leave your iPhone. Splitting the outings erases that link.

## Diagnostics

On the iPhone, Foulée receives from iOS (MetricKit) the reports of its own
crashes, hangs and slow launches. It keeps ten at most, for a month at most,
**on your iPhone**. These reports describe how the app runs — version, device
model, iOS version, technical traces — and contain **no health data and no
location**.

**Nothing leaves on its own.** In Settings › About, "Report a problem" shows
you the summary before anything is sent:

- "Open a report" opens an issue on GitHub, which is **public**, with the
  summary (version, device, date and type of each incident) if you leave
  "Attach the summary" on. You review it and send it yourself, from your
  GitHub account.
- "Share the full report" opens the iOS share sheet with the summary and the
  technical traces: you choose whom to send it to, privately.

Uninstalling the app deletes these reports.

## Apple privacy manifest

The app and its extensions (widgets, Watch app) ship a **privacy manifest**
(`PrivacyInfo.xcprivacy`), Apple's standard format for declaring what an app
does with your data. Foulée's declares:

- **no tracking** and no tracking domain;
- **no data collected** — nothing leaves your device;
- a single use of a so-called "required reason" API: **local preferences**
  (UserDefaults), used for your settings and shared between the app and its
  widgets through an app group, always on your device.

## Your choices

Since everything is local, you stay in control at any time from **iOS
Settings**:

- **Privacy & Security → Health → Foulée** for access to health data;
- **Privacy & Security → Location Services → Foulée** for location, on the iPhone as on the Apple Watch;
- **Notifications → Foulée** for reminders.

Deleting the app erases all the preferences it stored. The data in the Health
app remains managed by Health.

## And this website?

getfoulee.app is hosted by **Cloudflare**. To know how many people visit it, it
uses **Cloudflare Web Analytics**, an audience measurement **without
cookies**:

- nothing is stored in your browser, neither cookies nor local storage;
- neither your IP address nor your browser is used to recognize you from one
  visit to the next;
- only totals are kept: page views, the site you came from, country, type of
  device and browser, load time.

What you do on the website is never linked to the app, which still sends
nothing.

## Contact

A question about this policy? Write to **contact@getfoulee.app**.

_This policy is also available [in French](privacy.md)._
