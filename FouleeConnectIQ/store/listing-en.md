# Connect IQ Store listing — English

Ready to paste into the form at <https://apps.garmin.com/developer/upload>.
Don't rewrite it there: this file is the reference, the form is the copy.

The store listing is bilingual on purpose. The watch app follows the watch's
language (English, or French on a French watch); **the iPhone app is French
only**, and the English description says so rather than pretending otherwise.

---

## Name

```
Foulée
```

## Short description

```
The watch companion to Foulée: today's counters, sent to your iPhone.
```

## Full description

```
Foulée is an iPhone app that helps you keep a daily lunchtime walk streak
going. This Connect IQ app is its watch companion.

IT DOES NOT WORK ON ITS OWN. Without Foulée installed on your iPhone, it shows
today's counters and records your sessions, nothing more: the streak, the
goals, the reminders, the weather and the history all live on the phone.

WHAT IT DOES
• Shows your streak, then today's steps and active minutes against your
  goals, distance and calories, in Foulée's colours; streak and minutes also
  in the glance, on devices that support glances.
• Starts a walk or a run from the wrist: clock, distance, pace, heart rate,
  a vibration at every kilometre, pause, then Save or Discard. The watch
  records it itself and it lands in Garmin Connect like your other
  activities.
• Sends five of today's values to your iPhone every five minutes, whenever the
  phone is in range: steps, distance, active minutes, vigorous active minutes,
  calories — plus the time of the reading, the time your day started on the
  watch and three technical markers (message type, payload version, send
  counter). During a session, every ten seconds, where it stands for the
  iPhone's screen: walk or run, time, duration, distance, steps, heart rate,
  paused, ended. At the end of a session, its summary: walk or run, start,
  end, duration, distance, steps. For each glass logged, its time, volume and
  identifier. Nothing else leaves the watch. Out of range it simply
  waits for the next pass — no error message, no battery drain.

WHAT IT DOES NOT DO
• No account, no sign-up, no settings.
• Nothing is sent over the internet. The watch talks to your iPhone, full stop.
• No notifications. No GPS outside a session.

WHY IT EXISTS
Your Garmin watch measures intensity minutes an iPhone on its own never sees.
Sending them straight across lets Foulée keep your streak as faithfully as it
would with an Apple Watch, without waiting for the next Garmin Connect sync.

BATTERY
The watch wakes every five minutes, reads those five values, and only transmits
if they moved — about a hundred bytes. No GPS, no sensor powered up, no screen
lit. GPS and the heart-rate sensor only turn on during a session.

LANGUAGE
The watch app speaks English, or French on a watch set to French. The
iPhone app is in French.

PRIVACY
Foulée is a local app: nothing goes to a server of ours, there is no account to
create, and nothing is sold to anyone.
Full policy: https://github.com/EnO33/foulee/blob/main/docs/privacy.md

SUPPORT
Questions and bugs: https://github.com/EnO33/foulee/issues
Answered within a week, in French or English.
```

## Notes to reviewer

```
This app is the watch companion to an iPhone app (Foulée). It reads
ActivityMonitor.getInfo() and transmits five integers to the phone over
Communications: steps, distanceCm, activeMinutes, activeMinutesVigorous,
calories (plus "ts", a timestamp, "day", the start of the watch's local day,
"gen", a send counter, "t", the message type, and "v", the payload schema
version). At the end of a saved session it also transmits its summary ("t" =
"summary": sport, start, end, duration, distance, steps), and during the
session, every ten seconds, its state ("t" = "session": sport, time, duration,
distance, steps, heart rate, paused, ended). For each glass logged, it
transmits the glass ("t" = "water": identifier, time, volume), which the
iPhone writes to Apple Health. Nothing else is read or transmitted, and it
contacts no server.

It also records walks and runs with ActivityRecording (permissions Fit,
Positioning, Sensor): GPS and the heart-rate sensor are only on during the
session, and the activity is saved to Garmin Connect as a native one.
Position is not sent to the phone; the current heart rate is, in the session
state only, for the iPhone's screen.

The iOS channel cannot be demonstrated in the Connect IQ simulator, which only
relays companion traffic to Android (ADB). With no iPhone paired, the app just
displays today's counters and transmits nothing.
```

## Other fields

| Field | Value |
|---|---|
| Category | Health & Fitness |
| App type | Watch App |
| Website / support | <https://github.com/EnO33/foulee/issues> |
| Privacy policy | <https://github.com/EnO33/foulee/blob/main/docs/privacy.md> |
| Price | Free |
| ANT+ | No |
