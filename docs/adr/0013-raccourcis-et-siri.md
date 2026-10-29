# ADR 0013 — Raccourcis, Siri et bouton Action : des App Intents qui appellent l'existant

- **Statut** : acceptée (2026-10)
- **Issues** : [#603](https://github.com/getfoulee/foulee/issues/603), [#604](https://github.com/getfoulee/foulee/issues/604), [#605](https://github.com/getfoulee/foulee/issues/605), [#606](https://github.com/getfoulee/foulee/issues/606), [#607](https://github.com/getfoulee/foulee/issues/607), [#608](https://github.com/getfoulee/foulee/issues/608)

## Contexte

Un seul App Intent existait : ajouter un verre d'eau, pour le bouton du widget d'hydratation. On ne pouvait ni lancer une sortie, ni demander sa série à Siri, ni mettre Foulée dans le Centre de contrôle ou sur le bouton Action. Or les deux gestes les plus fréquents (démarrer une sortie, savoir où on en est) se font souvent sans regarder l'écran : en sortant de chez soi, montre au poignet, téléphone en poche.

## Décisions

### D1 — Les gestes fréquents deviennent des App Intents

Trois intents, pas plus :

| Intent | Ce qu'il fait | iPhone | Montre |
|---|---|---|---|
| « Commencer une sortie » | ouvre Foulée et démarre une sortie, marche, course ou automatique | ✓ | ✓ (sans « Automatique », D5) |
| « Où j'en suis aujourd'hui » | répond sans ouvrir l'app : série, minutes et pas du jour | ✓ | — |
| « J'ai bu un verre » | enregistre un verre dans Santé sans ouvrir l'app | ✓ | ✓ |

Un geste devient un intent quand il se fait **sans regarder l'écran**. Le reste (le Bilan, les réglages, une sortie passée) s'ouvre dans l'app.

### D2 — Un intent, toutes les surfaces

Le même intent sert Siri, Raccourcis, Spotlight, le Centre de contrôle, l'écran verrouillé et le bouton Action. On ne déclare pas un intent par surface :

- `FouleeShortcuts` (iPhone) et `FouleeWatchShortcuts` (montre) donnent les phrases Siri, en français, et les tuiles de Raccourcis ; le système les enregistre à l'installation.
- `StartOutingControl` et `LogWaterControl` posent les deux gestes d'action dans le Centre de contrôle, sur l'écran verrouillé et sur le bouton Action de l'iPhone. Le sport de la commande se choisit en l'ajoutant ; laissé vide, le mode de l'utilisateur décide, comme sur le bouton de l'accueil.
- Spotlight trouve les intents par leur description et leurs mots-clés (« Marche », « Course », « Eau », « Série »…).
- Une sortie lancée depuis l'accueil et un verre ajouté dans l'app sont **donnés** à Siri (`donate()`), pour qu'il les suggère au bon moment. Un raccourci exécuté l'est déjà par le système.

### D3 — Un intent n'a pas de logique propre

Un intent ne fait qu'appeler ce qui existe déjà :

- « Commencer une sortie » dépose la demande dans `SessionStartRouter` (iPhone) ou `WatchPendingStart` (montre) ; l'accueil, qui possède la séance, la prend et la démarre comme son propre bouton. Une demande se **prend** (lue puis effacée), pour qu'une reconstruction de l'écran ne démarre pas deux sorties. Une séance déjà à l'écran l'emporte.
- « Où j'en suis aujourd'hui » lit les mêmes chiffres que les widgets (`WidgetLiveMetrics`) et les dit avec les textes VoiceOver de l'app.
- « J'ai bu un verre » écrit dans Santé comme le bouton du widget sur l'iPhone, comme la bannière d'hydratation sur la montre (`WatchWaterLog`), puis rafraîchit le seul widget d'hydratation.

Une règle métier qui manquerait à un intent va dans le store ou dans `FouleeKit` (ADR 0007), jamais dans l'intent.

### D4 — Les chiffres de santé ne se lisent pas téléphone verrouillé

« Où j'en suis aujourd'hui » exige un téléphone déverrouillé : Siri ne lit pas la série et les pas à qui tient un iPhone verrouillé. « J'ai bu un verre » n'écrit qu'un verre et ne lit rien : il reste disponible verrouillé. Sans autorisation Santé, il le dit plutôt que d'échouer en silence.

### D5 — Sur la montre

La montre écrit sa propre séance dans Santé : un sport que personne n'a choisi y resterait pour de bon (#223). Son « Commencer une sortie » n'a donc pas d'« Automatique » ; laissé vide, il fait comme « Démarrer » : le mode synchronisé lance son sport, et « les deux » demande au poignet.

Le bouton Action de l'Apple Watch Ultra passe par `StartWorkoutIntent`, qui veut un sport : ses réglages proposent « Marche » et « Course », choisis une fois. Cet intent est caché de Raccourcis, qui liste déjà « Commencer une sortie ».

« Où j'en suis aujourd'hui » n'existe pas sur la montre : la complication et l'écran d'accueil y répondent d'un coup d'œil.

## Conséquences

- Un nouveau geste rapide, c'est un intent de quelques lignes, ajouté à `FouleeShortcuts` (et à `FouleeWatchShortcuts` s'il a un sens au poignet) ; une commande seulement s'il agit.
- Les intents ne sont référencés que par le runtime d'App Intents : Periphery les ignore par une annotation `periphery:ignore`.
- Les phrases Siri sont en français, comme l'app ; une traduction devra les décliner.
- Siri, le Centre de contrôle et le bouton Action ne se vérifient que sur un appareil réel.
