# ADR 0014 — Fiabilité et diagnostics, sans serveur

- **Statut** : acceptée (2026-10)
- **Issues** : [#609](https://github.com/getfoulee/foulee/issues/609), [#610](https://github.com/getfoulee/foulee/issues/610), [#611](https://github.com/getfoulee/foulee/issues/611), [#612](https://github.com/getfoulee/foulee/issues/612), [#613](https://github.com/getfoulee/foulee/issues/613), [#614](https://github.com/getfoulee/foulee/issues/614)

## Contexte

Foulée n'a pas de serveur, et c'est voulu : rien ne quitte l'appareil sans la personne. Mais quand quelqu'un signalait un souci, on n'avait rien : ni plantage, ni gel, ni trace des réveils en arrière-plan qui tiennent les widgets à jour. Les états dégradés (Santé illisible, localisation ou mouvements refusés, météo muette) étaient traités écran par écran, certains en silence. Le temps de lancement n'était mesuré nulle part, et une sortie montre se perdait si la batterie lâchait avant « Arrêter ».

## Décisions

### D1 — Les diagnostics restent sur l'iPhone, et ne partent qu'avec la personne (#610)

- L'iPhone s'abonne à **MetricKit** au lancement (`DiagnosticsCollector`) et garde ses plantages, gels, lancements lents, excès de CPU et d'écritures disque : **dix rapports au plus, un mois au plus** (`DiagnosticHistory`), dans le dossier de l'app, lisibles dès le premier déverrouillage pour qu'une livraison téléphone verrouillé ne les efface pas.
- **Aucun envoi automatique**, aucun SDK tiers, aucun serveur. Réglages › À propos › « Signaler un problème » montre d'abord le résumé (« Voir le résumé »), puis :
  - « Ouvrir un signalement » ouvre une issue GitHub, **publique**, préremplie du **résumé** si « Joindre le résumé » est activé : version, appareil, système, date et type de chaque incident, sans pile d'appels ;
  - « Partager le rapport complet » passe par la feuille de partage : le résumé et les traces techniques, envoyés **en privé** à qui la personne choisit.
- Le résumé ne contient **ni donnée de santé ni position** ; il est en anglais, car il est lu par le mainteneur. `docs/privacy.md` le décrit.
- La logique (tri, plafonds, texte du résumé) vit dans `FouleeKit` et se teste sur macOS (ADR 0007).

### D2 — Un état dégradé, un message et une action (#611)

- `DegradedState` (dans `FouleeKit`) nomme **ce qui manque pour la personne**, pas l'API qui a échoué : Santé illisible, eau non autorisée, localisation refusée, mouvements refusés, météo indisponible, aucune donnée sur la période.
- Chaque état a son titre, une phrase qui dit quoi faire, et un **remède** quand la personne peut agir : « Ouvrir Santé » ou « Ouvrir les réglages ». Sans remède possible (la météo qui ne répond pas), pas de bouton.
- Un seul composant, `DegradedBanner`, les affiche partout : accueil, hydratation, météo, sortie en cours, statistiques.
- Réglages › « Autorisations » liste toutes les autorisations refusées avec leur bouton. Santé ne dit jamais à une app qu'une lecture est refusée : la page le rappelle toujours, avec « Ouvrir Santé ».

### D3 — Les réveils en arrière-plan se journalisent, sans valeur de santé (#612)

- Chaque réveil (observateurs Santé du pas, de l'eau et des entraînements ; tâche de rafraîchissement ; instantané Garmin ; observateur eau de la montre) écrit sous la catégorie `background` de `FouleeLog` : réveil, durée, succès ou erreur.
- Une demande refusée par le système (`BGTaskScheduler.submit`, `enableBackgroundDelivery`) n'est plus avalée par un `try?` : elle est journalisée.
- Le journal ne contient **aucune valeur de santé** : le type HealthKit, une durée, le texte d'erreur du système. Il reste dans le journal unifié de l'appareil ; on le lit avec Console.app (`docs/BACKGROUND.md`).
- On distingue ainsi « iOS ne nous a pas réveillés » de « le réveil n'a rien changé », au lieu de le supposer.

### D4 — Le temps de lancement est mesuré en CI (#613)

- Le job **Launch time** lance l'app iPhone sept fois, à froid, en mode capture, et chronomètre chaque lancement jusqu'à l'accueil affiché.
- On compare le lancement **le plus rapide** au budget de `FouleeLaunchTime/LaunchTimeBudget.json`, avec 30 % de tolérance : la charge d'un runner ne fait qu'ajouter du temps, alors qu'une vraie régression ralentit tous les lancements.
- `XCTApplicationLaunchMetric` ne rend rien sur les machines virtuelles de la CI : le test mesure à l'horloge murale (`XCTClockMetric`).
- C'est un lancement **Debug** (le mode capture n'existe qu'en Debug) sur le simulateur de la CI : le chiffre ne vaut que comparé à lui-même. Il n'est pas un budget d'expérience utilisateur ; MetricKit (D1) remonte les lancements lents réels.

### D5 — Une sortie montre s'arrête avant la batterie (#614)

Sous 5 %, hors charge, une sortie montre s'arrête d'elle-même et s'enregistre dans Santé par le chemin habituel ; le résumé dit pourquoi. Le détail est dans l'ADR 0003, D9.

## Conséquences

- Un nouvel état dégradé est un cas de `DegradedState`, avec son texte et son remède, affiché par `DegradedBanner` ; jamais un message écrit à la main dans un écran.
- Un nouveau travail en arrière-plan journalise son réveil et sa fin sous `FouleeLog.background`, et ses lignes vont dans `docs/BACKGROUND.md`.
- Un changement volontairement plus lent au lancement met à jour le budget (`tools/launch_time.sh --record`, ou l'artefact `launch-time` de la CI), en le disant dans la PR.
- Tout ce qui pourrait sortir de l'appareil passe par un geste de la personne et par `docs/privacy.md`, copié vers `../foulee-web/src/content/`.
- La montre n'a pas de diagnostics MetricKit : on n'en reçoit que ce qu'en dit son journal (`session`, `background`).

## Ce qui reste non mesuré

- MetricKit livre au plus une fois par jour, et seulement sur un appareil réel : les diagnostics ne se vérifient pas au simulateur.
- La fréquence réelle des réveils en arrière-plan dépend d'iOS et de l'usage ; seuls les journaux d'un vrai téléphone le diront.
- Le seuil de 5 % de batterie n'a jamais été vu au poignet (ADR 0003).
