# ADR 0009 — L'app Garmin devient une app de séance, au même rôle que l'Apple Watch

- **Statut** : acceptée (2026-10)
- **Issues** : [#464](https://github.com/EnO33/foulee/issues/464) (épic), [#474](https://github.com/EnO33/foulee/issues/474)
- **Remplace** : la décision 2 de l'[ADR 0001](0001-garmin-integration.md) sur un point, le rôle de l'app Connect IQ (« la montre est un capteur, pas une seconde app »). La phase 1 (Garmin Connect → Santé) et le canal d'instantanés de la phase 2 restent en vigueur.

## Contexte

L'app Connect IQ actuelle lit les compteurs du jour et les pousse vers l'iPhone. Un porteur de Garmin n'a donc ni « Démarrer », ni séance au poignet, ni série. Il a une expérience de Foulée plus pauvre que celle d'un porteur d'Apple Watch. L'objectif est la **même app sur les deux montres** : on ouvre Foulée au poignet, on voit sa série, on démarre une sortie, on la suit, on la retrouve sur l'iPhone.

Les faits qui cadrent les décisions :

1. **Connect IQ n'écrit pas dans Santé.** Seule l'app iPhone le peut. Une activité Garmin rejoint Santé par Garmin Connect, en différé (ADR 0001, phase 1).
2. **Le système de la montre sait enregistrer une activité.** `Toybox.ActivityRecording` crée une session FIT native : GPS, fréquence cardiaque, tours, pause, sauvegarde. La montre la synchronise elle-même avec Garmin Connect, comme une activité de l'app d'exercice native.
3. **Le lien vers l'iPhone est lent et rare.** Environ 1 ko/s en BLE, et l'iPhone n'est pas toujours à portée. Le simulateur Connect IQ ne parle pas à iOS : seule la logique autour du transport est testable (README Connect IQ).
4. **La matrice est hétérogène.** Écrans tactiles AMOLED et montres à cinq boutons en 1 bpp, de CIQ 3.4 à 6, et une mémoire disponible qui varie beaucoup d'un modèle à l'autre.

## Décisions

### D1 — La montre Garmin est le moteur de la séance, comme l'Apple Watch

Le pendant de l'ADR 0003 D1. Une sortie démarrée sur la Garmin est mesurée par la Garmin. L'iPhone l'affiche et la retrouve, il ne mesure jamais à sa place. Le canal d'instantanés quotidiens (ADR 0001, annexe #189) reste en place pour les jours sans séance.

### D2 — L'enregistrement est celui du système : une activité FIT

- **`ActivityRecording.createSession`**, avec `SPORT_WALKING` ou `SPORT_RUNNING`. Pas d'enregistreur maison : GPS, fréquence cardiaque, pause et sauvegarde sont ceux du système, et la sortie apparaît dans Garmin Connect comme n'importe quelle activité.
- **Elle rejoint Santé par Garmin Connect**, sous le même nom que les autres sorties de l'utilisateur. Foulée n'écrit **rien** dans Santé depuis ce canal, pour la raison de l'ADR 0001 (annexe #189, règle 1) : Garmin Connect écrira la même sortie plus tard, et un doublon dans Santé ne se reprend pas.
- **En attendant Garmin Connect, la sortie existe quand même dans Foulée.** Le résumé de fin, envoyé par BLE, devient une sortie en attente sur l'iPhone, de même forme que `PendingWalk`. Elle compte pour la série du jour et disparaît dès que Santé contient l'activité Garmin qui la recouvre (`WorkoutDeduplication`).
- **Le dénivelé est celui de la montre** (#536, ADR 0012) : `totalAscent` et `totalDescent`, mesurés et filtrés par Garmin, sur l'écran de fin et dans le résumé (`ascentM`, `descentM`). Une fois la sortie dans Santé, Foulée lit les clés standard (`HKMetadataKeyElevationAscended`, `HKMetadataKeyElevationDescended`) quelle que soit la source. Que Garmin Connect les écrive reste à vérifier sur une vraie montre (#191) : s'il ne le fait pas, la sortie perd son dénivelé quand Garmin Connect la remplace dans le Bilan.

### D3 — Le sport se choisit au départ, jamais en route

- **Le mode synchronisé depuis l'iPhone décide** (`activityMode`, comme `WatchSyncPayload`) : « Marche » ou « Course » démarrent directement, « Les deux » pose la question. C'est la règle de la montre Apple (ADR 0002, D4) : le sport est figé à la création de la session.
- **Pas de détection marche / course.** Connect IQ n'a pas d'équivalent de `CMMotionActivity`, et une classification maison serait le code fragile que l'ADR 0002 refuse. Pas de page « Jambes » sur Garmin.

### D4 — L'interface suit l'app d'exercice de la montre

L'ADR 0008 prend pour modèle l'app Exercice d'Apple. Sur Garmin, le modèle est l'app d'activité native : le porteur la connaît, et Foulée ne lui réapprend pas ses boutons.

- **Même contenu, gestes de la plateforme.** L'accueil, les pages et le résumé portent les mêmes informations que sur l'Apple Watch. Les gestes sont ceux de Garmin : START démarre et met en pause, BACK revient, haut et bas changent de page. Sur les écrans tactiles, `BehaviorDelegate` traduit balayages et touchers en ces mêmes actions : un seul code pour les deux familles.
- **Accueil** : série, puis pas et minutes rapportés aux objectifs, km et kcal, carte d'hydratation, et « Démarrer » en action principale (ADR 0008, D1). Sans iPhone jamais synchronisé, la série et les objectifs cèdent la place à « Ouvre Foulée sur ton iPhone », comme sur l'Apple Watch.
- **Pages de séance** : Séance (chrono, distance, allure, fréquence cardiaque), Journée (série, objectifs, hydratation), Plan sur les modèles cartographiques (`WatchUi.MapView`, API 3.0.0, réservée aux appareils à cartes embarquées). Pas de page Musique : les commandes musicales sont celles du système. Elles s'enchaînent dans une `WatchUi.ViewLoop` (API 3.4.0, le niveau du plus ancien appareil de la matrice).
- **Pause** : START met en pause. L'écran de pause propose Reprendre, Enregistrer, Supprimer, en `Menu2`, comme l'app native.
- **Alerte au kilomètre** (#382) : vibration (`Attention.vibrate`) et le kilomètre écoulé en surimpression, quelle que soit la page.
- **Résumé de fin** : durée, pas, distance, et « Terminer » en action principale.
- **Composants du système** (`Menu2`, `ViewLoop`, `MapView`, `Confirmation`) avant toute vue dessinée à la main. Les vues dessinées se limitent aux tuiles de chiffres.

### D5 — L'iPhone envoie à la montre ce qu'il est seul à savoir

La série se calcule sur l'iPhone, source unique (même raison que `WatchSyncPayload`). Il envoie série, objectifs, mode et réglages d'hydratation par le Companion SDK (`sendMessage`). La montre les reçoit par `Communications.registerForPhoneAppMessages`, les garde dans `Application.Storage`, et affiche le dernier état reçu.

### D6 — Un message, un type, une version

Tous les messages, dans les deux sens, sont des dictionnaires Connect IQ avec deux clés communes : `t` (le type) et `v` (sa version). Types prévus : `snapshot` (l'instantané actuel), `sync` (iPhone → montre, D5), `session` (état de séance, D7), `summary` (fin de séance, D2), `water` (D8). Le décodeur iOS garde la tolérance du décodeur actuel : type inconnu ignoré, version inconnue rejetée, champ manquant ou mal typé à zéro. L'instantané v1 sans `t` reste accepté, pour les montres pas encore mises à jour.

### D7 — La séance de la Garmin s'affiche sur l'iPhone, sans tracé en direct

La règle de l'ADR 0003 D2 : **un état complet et daté, jamais un delta**. Un état `session` (début, pause, durée, distance, pas, fréquence cardiaque) d'une centaine d'octets part toutes les 10 s quand l'iPhone est à portée, plus au début, à la pause, à la reprise et à la fin. L'écran miroir de l'iPhone l'affiche avec son âge.

- **Le tracé ne voyage pas en direct** : 1 500 points (ADR 0003, D3) ne passent pas à 1 ko/s toutes les 10 s.
- **Le tracé de fin** : Garmin Connect écrit les sorties dans Santé sans leur tracé GPS (ADR 0001). S'il doit rejoindre l'iPhone, c'est dans le résumé de fin, allégé sur la montre. Ce point a sa propre issue (phase C).
- **Écarté d'abord, puis repris (#480)** : la Live Activity pour une séance Garmin et la commande « Arrêter » de l'iPhone vers la montre.
  - **« Arrêter »** part en message `command` (`GarminSessionCommand`). La montre enregistre la séance comme son propre menu de pause. L'écran de l'iPhone se ferme sur la fin que la montre renvoie, jamais sur le toucher.
  - **La Live Activity** est demandée à chaque état reçu. `Activity.request` peut être refusé hors du premier plan, et un réveil BLE n'est pas un réveil miroir HealthKit (ADR 0003, D6). Elle apparaît alors au premier état qui trouve l'app au premier plan, puis suit chaque état. Les calories, que la montre n'envoie pas, s'y affichent « — ».
  - Le comportement réel reste à vérifier sur matériel (#191).

### D8 — « J'ai bu » à la montre, écrit par l'iPhone

La montre ne peut pas écrire dans Santé (fait 1). Un toucher sur « J'ai bu » crée un verre (identifiant, heure, volume) gardé dans `Storage` jusqu'à ce que l'iPhone l'accuse réception. L'iPhone l'écrit dans Santé avec cet identifiant en métadonnée, et ignore un identifiant déjà écrit : un verre renvoyé après une coupure n'est jamais compté deux fois. La règle de l'ADR 0005 s'applique telle quelle.

### D9 — La logique se teste à part, les vues restent minces

Le pendant Monkey C de l'ADR 0007. Calculs (allure, kilomètres, résumé, décision du sport), formats et encodage des messages vivent dans des modules purs, sans E/S, comme `DailySnapshot` aujourd'hui, et sont couverts par des tests Run No Evil exécutés en CI (#466). Les vues lisent un état déjà calculé.

### D10 — Un appareil reste dans la matrice s'il tient la séance en mémoire

La séance demande beaucoup plus de mémoire que l'app actuelle. Un appareil reste dans la matrice si, au simulateur, une séance d'une heure tient avec au moins 20 % de marge mémoire sur la page la plus lourde. Ce seuil se mesure et se vérifie en CI ; il remplace le choix au cas par cas. fr55 et instinct2 sont sortis de la matrice avant toute mesure : bloqués en Connect IQ 3.4.2, ils retenaient le plancher d'API de toute l'app (`minApiLevel` 5.0.0 depuis, #472).

## Phases

| Phase | Contenu | Publication |
| --- | --- | --- |
| **0** | App actuelle (instantanés), #465 à #473 | Beta : valide la chaîne BLE sur matériel (#191) avant d'y ajouter quoi que ce soit |
| **A** | Accueil (D4, D5), séance FIT (D2, D3), pages Séance et Journée, pause, alerte au kilomètre, résumé, glance avec la série | 1.0 sur le store : la parité utile |
| **B** | Sortie en attente sur l'iPhone (D2), écran miroir (D7), « J'ai bu » (D8) | 1.x |
| **C** | Plan (`MapView`), tracé de fin vers l'iPhone, complications, réévaluation de la Live Activity et des commandes iPhone | 1.x |

## Conséquences

- **Le README Connect IQ, les deux fiches store et `docs/privacy.md` changent à la phase A.** L'app lit désormais la position et la fréquence cardiaque, et l'activité enregistrée rejoint le compte Garmin Connect de l'utilisateur, comme toute activité Garmin. Foulée n'envoie toujours rien à un serveur : les fiches doivent le dire en ces termes, et l'énumération « rien d'autre ne quitte la montre » doit rester exacte.
- **Nouvelles permissions au manifeste** : `Positioning`, `Sensor` et `FitContributor` seulement si un champ FIT propre à Foulée est ajouté (pas prévu).
- **La série d'un porteur de Garmin ne dépend plus de Garmin Connect** le jour d'une sortie : la sortie en attente (D2) la porte jusqu'à la synchronisation.
- **La CI qui compile et teste le Monkey C (#466) est un prérequis** de la phase A : une app de séance ne se vérifie pas qu'à la main.
- **`README.md`, section « Conventions »** : la règle des écrans de montre renvoie aussi à cet ADR pour Garmin.
