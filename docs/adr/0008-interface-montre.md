# ADR 0008 — Interface de la montre : l'action principale à portée, l'ordre d'Exercice

- **Statut** : acceptée (2026-10)
- **Issues** : [#438](https://github.com/EnO33/foulee/issues/438)

## Contexte

Le premier test sur TestFlight 1.52.0 a relevé trois gênes à la montre :

- **Accueil** : « Démarrer » venait après la série, les quatre tuiles et la carte d'hydratation. L'action pour laquelle on ouvre l'app était la dernière atteinte.
- **« Marche ou course ? »** : « Annuler » restait fixe sous les deux réponses, qui défilaient. Deux comportements sur un même écran.
- **Séance** : sept pages en ligne, dans un ordre propre à Foulée. Journée et Hydratation occupaient deux pages pour une seule question : où en est la journée.

Le résumé de fin de sortie avait le même défaut que l'accueil : avec le plan et les kilomètres, « Terminer » arrivait en dernier.

## Décisions

### D1 — L'action principale d'un écran est fixe en bas

- **« Démarrer » à l'accueil, « Terminer » au résumé** (ou « Réessayer » après un échec d'enregistrement) restent en bas de l'écran ; le reste défile au-dessus (`pinnedAction`).
- **Un `safeAreaInset`, pas un bouton de barre d'outils** : watchOS dessine ses boutons de barre du bas ronds et sans texte, alors que ceux de Foulée sont des capsules pleine largeur. La vue défilante s'arrête au-dessus du bouton, et un fond masque les lignes qui passent dessous.
- **Une seule action fixe par écran.** L'action secondaire (« Terminer » après un échec) reste à la fin du défilement.

### D2 — On quitte un écran de choix par la croix du système

- **« Annuler » est un `ToolbarItem(placement: .cancellationAction)`**, en haut à gauche comme dans toutes les feuilles de watchOS. Il ne prend aucune place aux réponses : sur un 40 mm, Marche et Course tiennent sans défiler.
- **L'écran garde sa vue défilante** pour les plus grandes tailles de texte. La croix, elle, ne défile jamais (`WatchActivityPickerTests`).

### D3 — Les pages d'une séance suivent l'ordre d'Exercice

| Contrôles | **Séance** | Musique | Plan | Jambes | Journée |
| --- | --- | --- | --- | --- | --- |
| Arrêter, Pause | page d'ouverture | « À l'écoute » | parcours | après un changement de sport | série, objectifs, hydratation |

- **Contrôles à gauche, Musique à droite de la page d'ouverture**, comme Exercice. Arrêter et mettre en pause sont à un geste dans un sens, la musique à un geste dans l'autre.
- **Hydratation rejoint Journée.** Six pages au plus, cinq tant que la sortie n'a pas changé de sport.
- **La séance de l'iPhone vue au poignet suit le même ordre** : Contrôles, Séance, Plan.
- **La sélection reste liée aux cas de `WatchSessionPage`**, jamais à un index : Jambes apparaît en cours de route.

### D4 — Les contrôles ont la forme de ceux d'Exercice

- **Deux boutons ronds côte à côte, nommés dessous** (`WatchControlButton`) : « Arrêter » à gauche, « Pause » ou « Reprendre » à droite. Même forme pour la séance de l'iPhone (« Terminer », « Pause »).
- **Le bouton porte son nom pour VoiceOver**, la légende est masquée : le contrôle se lit une fois, et un test d'interface le trouve par ce nom.

## Règle pour les écrans à venir

- **Un écran a au plus une action principale, et elle est fixe en bas** (`pinnedAction`).
- **Un écran de choix se ferme par la croix du système** (`.cancellationAction`), pas par un bouton dans le contenu.
- **Une nouvelle page de séance s'ajoute après Plan**, jamais entre Contrôles, Séance et Musique.
- **Toute mise en page se vérifie sur la sonde 40 mm** (`tools/capture_screenshots.sh --watch "Apple Watch SE 3 (40mm)" probe-40`, ou le workflow Screenshots).

## Conséquences

- **Les captures App Store de la montre changent** : l'accueil montre « Démarrer » dès la première image, et la carte d'hydratation au-dessus du bouton.
- **La capture « Jambes » passe par trois pages au lieu de quatre** (Musique, Plan, Jambes), Contrôles étant de l'autre côté.
