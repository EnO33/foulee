# ADR 0001 — Routes d'intégration Garmin

- **Statut** : acceptée (2026-08)
- **Issues** : [#179](https://github.com/EnO33/foulee/issues/179) (épic), [#180](https://github.com/EnO33/foulee/issues/180)

## Contexte

Foulée doit fonctionner pour un utilisateur qui porte une montre **Garmin** au lieu (ou en plus) d'une Apple Watch. La contrainte fondatrice de l'app cadre toute la décision :

> **Invariant non négociable** : la promesse *device-only / zéro backend* — les données de santé ne quittent jamais les appareils de l'utilisateur. Toute route d'intégration qui l'enfreint est disqualifiée d'office, quels que soient ses autres mérites.

Second fait structurel : le streak repose sur `appleExerciseTime`, un type HealthKit **en lecture seule** — ni Garmin ni aucune app tierce ne peut l'écrire, et un iPhone sans Apple Watch n'en génère **aucun échantillon** (source : doc Apple HealthKit, vérifiée 07/2026). Pour un utilisateur Garmin-only, chaque jour vaudrait 0 minute : ce n'est pas un bug de synchro, c'est structurel, et aucune route d'intégration ne peut le contourner côté Garmin.

## Options étudiées

Recherche et contre-vérification menées en 07/2026 — les citations datées figurent dans chaque option ci-dessous ; le détail du raisonnement est dans l'issue #180 et l'épic #179.

| Route | Verdict | Pourquoi |
|---|---|---|
| **Garmin Connect → Apple Santé** (native, gratuite) | ✅ **Phase 1** | Garmin Connect iOS écrit dans Santé : pas, distance, étages, FC quotidienne, calories actives/repos, workouts (sans tracé GPS), sommeil, poids, **eau bue**. Foulée lit déjà tout ça. Zéro dépendance Garmin, zéro backend. Limites : `appleExerciseTime` inaccessible (cf. contexte) ; synchro par rafales quand l'utilisateur ouvre Garmin Connect (minutes → parfois 24 h — constaté massivement en forums, non documenté officiellement). |
| **Connect IQ Companion App** (app Monkey C sur la montre + Companion App SDK iOS) | ✅ **Phase 2** | La seule route Garmin *device-to-device* : SDK iOS v1.8.x standalone en Swift Package (`github.com/garmin/connectiq-companion-app-sdk-ios`), BLE direct montre↔iPhone ; Garmin Connect Mobile requis uniquement pour l'autorisation initiale de l'appareil. L'app montre lit `ActivityMonitor.Info` — dont **`activeMinutesDay`**, l'équivalent Garmin natif des minutes d'exercice, exactement la métrique du streak. Service d'arrière-plan ≥ 5 min pour pousser des instantanés quotidiens. SDK et store gratuits. |
| **Garmin Health API** (cloud) | ❌ Rejetée | Server-to-server par construction (push/ping vers une URL de callback obligatoire) → exigerait un backend Foulée et ferait transiter les données de santé par deux clouds : violation directe de l'invariant. En plus : programme réservé aux entreprises, et **candidatures suspendues depuis mi-2026** (confirmé par l'équipe GCDP en forum). Les frais historiques de 5 000 $ n'existent plus (FAQ officielle Garmin, vérifiée 07/2026) — sans incidence, la route reste disqualifiée. |
| **Garmin Health SDK** (Companion/Standard BLE, licencié) | ❌ Rejetée | Techniquement compatible no-backend (BLE direct), mais licence entreprise négociée (« license fee or minimum device order quantity ») — hors de portée d'une app indé gratuite. |

Précédent rassurant : **StepsApp** et **Gentler Streak** font exactement le choix de la phase 1 (ingestion 100 % Apple Santé, aucune API Garmin), avec une politique de support assumée : « données manquantes = problème de synchro Garmin↔Santé, pas un bug de l'app ».

## Décision

1. **Phase 1 — Garmin Connect → Apple Santé.** Aucune dépendance Garmin, aucun code spécifique à une marque : Foulée continue de lire HealthKit, qui fusionne déjà les sources. Livrable sans app Connect IQ.
2. **Phase 2 — Connect IQ Companion App.** Seule voie device-to-device pour gagner la fraîcheur (indépendante des ouvertures de Garmin Connect) et les minutes actives natives Garmin (`activeMinutesDay`). Les issues de la phase 2 (#187–#190) référencent le présent ADR comme décision cadre.
3. **Les routes cloud (Health API) et sous licence entreprise (Health SDK) sont rejetées** — la première viole l'invariant device-only, les deux sont de toute façon inaccessibles à une app indépendante gratuite.

## Conséquences

- **La définition des « minutes actives » devient source-agnostique** ([#181](https://github.com/EnO33/foulee/issues/181)) : puisque `appleExerciseTime` ne peut jamais exister sans Apple Watch, le streak doit accepter des minutes dérivées d'autres échantillons (workouts, pas) — c'est le prérequis commun aux deux phases.
- La synchro en rafales de la phase 1 impose des verdicts de jour **réparables après coup** (#182).
- Aucune donnée de santé ne transite par un serveur : la politique de confidentialité reste inchangée sur le fond (mise à jour éditoriale suivie dans #186).
- La validation de bout en bout (phase 1 comme phase 2) exige une **montre physique** — aucun simulateur ne couvre ni la chaîne Garmin Connect → Santé, ni le canal BLE iOS (#191).
