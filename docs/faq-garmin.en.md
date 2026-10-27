# FAQ — Foulée with a Garmin watch

Foulée works with a Garmin watch through the native **Garmin Connect → Apple
Health** sync: your watch sends your data to the Garmin Connect app, which
writes it to the Health app, where Foulée reads it — all of it on your device.
Foulée never talks to Garmin's servers (see the
[privacy policy](privacy.en.md)).

## Turn on sharing (first connection)

The connection starts **from Garmin Connect**, not from Health.

1. Open **Garmin Connect**, **"More"** tab.
2. Tap **"Settings"**, then **"Connected Apps"**.
3. Tap **"Apple Health"**.
4. Tap **"Connect with Apple Health"**.
5. iOS then shows its **Health permission sheet**: **turn on the
   categories** — steps, distance, workouts, heart rate, calories, and water
   if you track your hydration.

Labels may vary from one version of Garmin Connect to the next: Garmin has
renamed this menu several times ("Third-Party Apps", "Connect Apps"). The path
stays the same: the settings, then the connected apps.

### Check or fix it, on the Health side

Once connected, everything can also be set from the Health app — those labels
are Apple's and do not move:

1. Open **Health**, **Summary** tab.
2. Tap your **photo or initials**, at the top right.
3. Under **"Privacy"**, tap **"Apps"**.
4. Tap **"Garmin Connect"** (the app is also called **"Connect"** in some
   places) in the list.
5. **Check the categories**: steps, distance, workouts, heart rate,
   calories — and water if you track your hydration.

If you had tapped "Don't Allow" on the permission sheet, this is where you fix
it: Garmin Connect does not offer it again.

### Garmin Connect is not in that list

That is normal as long as the connection has never been made: an app appears in
that list **once it has asked for access**, whatever your answer was — never
before. Hence the diagnosis:

- **It is not there** → the connection was never made. Go through "Turn on
  sharing" above again, in Garmin Connect.
- **It is there** → the request has already happened. Everything is set in
  Health, even if you had declined, without going back to Garmin Connect.

## My data for today does not show up (or shows up late)

This is by far the most common case, and Garmin documents it: **the Garmin
Connect app has to be open in the foreground to send data to Health.** Allow
**a few minutes** before your data arrives (about 5 in our tests): it is not
instant, and many people conclude too quickly that nothing works. If the app is
closed, the transfer is paused and only finishes at the next sync, with the app
open. Until then, your data stays on Garmin's side and Health (so Foulée) does
not see it.

**The fix: open Garmin Connect.** The sync starts, the data reaches Health, and
Foulée updates at the next refresh. Good news: if minutes arrive after the
fact, your streak is **repaired retroactively** — a day completed late still
counts.

## Can I try it without a watch?

Yes. The data you enter **by hand** in Garmin Connect (a glass of water, an
activity created manually) goes to Health exactly like a watch's — Foulée makes
no difference, since it reads Health and never Garmin. It is the simplest way to
check that your connection works: enter an activity, leave Garmin Connect open
for a few minutes, and watch the minutes ring move.

## My streak does not count even though I walked

If your steps are there but your streak will not count the day, your walk was
probably **not recorded as an activity**.

Apple's "exercise minutes" only exist if you wear an Apple Watch: no third-party
app, Garmin included, can write them — Garmin even states that its data does not
move Apple's rings. So Foulée replaces them with the **duration of your recorded
activities** — every sport, not only walking. That is what lets a Garmin watch
move your streak forward.

The consequence: a walk your watch only counted as steps gives no minutes.
**Record your walk as an activity** on the Garmin (start the "Walk" activity
before you set off), or turn on **automatic activity detection** in your watch's
settings so that it creates it on its own. Once the activity has synced to
Health, the day counts — retroactively too.

## My history from before installing is empty

Not quite: **when sharing is turned on, Health imports your Garmin data from the
previous two weeks**. Beyond that, though, nothing comes back — Garmin Connect
does not copy your full history. This is a limit of Garmin Connect, shared by
every app that reads Health, and Foulée cannot work around it: your statistics
build up from there.

## My steps are counted twice (watch + iPhone)

If you wear your Garmin while keeping the iPhone in your pocket, both count your
steps. The Health app knows how to remove duplicates, but it follows a **source
priority order**. Good news: a newly added source is placed **above all the
others**, so a freshly connected Garmin already comes before the iPhone.

To check or change that order: open **Health → Browse → Activity → Steps →
Data Sources & Access**, then tap **Edit** and move your preferred source
(Garmin Connect or iPhone) to the top of the list. Foulée reads Health's
deduplicated totals and so reflects this setting.

## When data is missing

**Our support policy is simple: data missing from Foulée is almost always a
Garmin ↔ Health sync problem, to check first — not a bug in the app.** The
test: open the Health app and look for the missing data. If it is not there,
Foulée cannot show it — go through "Turn on sharing" and "Check or fix it, on
the Health side" above again, then open Garmin Connect to start a sync. If it is
there but not in Foulée, first check that it is not about exercise minutes (see
"My streak does not count even though I walked": they come from your recorded
activities, not from your steps) — otherwise, write to us:
**contact@getfoulee.app**.

_This FAQ is also available [in French](faq-garmin.md)._
