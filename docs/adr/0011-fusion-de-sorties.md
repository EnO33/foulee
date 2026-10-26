# ADR 0011 — Fusionner une sortie coupée en deux

- **Statut** : acceptée (2026-10)
- **Issues** : [#549](https://github.com/getfoulee/foulee/issues/549), [#550](https://github.com/getfoulee/foulee/issues/550), [#551](https://github.com/getfoulee/foulee/issues/551), [#552](https://github.com/getfoulee/foulee/issues/552), [#553](https://github.com/getfoulee/foulee/issues/553), [#554](https://github.com/getfoulee/foulee/issues/554), [#555](https://github.com/getfoulee/foulee/issues/555)

## Contexte

Une sortie interrompue en route arrive dans Santé en deux séances : l'app montre relancée par le système en pleine séance, une séance qui échoue, un arrêt par erreur, une montre Garmin qui sauvegarde et repart. Foulée en montrait deux : le Bilan comptait deux sorties aux chiffres coupés en deux, les repères de séance (ADR 0010) mesuraient une moitié, la notification en annonçait deux.

## Décisions

### D1 — Une fusion est un lien gardé sur l'iPhone, pas une réécriture de Santé

Santé ne laisse une app supprimer que ce qu'elle a écrit, et les copies de Garmin Connect ou de Strava resteraient de toute façon. Réécrire Santé ne marcherait que pour les séances Foulée, et ne se défait pas.

`OutingMerge` garde les séances Santé d'une sortie fusionnée ; `OutingMergeStore` les garde dans les `UserDefaults` de l'iPhone. À la lecture (`recentWorkoutSummaries`), chaque partie reçoit l'identifiant de la fusion comme une jambe de sortie montre (#316) : `OutingGrouping` les rejoint en une sortie, même de même sport, et tout ce qui lit les sorties — Bilan, repères, notification — n'en voit qu'une. Une fusion de plus de 400 jours est oubliée : le Bilan lit douze mois.

### D2 — Seulement deux sorties qui se suivent

- Consécutives : la sortie juste avant ou juste après, jamais au-delà d'une autre.
- Sans chevauchement : deux séances qui se chevauchent sont deux copies d'une même sortie, déjà réunies par le dédoublonnage (#218).
- À **une heure** d'écart au plus : au-delà, ce sont deux sorties.
- Pas une sortie Garmin en attente (#479) : son identifiant change quand Garmin Connect l'écrit, et la fusion se déferait seule.

Fusionner une sortie déjà fusionnée étend la fusion. Une fusion se sépare ; une sortie montre regroupée de ses jambes, non.

### D3 — L'arrêt n'est pas de l'activité

La durée d'une sortie fusionnée est la somme de ses parties ; ses pas se lisent partie par partie. Le dédoublonnage mesure le chevauchement sur toute la sortie, de la première partie à la dernière, pour que la copie Strava de la seconde partie s'y fonde encore après un long arrêt. Les minutes de l'anneau ne changent pas : elles comptent déjà chaque partie, jamais l'arrêt. La frise du détail montre l'arrêt, et VoiceOver le dit.

### D4 — Depuis la fiche de la sortie

La fiche propose « Fusionner avec la sortie de 10:42 » pour chaque voisine possible ; une confirmation dit l'heure, la distance du résultat, et que Santé n'est pas modifié. Une sortie fusionnée propose « Séparer les sorties ». L'une ou l'autre ramène au Bilan, relu.

### D5 — La montre reprend la séance plutôt que de la clore

Après une relance de l'app en pleine séance, `WatchWorkoutRecovery` terminait la séance retrouvée : le marcheur, qui continuait, en relançait une autre. La montre la **reprend** désormais, comme les apps d'entraînement d'Apple : écran de séance, horloge du builder, identifiant de sortie relu sur la jambe, jambes déjà enregistrées relues dans Santé. Le tracé d'avant la relance reste perdu : l'app le tenait. Une séance d'un sport que Foulée n'enregistre pas est terminée, comme avant, pour qu'elle arrive dans Santé.

## Conséquences

- Une fusion ne vit que sur l'iPhone qui l'a faite : une réinstallation l'oublie, et Santé comme les autres apps voient toujours deux séances.
- La reprise sur la montre n'est pas encore éprouvée au poignet (#191).
