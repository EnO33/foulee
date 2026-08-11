# ADR 0002 — Détection automatique marche / course

- **Statut** : acceptée (2026-08)
- **Issues** : [#244](https://github.com/EnO33/foulee/issues/244) (épic), [#248](https://github.com/EnO33/foulee/issues/248), [#249](https://github.com/EnO33/foulee/issues/249), [#250](https://github.com/EnO33/foulee/issues/250), [#246](https://github.com/EnO33/foulee/issues/246), [#247](https://github.com/EnO33/foulee/issues/247), [#256](https://github.com/EnO33/foulee/issues/256)

## Contexte

Depuis #216, Foulée enregistre marche **et** course. Le sport d'une séance était choisi par l'utilisateur : une préférence globale (`ActivityMode`), et une question au démarrage pour le mode « les deux » (#224).

Demande d'origine : *« lancer l'activité au début et ne plus s'en soucier jusqu'à l'arrivée »*. Donc une détection **muette** — aucune question au départ, aucune confirmation à l'arrivée.

Deux faits cadrent tout le reste :

1. **`HKWorkout` est immuable et Foulée n'appelle jamais `HKHealthStore.delete`.** Un sport mal enregistré l'est définitivement.
2. **Le téléphone n'écrit aucun échantillon d'énergie** (ils double-compteraient le total du jour, cf. `HealthKitClient+Live`). `WalkSession.estimatedCalories` — pas × `kcalPerStep`, **0,04 en marche contre 0,09 en course** — est donc la seule donnée d'énergie qu'une séance téléphone portera jamais.

Une erreur de classification est ainsi **invisible, coûteuse et définitive** à la fois.

## Décisions

### D1 — CoreMotion en direct au poignet, en différé sur le téléphone

`CMMotionActivityManager` ne délivre **rien pendant qu'une app est suspendue** (documenté), et un téléphone en poche l'est en quelques secondes. Les deux plateformes emploient donc des mécanismes opposés :

| | Mécanisme | Pourquoi |
|---|---|---|
| **Apple Watch** | `startActivityUpdates` pendant la séance | Une `HKWorkoutSession` active maintient l'app en vie. |
| **iPhone** | `queryActivityStarting(from:to:to:)` à l'arrêt | Rend la liste **complète** des transitions après coup : la segmentation est plus exacte qu'un flux live, sans tâche de fond ni batterie. |

Mesuré sur appareil (#248) : la reconnaissance fonctionne au poignet, latence **< 30 s**. Batterie non mesurée.

### D2 — Une seule définition de « ce que dit une estimation »

`MotionActivityReading` (`Foulee/Motion/`) est compilé dans **les deux cibles**. La montre classe en direct, le téléphone relit après coup, mais la règle est unique :

- Les drapeaux de `CMMotionActivity` **ne sont pas mutuellement exclusifs et peuvent être tous faux**. `if walking … else if running` est faux par construction : il préfère silencieusement la marche au moment où l'appareil est le moins sûr. **Exactement un** de marche/course doit être levé.
- Confiance sous `.medium` → aucune preuve. Un niveau que l'app ne sait pas nommer non plus.

Deux plateformes en désaccord sur une même estimation donneraient un bug inexplicable : la montre affichant « Course » au poignet pendant que le téléphone classe la même sortie en marche.

### D3 — Toujours du côté qui sous-crédite

Chaque cas ambigu retombe sur **marche**, le taux le plus bas : drapeaux illisibles, confiance faible, appareil muet, égalité parfaite entre les deux durées. Même principe que `GarminSnapshotOverlay` : jamais une source de minutes que personne n'a gagnées.

### D4 — La détection ne contredit pas une réponse déjà donnée

Elle ne tranche **qu'en mode « les deux »**. Un mode « Marche » ou « Course » est un choix explicite, et le contredire sur-créditerait (0,09 contre 0,04) de façon permanente.

Corollaire livré avec #246 : le **sélecteur de #224 disparaît côté téléphone** — la question n'a plus lieu d'être posée puisque l'appareil y répond. Il reste **sur la montre**, qui fige son `activityType` à la création de la `HKWorkoutSession` et ne peut pas y revenir.

### D5 — Le libellé et le coût sont deux questions distinctes

Le sport enregistré respecte le choix de l'utilisateur (D4) ; les **calories** sont estimées au taux de chaque portion, quel que soit le mode (#247). Quelqu'un qui a réglé « Marche » et couru vingt minutes garde son libellé et a quand même couru : les facturer au taux de la marche serait faux.

Deux refus délibérés : une sortie **homogène** n'est pas ventilée (elle donnerait exactement le même chiffre — non-régression volontaire sur le cas courant), et une portion que le podomètre refuse de chiffrer annule **toute** la ventilation (un total partiel n'est pas une vérité plus petite, c'est un total faux).

### D6 — Rien n'est nommé avant d'être su

Pendant une séance « les deux » non encore tranchée, l'écran de séance et l'écran verrouillé disent **« Ta sortie »**. Nommer « Ta marche » pendant toute une sortie pour enregistrer « Course » à la fin serait pire que la dérive de #225 : l'écran aurait eu tort du début à la fin.

## Ce qui s'est révélé impossible

### Segmenter une séance par `HKWorkoutActivity`

Le plan initial (#250) était que chaque portion soit une sous-activité de la séance, HealthKit fournissant alors les statistiques par sport (`allStatistics`, `statisticsForType:`) sans aucun calcul de notre part.

**Deux versions livrées sur TestFlight, deux sorties perdues.** L'appareil a fini par répondre :

```
Cannot add subactivity of type HKWorkoutActivityTypeRunning
```

sur une séance dont le type est `.walking`. Les sous-activités existent pour le **multisport** — `HKWorkoutActivityTypeSwimBikeRun` et `HKWorkoutActivityTypeTransition` sont les types faits pour les porter. Une séance mono-sport n'en accepte aucune d'un autre sport. **Rien dans l'en-tête de `beginNewActivityWithConfiguration:date:metadata:` ne le dit.**

Et le parent multisport est disqualifié : sortir de {walking, running} ferait disparaître la séance du résumé 7 jours (`WorkoutActivityFilter`, régression corrigée par #217) et changerait ce que Santé en dit.

> ⛔ **Ne jamais retenter `beginNewActivity` avec un sport différent de celui de la séance.**

Conséquence : la montre **affiche** le sport en cours mais ne peut pas le **chiffrer**. Les stats par sport de #250 n'ont pas de source par ce chemin.

### La leçon, qui vaut plus que la cause

Les deux hypothèses successives — session pas encore démarrée, activité principale qu'on tentait de terminer — étaient **fausses toutes les deux**. Ce qui a débloqué le problème n'est pas une meilleure analyse : c'est d'avoir enfin **affiché le message d'erreur**.

Il existait depuis toujours. `handleSessionFailure` le rangeait dans `lastError`, rendu **uniquement sur l'écran d'accueil** — que `reset()` vide en y allant. La seule information qui tranchait était produite puis jetée, et l'utilisateur l'avait sous les yeux sans que l'app la lui montre.

> **Afficher l'erreur d'abord, corriger ensuite.** Sur un chemin qu'aucun simulateur ne peut exercer, un correctif de diagnostic doit précéder tout correctif de comportement.

## Piste restée ouverte

L'app **Forme** enchaîne marche → course dans une même sortie et en produit un récap. La question non tranchée : Santé contient-il alors **un** entraînement multisport, ou **deux** entraînements consécutifs ?

Si c'est deux, Foulée peut faire pareil — terminer la séance de marche et en ouvrir une de course à la bascule, chacune restant dans {walking, running}, chacune correctement étiquetée, #245 rendant les deux lignes lisibles dans le résumé. Ce serait une autre conception, pas un correctif.

## Réglages, et ce qui les gouverne

| Réglage | Valeur | Raison |
|---|---|---|
| Seuil de confiance | `.medium` | Trop strict → la détection se tait et la séance reste ce qu'elle était (aucune donnée abîmée). Trop laxiste → un sport faux, définitif. |
| Confirmations avant bascule (montre) | **1** | L'hystérésis à 2 protégeait un segment permanent dans Santé. Ce segment n'existe plus (#256), donc attendre n'achetait plus rien et ajoutait des secondes à la latence propre de CoreMotion. **À remonter si la segmentation redevient possible.** |
| Repli | marche | Voir D3. |

## Vérification restant à faire sur appareil

- Qu'une sortie marche → course aille **jusqu'au bout** au poignet.
- La latence réelle des transitions côté iPhone : tapis, poussette, descente rapide.
- Le coût en batterie du flux au poignet, toujours non mesuré depuis #248.
