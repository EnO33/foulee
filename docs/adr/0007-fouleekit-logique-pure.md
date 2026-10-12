# ADR 0007 — FouleeKit : la logique pure dans un framework testé sur macOS

- **Statut** : acceptée (2026-10)
- **Issues** : [#425](https://github.com/EnO33/foulee/issues/425)

## Contexte

Le job iOS passe environ 7 minutes sur l'étape « Test (iOS) », alors que les tests eux-mêmes tournent en une quinzaine de secondes. Le reste sert à installer et lancer le test host, l'app Foulée entière avec l'app montre embarquée, dans le simulateur iOS 27. Le job watchOS paie le même prix.

La plupart de ces tests portent pourtant sur de la logique pure : modèles, calculs, formats. Cette logique n'a besoin ni d'UIKit, ni de HealthKit, ni d'un simulateur.

Le code partagé entre les cibles était compilé plusieurs fois. Chaque extension et l'app montre listaient, dans `Project.swift`, les fichiers de `Foulee/Shared/` dont elles avaient besoin, avec leurs dépendances transitives. Un oubli dans une liste ne se voyait qu'à la compilation de la cible concernée.

## Décisions

### D1 — Un framework `FouleeKit`, compilé pour iOS, watchOS et macOS

- **Contenu** : les modèles et la logique pure partagés, sous `FouleeKit/Sources/`.
- **Consommateurs** : l'app, la montre, les widgets et la Live Activity l'importent (`import FouleeKit`) au lieu de compiler les mêmes fichiers.
- **macOS ne sert qu'aux tests.** Aucune app Mac n'est prévue.
- **Le framework n'importe que ce qui existe sur les trois plateformes** : Foundation, `os`, CoreLocation. SwiftUI, HealthKit, ActivityKit et AppIntents restent hors du kit.

### D2 — Ses tests tournent sur macOS, sans simulateur

- **`FouleeKitTests`** (Swift Testing) tourne sur le runner lui-même, dans le job CI « Kit ». Il n'y a ni simulateur à démarrer ni app hôte à installer.
- **`FouleeTests` et `FouleeWatchTests`** gardent ce qui a besoin de l'app : stores, vues, intégrations système.
- **La cible macOS est signée en local** (`CODE_SIGN_IDENTITY = -`). Elle ne demande aucune équipe, ni en CI ni sur un Mac de développeur.

### D3 — L'API du kit est `public`, et rien de plus

- Ce qu'une autre cible utilise est `public`. Une structure construite hors du kit déclare son initialiseur `public`, car Swift ne rend pas public l'initialiseur memberwise.
- Le reste garde sa visibilité. Les tests du kit utilisent `@testable import FouleeKit`.
- **Isolation** : le kit n'active pas le main actor par défaut (ADR 0006). Ses types sont `nonisolated`, comme l'exige la règle pour les données et la logique pure.

### D4 — Une migration par étapes

1. **Cette étape** : les fichiers de `Foulee/Shared/` qui ne dépendent que de Foundation, `os` et CoreLocation, avec les fichiers dont ils dépendent (`ActivityMode`, `Coordinate`, `MotionActivityReading`, `HydrationNotification`, `ActiveMinutes`), et leurs tests.
2. **Ensuite** : les calculs de l'app, dossier par dossier, une PR par dossier.
   - **Health** : les modèles et calculs de `Foulee/Health/` qui ne dépendent pas de HealthKit (résumés et détail de sortie, regroupement, déduplication, métriques, surcouche Garmin), avec `GarminDailySnapshot` qu'utilise la surcouche, et `Int.formattedFR`, qui part de `TodayHeroCard` vers `NumberFormatting`. Les clients HealthKit et les extensions qui lisent un `HKWorkout` restent dans l'app.
   - **Recap** : le Bilan (`Recap`, `RecapPeriod`, `RecapWater`, `OutingDay`), avec `Weekday` (Preferences) et `HydrationMath` (Hydration) qu'il utilise. Restent dans l'app le store et la carte de partage, qui dessine en SwiftUI.
   - **Streak** : le calcul de la série (`StreakCalculator`) et son calendrier (`StreakCalendar`, `StreakMonth`, `CalendarDay`, `WeekdayStat`). Le store du calendrier et ses vues restent dans l'app.
   - **Preferences** : `TimeOfDay`, l'heure et les plages horaires des réglages. `UserPreferences` reste dans l'app : c'est un store `@Observable` adossé à `UserDefaults`. `ThemeMode` aussi, qui importe SwiftUI.
   - **Walk** : `WalkSession`, la séance en cours et son estimation d'énergie. Restent dans l'app `ActiveWalkStore`, les clients `Pedometer` et `Altimeter` (swift-dependencies, CoreMotion) et `WalkActivityAttributes` (ActivityKit).

Restent listés dans `Project.swift`, parce qu'ils dépendent d'un framework absent de macOS ou de l'état de l'app :

| Fichier | Raison |
| --- | --- |
| `LogWaterIntent` | App Intent, déclarée dans chaque processus qui l'exécute |
| `WalkActivityAttributes` | ActivityKit |
| `SessionActivity+HealthKit` | HealthKit |
| `ActivityPalette`, `SessionActivity+Tint`, `MetricPalette` | SwiftUI |
| `RouteRecorder` | état du main actor, CoreLocation en direct |
| `ScreenshotSeedCore` | mode capture, Debug seulement |

## Règle pour le code à venir

- **Un modèle, un calcul ou un format qui ne dépend que de Foundation** : dans `FouleeKit/Sources/`, avec ses tests dans `FouleeKitTests/`.
- **Un type d'interface, un store, un client système** : dans l'app ou la montre.
- **Avant d'ajouter un fichier à une liste de `Project.swift`**, vérifier s'il a sa place dans le kit.
- **En déplaçant un fichier vers le kit** :
  - retirer son `import FouleeKit`, sinon il s'importe lui-même ;
  - ne rendre `public` que ce que l'app utilise, sinon Periphery le signale ;
  - une valeur par défaut d'une fonction publique ne peut nommer qu'un membre `public` ou `@usableFromInline`, jamais un membre `private`.

## Conséquences

- **Les tests de logique pure ne paient plus le lancement du simulateur.** Le gain sur la durée de la CI grandit à chaque dossier déplacé.
- **Un ajout à l'API partagée demande un `public`.** Le compilateur signale l'oubli dès la première cible qui l'utilise.
- **Periphery indexe aussi le kit et ses tests** (schéma `FouleeKit`). Le job iOS compile ces tests pour macOS, uniquement pour alimenter l'index.
