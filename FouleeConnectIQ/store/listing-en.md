# Connect IQ Store listing — English

Ready to paste into the form at <https://apps.garmin.com/developer/upload>.
Don't rewrite it there: this file is the reference, the form is the copy.

The store listing is bilingual on purpose; **the app itself is French only**
(`<iq:language>fre</iq:language>` in the manifest, like the iPhone app). The
English description says so rather than pretending otherwise.

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
today's counters and nothing more: the streak, the reminders, the weather and
the history all live on the phone.

WHAT IT DOES
• Shows today's steps, distance and active minutes on the watch; steps and
  active minutes also in the glance, on devices that support glances.
• Sends five of today's values to your iPhone every five minutes, whenever the
  phone is in range: steps, distance, active minutes, vigorous active minutes,
  calories — plus the time of the reading and two technical markers (payload
  version, send counter). Nothing else leaves the watch. Out of range it simply
  waits for the next pass — no error message, no battery drain.

WHAT IT DOES NOT DO
• No account, no sign-up, no settings.
• Nothing is sent over the internet. The watch talks to your iPhone, full stop.
• No activity recording, no GPS, no notifications.

WHY IT EXISTS
Your Garmin watch measures intensity minutes an iPhone on its own never sees.
Sending them straight across lets Foulée keep your streak as faithfully as it
would with an Apple Watch, without waiting for the next Garmin Connect sync.

BATTERY
The watch wakes every five minutes, reads those five values, and only transmits
if they moved — about a hundred bytes. No GPS, no sensor powered up, no screen
lit.

LANGUAGE
The iPhone app and the on-watch labels are in French.

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
calories (plus "ts", a timestamp, "gen", a send counter, and "v", the payload
schema version). Nothing else is read or transmitted, and it contacts no
server.

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
