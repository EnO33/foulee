# ADR 0003 — Séance partagée entre l'iPhone et l'Apple Watch

- **Statut** : acceptée (2026-10)
- **Issues** : [#272](https://github.com/EnO33/foulee/issues/272) (épic), #277, #278, #279, #282, #283, [#334](https://github.com/EnO33/foulee/issues/334), [#335](https://github.com/EnO33/foulee/issues/335), [#340](https://github.com/EnO33/foulee/issues/340)

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

### D4 — Une sortie de l'iPhone se reprend à la montre en deux portions (#335)

Le fait 1 interdit de *déplacer* une séance de l'iPhone vers la montre. La reprise **coupe** donc la sortie au lieu de la déplacer : l'iPhone arrête sa mesure et l'enregistre comme **portion 0** d'une sortie (`OutingLeg`), la montre ouvre la **portion 1** de la même sortie. Le regroupement par `outingID` (ADR 0002) en refait une seule ligne de l'historique, comme pour les portions d'une sortie montre.

- **Deux portes, un mécanisme.** « Continuer sur ma Watch » sur l'iPhone (`ActiveWalkStore.handOffToWatch`) et « Reprendre la séance de l'iPhone » sur la montre aboutissent au même `handOff()` : arrêter, enregistrer, rendre un `SessionHandoff` (identifiant de sortie + chiffres de la portion iPhone).
- **Depuis l'iPhone**, la reprise part dans le *contexte d'application* **avant** `startWatchApp(toHandle:)`, qui ne transporte qu'un sport : la montre, réveillée, la trouve en écoutant. Le contexte n'arrive qu'après l'activation de `WCSession`, donc **après** la demande de démarrage : la montre attend, au plus 3 s, que l'iPhone ait dit où il en est — une reprise fraîche, ou aucune séance en cours — avant d'ouvrir quoi que ce soit (#340). Démarrer aussitôt ouvrait une sortie neuve, à zéro, sans la portion iPhone. Elle remplace ensuite l'écran de l'iPhone par le miroir (D1), par le chemin existant.
- **Depuis la montre**, `sendMessage` réveille l'app iOS en arrière-plan ; l'iPhone répond avec la reprise, ou rien si sa séance vient de finir. Le contexte annonce en continu la séance en cours (`PhoneSessionStatus`), d'où le bouton et son chrono.
- **Les deux portions se touchent.** La portion montre commence où l'iPhone s'est arrêté, sans remonter plus loin que la fraîcheur d'une reprise (`SessionHandoff.freshness`, 2 min) ni dépasser l'instant présent : aucune minute non mesurée n'est revendiquée.
- **Les totaux continuent.** La portion iPhone entre dans les totaux et le chrono de la montre dès la première seconde, sans jamais être réenregistrée par la montre. Les kilomètres continuent la numérotation de la sortie ; celui en cours à la reprise, mesuré pour partie par chaque appareil, n'est pas chronométré.
- **Une reprise sert une fois.** Le contexte est renvoyé entier à chaque changement : la montre retient les sorties déjà reprises et ignore une reprise périmée, pour ne jamais ouvrir deux fois la portion 1.

Écarté : envoyer la reprise par `sendMessage` au moment de `startWatchApp` (la montre n'est pas encore joignable), et un enregistrement unique couvrant les deux appareils (aucune API ne permet à la montre d'écrire dans la séance de l'iPhone).

## Ce qui reste non mesuré

- **La taille maximale d'un envoi** par `sendToRemoteWorkoutSession(data:)` n'est pas documentée. 1 500 points compacts font environ 30 Ko ; le plafond est le réglage à baisser si un envoi échoue (le journal `session` le dira : « snapshot non transmis »).
- **Le coût CPU** de l'allègement toutes les 8 s sur une longue sortie : linéaire, jamais mesuré au poignet.
- **Le délai de réveil de l'app iOS** par `sendMessage` quand elle est suspendue : la montre affiche « iPhone injoignable » si le message échoue, sans réessai automatique.
