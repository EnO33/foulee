# ADR 0005 — Hydratation : la carte, l'annulation et l'écran dédié

- **Statut** : acceptée (2026-10)
- **Issues** : [#353](https://github.com/EnO33/foulee/issues/353), [#354](https://github.com/EnO33/foulee/issues/354), [#355](https://github.com/EnO33/foulee/issues/355)

## Contexte

Le suivi d'hydratation (#329) tenait en une carte : une barre de progression, des litres, et un bouton « J'ai bu » qui écrit un verre dans Santé (`dietaryWater`). La carte ne disait pas si l'on était en retard sur sa journée. Un toucher accidentel ne s'annulait que dans l'app Santé. Et rien ne permettait de revenir sur la journée ou la semaine. Le Bilan (ADR 0004) a fixé une grammaire visuelle (anneaux, chronologie, une phrase qui donne le sens), et l'hydratation la rejoint.

## Décisions

### D1 — Une rangée de verres, et le rythme de la journée (#353)

- **La carte dessine l'objectif en verres** (`HydrationMath.glassFills`). Il y a autant de verres que l'objectif en contient, arrondi au-dessus, avec un plafond de dix. Au-delà, chaque verre représente une part plus grande de l'objectif, pour qu'un objectif de 4 L ne déborde jamais de la carte. Le dernier verre peut être en partie rempli.
- **Le rythme** (`HydrationPace`, pur et testé) compare l'apport à un objectif réparti uniformément sur la plage d'hydratation des réglages, celle des rappels. Un écart de moins d'un verre se lit « dans le rythme ». Au-delà, l'écart se compte en verres entiers : « 2 verres de retard », « en avance ». Avant la plage, sans rien bu, la journée « commence à 9 h ». Un objectif atteint l'emporte sur l'heure.
- **La plage n'est pas un `ClosedRange`.** Rien n'empêche les réglages de la faire finir avant son début, et un `ClosedRange` inversé fait planter l'app. Une plage inversée compte comme terminée dès que son début est passé.
- La carte relit le rythme chaque minute, à l'horloge de l'app (`@Dependency(\.date)`). Les captures et les tests le figent donc.

### D2 — Annuler un verre (#354)

- **Le toast de confirmation porte « Annuler »** pendant 5 s, que le verre vienne de l'accueil ou de l'action de la notification. Le tampon de confirmation transporte ce qu'il faut pour annuler (`HydrationNotification.Undo`) :
  - l'identifiant de l'échantillon écrit, que `logWater` renvoie ;
  - le verre précédent sur lequel la grille de rappels s'appuyait.
- **Seul l'échantillon écrit par Foulée est supprimé** (`deleteWater`). HealthKit ne laisse de toute façon une app supprimer que ses propres échantillons. Annuler ne peut donc jamais retirer de l'eau notée par une autre app.
- **La grille de rappels revient en arrière** (`restoreDrinkAndReschedule`) comme si le verre n'avait pas été bu.
- **Un refus de Santé est dit** dans le toast. L'apport, lui, ne bouge pas.

### D3 — Un écran Hydratation (#355)

Toucher la carte ouvre un écran, dans le langage du Bilan :

- **Aujourd'hui** : une goutte qui se remplit, les litres et le rythme.
- **Les quantités rapides**, toutes visibles sur l'écran : petit verre, verre réglé, grand verre, bouteille (`HydrationServing`). Ce sont des tailles fixes, dérivées du verre réglé et arrondies à 10 mL, et la bouteille reste la plus grande. Sur l'accueil, un toucher reste un verre, et les autres tailles sont à un appui long.
- **Verre par verre** : chaque échantillon du jour à son heure, avec sa quantité et l'app qui l'a écrit. Comme la chronologie des sorties, elle lit toutes les sources : un verre noté sur la montre ou dans une autre app y figure.
- **7 derniers jours** : un anneau par jour à la couleur de l'eau, les jours où l'objectif est tenu, et la moyenne (`HydrationHistory`, pur et testé).

Deux lectures Santé s'ajoutent : `waterToday` (les échantillons du jour) et `waterSeries` (les totaux quotidiens). Elles vivent dans `HealthKitClient+Water`, à côté de la requête de statistiques partagée (`statisticsCollection`, généralisée à un type quelconque). L'écran se relit chaque fois que l'apport du jour bouge : un verre ici, un verre de la montre, un verre annulé.

**Écarté** : la saisie libre d'une quantité. Quatre tailles couvrent l'usage, et un champ numérique coûte plus de gestes qu'il n'en fait gagner.

## Ce qui reste ouvert

- **L'hydratation dans le Bilan** (#356) : moyenne, jours tenus et écart avec la période d'avant.
