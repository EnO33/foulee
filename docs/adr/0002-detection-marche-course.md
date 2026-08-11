# ADR 0002 — Détection automatique marche / course

- **Statut** : acceptée (2026-08)
- **Issues** : [#244](https://github.com/EnO33/foulee/issues/244) (épic), #248, #249, #250, #246, #247, #256, #265, #266, #267

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

### D7 — Un changement de sport ouvre une nouvelle séance

Une séance HealthKit enregistre **un** sport (voir la section suivante). Un second sport a donc besoin d'une **seconde séance** : à la bascule, la montre termine celle en cours et en ouvre une autre. Santé reçoit une marche *et* une course, chacune correctement typée, chacune restant dans {walking, running}.

C'est ce que fait **Forme** quand on ajoute une activité à la main — constaté par l'utilisateur, et c'est cette observation qui a débloqué la conception.

Trois propriétés font tenir le découpage :

- **La coupure porte la date de la frontière**, pas celle où on l'apprend. `endCollection(at:)` et `startActivity(with:)` acceptent une date passée, donc la marche se termine là où la course a commencé, sans trou entre les deux.
- **Une portion de moins de 15 s ne devient pas une séance** (`WatchWorkoutStore.minimumLegDuration`). Seuil choisi avec l'utilisateur : il préfère trier un workout de trop que perdre la justesse d'une frontière.
- **Un échec ne coûte jamais ce qui précède** : chaque portion terminée est sauvée *avant* que la suivante soit tentée. Si celle-ci ne peut pas s'ouvrir, la sortie se termine avec la raison à l'écran — moins coûteux qu'une séance qui continue en n'enregistrant rien.

Les compteurs affichés totalisent la **sortie**, pas la portion : le builder d'une nouvelle portion repart de zéro, et sans ce cumul l'écran se remettrait à zéro à chaque changement de sport.

### D8 — L'écran et l'enregistrement n'avancent pas à la même vitesse

Renommer l'écran ne peut pas échouer et s'autocorrige à la lecture suivante : c'est **immédiat**. Couper la sortie écrit un workout **permanent** : ça **attend** que le nouveau sport tienne.

Attendre ne coûte aucune précision, puisque la coupure est datée de la frontière (D7). C'est ce qui permet d'avoir à la fois un écran réactif et un enregistrement prudent, sans arbitrer entre les deux.

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

Conséquence à l'époque : la montre affichait le sport en cours sans pouvoir le chiffrer. **Résolu depuis par D7** — chaque portion étant une séance à part entière, ses chiffres sont ceux de son propre builder.

### La leçon, qui vaut plus que la cause

Les deux hypothèses successives — session pas encore démarrée, activité principale qu'on tentait de terminer — étaient **fausses toutes les deux**. Ce qui a débloqué le problème n'est pas une meilleure analyse : c'est d'avoir enfin **affiché le message d'erreur**.

Il existait depuis toujours. `handleSessionFailure` le rangeait dans `lastError`, rendu **uniquement sur l'écran d'accueil** — que `reset()` vide en y allant. La seule information qui tranchait était produite puis jetée, et l'utilisateur l'avait sous les yeux sans que l'app la lui montre.

> **Afficher l'erreur d'abord, corriger ensuite.** Sur un chemin qu'aucun simulateur ne peut exercer, un correctif de diagnostic doit précéder tout correctif de comportement.

## Le multisport, écarté — et pas pour la raison qu'on croyait

Première objection avancée : « un parent multisport ferait sortir la séance du résumé 7 jours ». Elle était **circulaire** — `WorkoutActivityFilter.summarizedActivityTypes` est un fichier de ce dépôt, y ajouter `.swimBikeRun` est une ligne. L'utilisateur l'a relevé.

Les objections qui tiennent :

1. **Le type est figé à la création de la session.** Pour pouvoir basculer il faudrait démarrer *toutes* les séances en multisport, y compris les marches pures — qui seraient alors étiquetées « Multisport » dans Santé, définitivement.
2. **Rien ne prouve que `swimBikeRun` accepte marche et course.** L'appareil nous a appris qu'un parent `walking` refuse une sous-activité `running` ; il n'a rien dit du parent multisport.
3. **Le crédit `appleExerciseTime`** sur un workout multisport n'est pas documenté, et toute la série en dépend.

Et la question qui a tout tranché — *Forme produit-il un multisport ou deux entraînements ?* — a reçu sa réponse par l'observation : **deux entraînements consécutifs**. Apple n'utilise donc pas non plus les sous-activités pour ça, et la voie était D7.

## Réglages, et ce qui les gouverne

| Réglage | Valeur | Raison |
|---|---|---|
| Seuil de confiance | `.medium` | Trop strict → la détection se tait et la séance reste ce qu'elle était (aucune donnée abîmée). Trop laxiste → un sport faux, définitif. |
| Confirmations avant bascule (montre) | **1** | L'anti-bruit est assuré par le seuil de 15 s de D7, qui décide seul si une portion mérite une séance. Confirmer deux fois ajouterait des secondes à la latence sans rien protéger de plus. |
| Durée minimale d'une portion | **15 s** | En dessous, une portion est plus courte que l'écart entre deux lectures : du bruit, pas une observation. Le chiffre à monter si un fractionné découpe trop. |
| Source rapide de la détection | cadence + vitesse | CoreMotion répond en ~30 s et son lissage *est* sa raison d'être (#248). Les compteurs de la séance donnent une cadence en quelques secondes, sans capteur ni permission de plus. CoreMotion reste l'arbitre. |
| Repli | marche | Voir D3. |

## Ce qui a été constaté sur appareil

| Version | Résultat |
|---|---|
| `v1.38`, `v1.39` | ⛔ La bascule **tuait la séance**. C'est `v1.39`, affichant enfin l'erreur, qui a livré la cause. |
| `v1.41` | Plus d'erreur, la transition se fait, la montre nomme le sport. Restaient un chrono par à-coups et une détection lente. |
| `v1.42` | ✅ « La détection fonctionne mieux en effet. » Chrono fluide. Une seule séance encore — attendu à ce stade. |
| `v1.43` | ✅ **Le découpage fonctionne.** Une sortie qui change de sport laisse deux séances. |

## Ce qui reste non mesuré

- **La batterie** du flux au poignet, toujours pas mesurée depuis #248.
- La latence des transitions côté **iPhone** dans les cas tordus : tapis, poussette, descente rapide.
- Le comportement sur un **fractionné** : le seuil de 15 s de D7 est le réglage prévu pour ça, jamais éprouvé.
- **Les seuils de cadence sont personnels** (`MovementClassifier`). Réglés pour une allure ordinaire ; un marcheur très rapide ou un joggeur très lent tombent dans la zone grise.
