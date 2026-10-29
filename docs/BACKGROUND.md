# Reading the background wakes

The widgets, the watch complication and the hydration reminders stay current
only because iOS wakes Foulée in the background. iOS decides when it does,
and nothing in the app shows it. The `background` log category records every
wake, so "iOS never woke us" and "the wake ran but changed nothing" can be
told apart (issue #612).

The log never holds a health value. It records the type that woke the app, the
time the wake took, and the error when there is one.

## Where the logs are

**Console.app**, with the iPhone (or the watch, through its iPhone) plugged in
or on the same network:

1. Select the device in the sidebar and click **Start**.
2. In the search field, type `subsystem:com.eno33.foulee category:background`.
3. **Action → Include Info Messages** to also see the « prochain réveil
   demandé » and « observateurs Santé enregistrés » lines.

**Terminal**, for a simulator or a Mac connected to the device:

```sh
log stream --predicate 'subsystem == "com.eno33.foulee" AND category == "background"' --info
```

`notice` and `error` lines are kept on the device for a few days. To read a
past day, run `sudo log collect --device --last 1d` and open the
`.logarchive` it writes in Console.app. `info` lines are only kept while a
stream is open.

## What each line means

| Line | Where | Meaning |
|------|-------|---------|
| `observateurs Santé enregistrés` | iPhone | The three observers (steps, water, workouts) are registered. Once per process. |
| `observateur <type> : réveil` | iPhone | Health woke the app for that type. |
| `observateur <type> : terminé en N s` | iPhone | The widget snapshot was refreshed and the widgets reloaded. Comes after every `réveil`. |
| `observateur <type> : livraison refusée : …` | iPhone | `enableBackgroundDelivery` failed. Usually means Health access is denied. That type will never wake the app. |
| `observateur <type> : erreur : …` | iPhone | The observer fired with an error. Nothing was refreshed. |
| `rafraîchissement : réveil` | iPhone | The app-refresh task started. |
| `rafraîchissement : succès en N s` | iPhone | The task finished in time. |
| `rafraîchissement : temps écoulé, tâche annulée` | iPhone | iOS took the time back before the end. A `rafraîchissement : échec` line follows. |
| `rafraîchissement : prochain réveil demandé` | iPhone | The next task is requested, at least two hours away. Logged when the app goes to the background and at each task. |
| `rafraîchissement : demande refusée : …` | iPhone | iOS refused the request. It always does on the simulator, and when « Actualisation en arrière-plan » is off for Foulée. No task will run. |
| `Garmin : instantané reçu, widgets rechargés` | iPhone | The Garmin watch sent its counters (Connect IQ can relaunch the app in the background for this) and the counter widgets reloaded. |
| `Garmin : instantané reçu, widgets non rechargés` | iPhone | Same, but the counters did not move, or the widgets were reloaded less than the throttle ago. The snapshot is still updated. |
| `observateur eau (montre) : réveil, complication rechargée` | Watch | Water changed in Health and the hydration complication reloaded. |
| `observateur eau (montre) : livraison refusée : …` / `erreur : …` | Watch | Same meanings as on the iPhone. |

A workout mirrored from the watch also relaunches the iPhone in the
background, but it drives the Live Activity, not the widgets: its lines are
under the `session` and `live-activity` categories.

The type is HealthKit's identifier: `HKQuantityTypeIdentifierStepCount`,
`HKQuantityTypeIdentifierDietaryWater` or `HKWorkoutTypeIdentifier`.

## What to expect

- **At launch**, each observer fires once, right after it is registered. Those
  are not deliveries, and three `réveil` lines within a second are normal.
- **Steps**: at most one wake an hour, and often fewer. iOS clamps the
  frequency and skips wakes when the phone is locked, on low battery, or in Low
  Power Mode.
- **Water and workouts**: within seconds of a glass or an outing saved in
  Health, from any app or device. A glass logged on the watch reaches the
  iPhone only once Health has synced, which can take minutes.
- **App-refresh task**: a few times a day at best, never sooner than two hours
  after the previous request. iOS learns from how often the app is opened.
  None at all on a phone where Foulée is rarely used is normal, not a bug.
- **Duration**: a wake normally takes well under a second. Several seconds
  points at a slow Health read, usually the streak recompute after a workout.

## What a missing line tells you

- **No `réveil` for a type all day, with no `livraison refusée`**: iOS did not
  deliver. Check that Health access is granted for that type and that Low
  Power Mode is off.
- **No `rafraîchissement` line for days**: check « Actualisation en
  arrière-plan » in Réglages. An app swiped away from the app switcher gets no
  refresh task until it is opened again.
- **A `réveil` without a matching `terminé`**: the process was killed during
  the wake. If this repeats, the wake is too slow for its budget.
- **`rafraîchissement : échec` often**: the task runs out of time. The
  Health reads in `refreshWidgetSnapshotFromHealth()` are the place to look.
