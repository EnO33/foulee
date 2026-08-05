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
- **L'agrégation multi-sources reste déléguée à HealthKit** ([#183](https://github.com/EnO33/foulee/issues/183)) : audit fait — tous les totaux passent par `HKStatisticsQuery`/`HKStatisticsCollectionQuery`, jamais par une somme manuelle d'échantillons.
- Aucune donnée de santé ne transite par un serveur : la politique de confidentialité reste inchangée sur le fond (mise à jour éditoriale suivie dans #186).
- La validation de bout en bout (phase 1 comme phase 2) exige une **montre physique** — aucun simulateur ne couvre ni la chaîne Garmin Connect → Santé, ni le canal BLE iOS (#191).

## Annexe — Spike Connect IQ Companion App SDK iOS (#187)

- **Statut** : go — le SDK s'intègre proprement, sans compromis sur la promesse device-only.
- **Version intégrée** : `github.com/garmin/connectiq-companion-app-sdk-ios` 1.8.0.

### Ce que le spike a établi

Le paquet est un **Swift Package à cible binaire** (`ConnectIQ.xcframework`, iOS uniquement, `arm64` + simulateur). Il se déclare comme les autres dépendances SPM du dépôt, dans `packages:` de `Project.swift`, et n'est lié qu'à la cible iPhone : les extensions widget, la montre Apple et sa complication n'y touchent pas. Trois réglages sont obligatoires et faciles à oublier :

1. `-ObjC` dans `OTHER_LDFLAGS` de la cible app — le SDK utilise des catégories Objective-C ; sans ce drapeau l'éditeur de liens les jette et le crash n'arrive qu'à l'exécution.
2. `LSApplicationQueriesSchemes` doit contenir `gcm-ciq`, sinon le SDK conclut toujours que Garmin Connect Mobile est absent.
3. `NSBluetoothAlwaysUsageDescription` (le guide du SDK nomme encore la clé `…Peripheral…`, dépréciée depuis iOS 13 — les deux sont déclarées).

**Swift 6.2 strict concurrency** : aucune friction bloquante. L'API est Objective-C non annotée, donc `@preconcurrency import ConnectIQ` et confinement de tous les types du SDK (`IQDevice`, `IQApp`, le singleton `ConnectIQ`) dans un seul fichier ; la passerelle est un `@unchecked Sendable` avec un `OSAllocatedUnfairLock`, exactement le patron déjà utilisé par `PhoneWatchSync` pour `WCSession`. Rien du SDK ne franchit une frontière d'isolation : le décodage du message se fait dans le callback, et seule la valeur `Sendable` en sort. Compile sans nouvel avertissement ; la manifeste Tuist, en revanche, a dû voir son `Info.plist` d'app extrait dans une constante nommée — le littéral inline avait fini par dépasser le budget de typage du compilateur.

### Schéma de message — gelé

`{ "v", "steps", "distanceCm", "activeMinutes", "activeMinutesVigorous", "calories", "ts", "gen" }` — dictionnaire Connect IQ (`NSString`/`NSNumber`), pas du JSON. Unités calquées sur `Toybox.ActivityMonitor.Info` : distance en centimètres, minutes entières, calories en kcal. `ts` = secondes epoch UTC, `gen` = compteur montre incrémenté à chaque instantané, qui ordonne le flux (le BLE réordonne et redélivre). Le décodeur est tolérant par conception : clé inconnue ignorée, `v` inconnu ou absent → rejet complet, métrique absente ou mal typée → 0, valeur négative → 0, nombre non fini ou hors bornes → rejet ou saturation, jamais de piège. C'est la seule partie couverte par des tests, et elle l'est à fond.

### Ce qui reste invérifiable sans matériel

Honnêtement : **tout le canal BLE**. Le simulateur Connect IQ ne parle companion qu'à Android, et le simulateur iOS n'a pas de Bluetooth — donc rien de ce qui suit n'a été exécuté, seulement écrit d'après la documentation du SDK et TN3115 :

- l'aller-retour d'autorisation (`showConnectIQDeviceSelection` → Garmin Connect Mobile → retour par `foulee-ciq://`) ;
- la réception d'un message réel, et donc le décodeur sur un vrai instantané ;
- le réveil en arrière-plan : le mode `bluetooth-central` et l'identifiant de restauration `CBCentralManager` sont câblés (le SDK le passe lui-même à son `CBCentralManager` interne, et l'app initialise le SDK au démarrage du processus, pas à l'affichage d'un écran), mais **la fréquence réelle des réveils et leur survie à un `force quit` restent inconnues** ;
- le débit et la taille maximale utile d'un message (`BLE_REQUEST_TOO_LARGE` n'est pas documenté chiffré).

L'UUID de l'app Monkey C est un placeholder tant que #188 n'a pas généré le vrai : en pratique l'enregistrement des écouteurs ne matche donc aucun appareil aujourd'hui.

### Frontière assumée

Le spike s'arrête à « un instantané est arrivé et a été décodé ». Rien n'est écrit dans HealthKit ni dans l'instantané widget : fusionner ces données avec ce que Garmin Connect écrit déjà dans Santé, sans double comptage, est le sujet entier de #189.

## Annexe — Fusion des deux canaux Garmin (#189)

Une même journée Garmin arrive par deux canaux qui décrivent **la même activité** : Santé (écrit par Garmin Connect — tardif, granulaire, faisant foi) et l'instantané Connect IQ (frais à ≤ 5 min, mais total agrégé du jour). La règle retenue, implémentée dans `GarminSnapshotOverlay` et épinglée par tests :

1. **Rien n'est jamais écrit dans HealthKit depuis ce canal.** Garmin Connect synchronisera le même jour plus tard ; un échantillon écrit ici doublerait définitivement les données Santé de l'utilisateur, sans que Foulée puisse le reprendre. L'instantané ne vit que comme *overlay* local — même forme que l'overlay post-marche `PendingWalk`.
2. **Jamais d'addition : par métrique et par jour, un `max`.** Les minutes d'intensité Garmin et les workouts que Garmin Connect écrit dans Santé sont le plus souvent la même activité. Le `max` règle aussi gratuitement le porteur hybride : `appleExerciseTime` est déjà dans le terme HealthKit, donc un agrégat Garmin périmé ne peut jamais remplacer un chiffre Apple plus élevé.
3. **Overlay horodaté et périssable.** Deux gardes indépendantes : le **jour local** de `ts` (un instantané de 23 h 50 a vingt minutes à 00 h 10 et décrit pourtant un jour terminé — c'est le bug de #144, #152, #203) et un **horizon de fraîcheur** écrit comme `GarminFreshness.staleAfter / 2` (soit 2 h aujourd'hui) : l'overlay doit cesser d'accepter de nouveaux totaux bien avant que l'app ne déclare elle-même la journée en retard. La relation est épinglée par test, pour qu'un réglage de `staleAfter` ne laisse pas dériver un littéral.
4. **Les compteurs ne redescendent jamais : plancher journalier à haute eau.** Passé l'horizon, la contribution ne disparaît pas — la dernière contribution utilisable reste un **plancher horodaté au jour local** (`GarminSnapshotOverlay.Floor`). Sans cela, à H+2 l'app, le groupe d'app et les widgets republient un total Santé seul, souvent 0 chez un utilisateur Garmin dont Connect n'a pas encore synchronisé : un compteur qui *décroît* est pire qu'un compteur figé. Le plancher n'est jamais additionné, il est abandonné dès que Santé le dépasse (aucun verrou : le `max` est réévalué à chaque passe), et il meurt à minuit local comme tous les overlays de ce dépôt (#144, #152, #203). L'horizon ne décide donc que d'une chose : si un instantané est assez frais pour **relever** le plancher.
5. **Minutes actives dédoublées.** `ActivityMonitor.ActiveMinutes.total` compte les minutes *d'intensité* (vigoureux compté double) ; `appleExerciseTime` compte l'horloge. On retranche donc la part vigoureuse. En cas d'incohérence, on sous-crédite : cet overlay ne peut être qu'un plancher sous Santé.
6. **Calories exclues de la fusion.** `Info.calories` de Garmin est une dépense *totale* (métabolisme de base inclus), là où Foulée affiche `activeEnergyBurned`. Un `max` entre les deux ne double-compterait pas : il afficherait simplement un chiffre faux.
7. **Discipline de publication par jambe conservée** (#200/#201) : l'overlay chevauche la jambe « métriques ». Une lecture Santé refusée ne publie rien — une valeur mesurée par la seule montre n'atteint jamais seule le groupe d'app, les widgets ou la Watch.
8. **Fraîcheur widgets** : ce canal n'écrit aucun échantillon Santé, donc aucun observer ne se déclenche. Le rechargement est explicite mais **ciblé** (`reloadTimelines(ofKind:)` sur les widgets de compteurs), conditionné à un compteur qui a réellement bougé **et throttlé à `WidgetRefresh.daytimeStepMinutes`** : la montre n'émet que *parce que* ses métriques ont bougé, donc « les compteurs ont changé » est vrai à presque chaque envoi et ne peut pas être la seule garde — le budget WidgetKit est de ~40-70 rechargements par jour. Seul le rechargement est rationné ; l'écriture dans le groupe d'app, elle, a toujours lieu.
9. **Le processus widget fusionne, il ne remplace pas.** `WidgetLiveMetrics.freshSnapshot()` relit HealthKit en direct quand le téléphone est déverrouillé ; ces lectures sont fusionnées par `max` avec l'instantané partagé (`WidgetSnapshot.mergingLiveCounters`). Sans cela le widget écraserait à chaque rendu un overlay qu'il ne peut pas voir — il ne parle pas BLE — et afficherait des chiffres inférieurs à ceux de l'app, à la même seconde.
10. **Le franchissement d'objectif en arrière-plan reste sur une échelle Santé pure.** `snapshot.minutes` du groupe d'app portant désormais l'overlay, l'arête « objectif franchi » de `BackgroundStreakRefresh` se juge contre `lastMeasuredMinutesToday` — les minutes *mesurées* du dernier réveil, horodatées au jour — et non contre l'instantané partagé, qui la consommerait avant que Santé ne l'ait jamais franchie.

### Limite connue, non corrigée : fuseaux divergents

Le jour local est décidé côté téléphone, à partir de `ts` (epoch UTC). Si la montre et le téléphone sont dans des fuseaux différents — montre restée à l'heure du départ après un vol, ou changée manuellement — leurs minuits ne coïncident pas : la montre peut agréger une journée qui n'est pas celle que Foulée affiche, et l'écart peut aller jusqu'à quelques heures de compteurs sur le mauvais jour. Corriger cela demande que la montre envoie son propre début de journée local (ou son décalage UTC), donc un **schéma v2** — le schéma est gelé et partagé mot pour mot avec #188. Considéré, écarté ici : la garde jour local côté téléphone reste la bonne approximation, et la fenêtre d'erreur est bornée par l'horizon de fraîcheur.

**Hors périmètre de #189** : la publication de l'app montre sur le store Connect IQ (#190), l'hydratation depuis la montre, le streak (dont l'historique reste dérivé de Santé — un streak adossé à un overlay de deux heures apparaîtrait et disparaîtrait au gré de la portée BLE) et toute UI au-delà des chiffres déjà affichés.
