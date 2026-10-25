# ADR 0012 — Un dénivelé juste, montée et descente séparées

- **Statut** : acceptée (2026-10)
- **Issues** : [#562](https://github.com/EnO33/foulee/issues/562), [#563](https://github.com/EnO33/foulee/issues/563), [#564](https://github.com/EnO33/foulee/issues/564), [#565](https://github.com/EnO33/foulee/issues/565), [#566](https://github.com/EnO33/foulee/issues/566), [#567](https://github.com/EnO33/foulee/issues/567)

## Contexte

Une sortie affichait 615 m de dénivelé, bien plus que le terrain. `ElevationAccumulator` ajoutait chaque hausse entre deux lectures du baromètre, environ une par seconde. Le baromètre oscille de quelques dizaines de centimètres en permanence : chaque oscillation vers le haut comptait, et une heure de marche montait de plusieurs centaines de mètres, en côte comme sur le plat. La descente n'était mesurée nulle part.

## Décisions

### D1 — Un seuil de 3 m

Un écart ne compte qu'une fois l'altitude éloignée de **3 m** du dernier point retenu, vers le haut comme vers le bas ; il compte alors en entier, et ce point devient le nouveau repère. C'est la méthode des montres de sport : le bruit du baromètre reste sous le seuil, une vraie côte le franchit. Une pente régulière ne perd que ses derniers mètres, moins de 3 m par sortie. Une dérive lente de la pression (la météo) peut encore franchir le seuil sur une très longue sortie : c'est le prix d'un baromètre sans GPS d'altitude.

### D2 — D+ et D− séparés, jamais additionnés

`Elevation` porte la montée et la descente, mesurées de la même façon et gardées à part. L'iPhone les cumule sur les segments d'une séance, pauses comprises ; la montre donne à chaque portion sa part des deux (`ClimbTrail`) ; la montre Garmin envoie `totalAscent` et `totalDescent`, qu'elle mesure elle-même.

### D3 — Les clés standard de Santé

La montée sous `HKMetadataKeyElevationAscended`, la descente sous `HKMetadataKeyElevationDescended`, que d'autres apps lisent aussi. Moins d'un mètre n'est pas écrit : une clé absente se lit « non mesuré », 0 m se lirait « sortie plate ».

### D4 — Affichées côte à côte, le reste sur la montée

La fiche montre « D+ » et « D− », les lignes du Bilan « ↑ 120 m · ↓ 115 m », la séance en cours et les écrans de fin les deux. Le Bilan, les records et les repères de séance (ADR 0010) restent sur la montée : c'est l'effort, la descente n'en est qu'une partie.

## Conséquences

- Les sorties déjà enregistrées gardent la valeur écrite à l'époque : Santé ne laisse pas modifier une séance.
- Le seuil n'est pas encore éprouvé au poignet (#191) ; il se règle dans `ElevationAccumulator.threshold`.
