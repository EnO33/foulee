# ADR 0003 — Séance partagée entre l'iPhone et l'Apple Watch

- **Statut** : acceptée (2026-10)
- **Issues** : [#272](https://github.com/EnO33/foulee/issues/272) (épic), #277, #278, #279, #282, #283, [#334](https://github.com/EnO33/foulee/issues/334), [#342](https://github.com/EnO33/foulee/issues/342)

## Contexte

Une sortie peut être mesurée par l'iPhone (`ActiveWalkStore`) ou par l'Apple Watch (`WatchWorkoutStore`), et l'utilisateur veut la suivre sur les deux appareils. Les décisions de l'épic #272 n'étaient consignées que dans l'issue ; cet ADR les fixe et accueille celles qui suivent.

Trois faits d'Apple cadrent tout :

1. **Le miroir ne va que dans un sens.** `startMirroringToCompanionDevice()` n'existe que sur watchOS, et `HKWorkoutSessionType` n'a que `primary` (montre) et `mirrored` (iPhone). Aucune API ne fait voir à la montre une séance mesurée par l'iPhone.
2. **Le miroir n'est pas du temps réel.** Dans le sens montre → iPhone, HealthKit met en cache ce qui est envoyé et réveille l'app iOS *périodiquement*, parfois à plusieurs minutes d'intervalle.
3. **Rien du miroir ne s'exerce au simulateur.** Ni en local, ni en CI : seule la logique autour du transport est testable.

## Décisions

### D1 — La montre est le moteur ; l'iPhone, une télécommande

Une sortie mesurée à la montre est **la meilleure** des deux : vrais échantillons HealthKit, fréquence cardiaque, découpage en portions (ADR 0002). L'iPhone l'affiche (#279), peut l'arrêter (#282) et peut la démarrer (#283, `startWatchApp(toHandle:)`), mais ne mesure jamais à sa place. `ActiveWalkStore` reste le repli « pas de montre au poignet ».

### D2 — Un état complet, daté, jamais un delta

La montre envoie un `WatchSessionSnapshot` toutes les `mirrorInterval` (8 s), plus aux moments qui comptent (début, changement de sport, fin). Chaque envoi est **complet** : un delta perdu entre deux réveils ne se rattrape pas, un état complet perdu est corrigé par le suivant. L'iPhone garde le plus récent (`sentAt`) et **affiche son âge** (« Relevé il y a 2 min ») plutôt que de prétendre au direct. Seul le chrono, dérivé d'une date, avance en temps réel.

### D3 — Le parcours voyage dans le snapshot (#334)

La montre enregistre le tracé GPS (#312). Il rejoint l'iPhone **dans le même snapshot**, sous la règle de D2 : le tracé complet à chaque envoi.

- **Par portion**, découpé par `WatchRoutePortion.portions` (#320) : l'iPhone le colore marche / course comme la page « Plan » de la montre et le détail (`SessionActivity.tint`, désormais partagé par les deux cibles).
- **Allégé** avant l'envoi (`MirroredRoutePortion.mirrored`) : un point tous les 10 m au plus serré, l'espacement s'élargissant pour ne jamais dépasser **1 500 points** quelle que soit la longueur de la sortie. Le premier et le dernier point de chaque portion sont gardés, pour que les jonctions se touchent et que le dernier point soit bien la position actuelle.
- **Compact** : `[lat, lon, lat, lon, …]` arrondis à 10⁻⁵ degré (~1 m), environ deux fois moins d'octets que des objets `{latitude, longitude}`.
- **Tolérant** : un tracé absent ou illisible donne un tracé vide, jamais un snapshot rejeté — une montre d'une version antérieure continue d'envoyer ses chiffres.

L'écran miroir propose « Voir le parcours » **seulement quand une ligne existe** (deux points dans au moins une portion). La carte se met à jour au rythme des réveils, comme les chiffres.

Écarté : un message séparé pour le tracé, ou des deltas de points. Les deux réintroduisent ce que D2 évite — un état que la perte d'un message rend faux pour le reste de la sortie.

### D4 — Une séance de l'iPhone s'affiche sur la montre ; elle n'y est pas reprise (#342)

Le pendant de D1 dans l'autre sens : pour une séance lancée sur l'iPhone, **l'iPhone est le moteur et la montre une télécommande**. Un seul enregistrement, celui de l'iPhone. La montre affiche la séance (chrono, pas, distance, kcal, carte) et peut la mettre en pause, la reprendre ou la terminer.

- **Transport : WatchConnectivity**, puisque le miroir HealthKit ne va que montre → iPhone (fait 1). L'état suit D2 : un `PhoneSessionSnapshot` complet et daté. Il part à chaque changement d'état (début, pause, reprise, fin), puis toutes les 3 s pendant la séance.
  - **En direct**, par `sendMessage`, quand la montre est joignable.
  - **Dans le contexte d'application**, pour une montre qui ouvre l'app plus tard. Le contexte porte aussi les préférences synchronisées, car il est remplacé en entier à chaque envoi.
- **La montre garde le plus récent** (`sentAt`), fait tourner le chrono elle-même (`timerBasis`) et affiche l'âge du relevé. Elle oublie une séance terminée, retirée du contexte, ou silencieuse depuis 15 min (app iPhone tuée).
- **Commandes** : la montre envoie `pause`, `resume` ou `stop` par `sendMessage`, ce qui réveille l'app iOS en arrière-plan. L'iPhone répond si la séance était en état d'obéir. L'écran change quand l'iPhone dit que la séance a changé, pas au toucher.
- **Le parcours de l'iPhone** est allégé par les mêmes règles que D3 (`MirroredRoutePortion.thinning`, désormais partagé).
- **La page de chiffres est celle d'une séance montre**, alimentée par l'iPhone : une seule façon de lire une séance, quel que soit l'appareil qui l'enregistre. Sans capteur cardiaque sur l'iPhone, la tuile affiche un tiret.

**Écarté, après l'avoir livré (#335, #337, #341) :** reprendre la séance à la montre en la coupant en deux portions d'une même sortie. Le code regroupait bien les deux portions dans l'historique de Foulée, mais Santé et Forme montraient **deux entraînements** pour une seule sortie. Ce n'est pas ce qu'on attend d'une séance « reprise ». Aucune API ne permet de déplacer une séance d'un appareil à l'autre.

## Ce qui reste non mesuré

- **La taille maximale d'un envoi** par `sendToRemoteWorkoutSession(data:)` n'est pas documentée. 1 500 points compacts font environ 30 Ko ; le plafond est le réglage à baisser si un envoi échoue (le journal `session` le dira : « snapshot non transmis »).
- **Le coût CPU** de l'allègement toutes les 8 s sur une longue sortie : linéaire, jamais mesuré au poignet.
- **Le coût en batterie** d'un `sendMessage` toutes les 3 s pendant une séance iPhone, des deux côtés. C'est le réglage à allonger (`ActiveWalkStore.watchInterval`) si la montre s'en ressent.
