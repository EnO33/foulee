# ADR 0004 — Récap de la semaine et du mois

- **Statut** : acceptée (2026-10)
- **Issues** : [#344](https://github.com/EnO33/foulee/issues/344), [#346](https://github.com/EnO33/foulee/issues/346), [#348](https://github.com/EnO33/foulee/issues/348), [#350](https://github.com/EnO33/foulee/issues/350), [#356](https://github.com/EnO33/foulee/issues/356)

## Contexte

L'accueil suit la journée en cours et les 7 derniers jours, mais rien ne fait le **bilan** d'une semaine ou d'un mois écoulés. Un bilan régulier donne une raison de revenir et de mesurer le chemin parcouru. Il demande deux choses : un écran de récap, et une notification qui l'annonce.

## Décisions

### D1 — Le récap porte sur la dernière période terminée

> **Amendée par D6** pour la semaine : elle couvre désormais les 7 derniers jours glissants. Le mois reste le dernier mois terminé.

Une semaine, du lundi au dimanche (calendrier ISO, comme toutes les semaines de l'app), ou un mois civil. Jamais la période en cours : un récap est un bilan, pas un suivi, et l'accueil fait déjà le suivi. Le lundi, le récap de la semaine est celui de la semaine qui s'est terminée la veille ; le 1er, celui du mois qui vient de finir.

### D2 — Les chiffres de l'app, pas de nouveaux calculs

Le récap est calculé (`Recap.make`, pur et testé) à partir de ce que l'app lit déjà dans Santé :

- les **minutes** viennent des minutes quotidiennes fusionnées (`dailyMinutes`), les mêmes que la série et le calendrier ;
- les **pas, la distance et les kcal** viennent des séries quotidiennes (`metricSeries`), les mêmes que les écrans de statistiques ;
- les **sorties** sont comptées comme dans le résumé : les portions d'une même sortie sont regroupées (`OutingGrouping`), puis les doublons retirés (`WorkoutDeduplication`).

**L'objectif tenu** se compte sur les **jours actifs** choisis par l'utilisateur, comme la série. Un jour de repos ne le fait pas manquer.

**La comparaison** se fait avec la période précédente. Elle est absente quand la période précédente est vide, car « +∞ % » ne dit rien.

Une seule lecture de Santé (`RecapStore`) couvre la semaine, le mois et les deux périodes précédentes.

### D3 — Une notification au texte fixe

Chaque lundi (dimanche à 19 h depuis D6) et chaque 1er du mois à 9 h, une notification répétée (`UNCalendarNotificationTrigger`) annonce le récap. **Son texte ne cite aucun chiffre** : une notification est programmée à l'avance et ne peut pas lire Santé au moment où elle s'affiche. Elle annonce donc le récap au lieu de le citer, et les chiffres, toujours à jour, sont à un toucher.

Toucher la notification ouvre le bon récap. Le délégué de notifications, qui s'exécute avant qu'un écran existe, passe la demande à `RecapRouter`. L'accueil la présente ensuite (`RecapPresentation`), que le toucher ait lancé l'app ou l'ait trouvée ouverte. La carte « Tes récaps » de l'accueil passe par le même routeur : une seule façon d'ouvrir un récap.

La notification est **activée par défaut** et se coupe dans Réglages → Notifications.

**Écarté** : recalculer le texte de la notification en arrière-plan (`BGAppRefreshTask`) pour y mettre les chiffres. iOS ne garantit ni l'heure ni l'exécution d'une tâche de fond. Une notification qui affiche des chiffres faux, ou qui n'arrive pas, coûte plus cher qu'un texte fixe.

### D4 — Un récap qui se lit comme un bilan, pas comme un tableau (#346)

La première version (#344) alignait des chiffres, un graphique en barres et quatre tuiles. Juste, mais rien ne disait ce que la période **signifiait**. L'écran se lit désormais de haut en bas, comme une histoire.

1. **Le sens d'abord.** Un grand anneau « objectifs tenus », le total de minutes et une phrase de bilan (`Recap.Verdict`, pur et testé). L'ordre de priorité est : période vide, puis parfaite, puis régulière (70 % des jours prévus), puis en progrès. La régularité passe avant le volume, parce que la série est ce dont l'app parle.
2. **Le jour par jour en anneaux** : sept pour une semaine, un calendrier pour un mois. C'est le même langage que l'anneau d'activité de l'accueil et l'anneau intérieur du calendrier de série : un même jour se lit pareil partout. Un jour de repos sans activité est un cercle pointillé, jamais un anneau vide, car il n'a pas été manqué.
3. **La comparaison en barres** : deux barres par mesure, sur une échelle commune. Cette période prend la couleur de la mesure, la précédente est en gris neutre, avec l'écart chiffré. L'écart a une flèche en plus de sa couleur, pour que le sens ne repose jamais sur la couleur seule.
4. **Les temps forts** : le meilleur jour et l'énergie dépensée.

Les anneaux et les barres se remplissent à l'ouverture. Changer de période rejoue l'animation.

**Sur l'accueil**, la carte passe sous l'hydratation et devient un aperçu de la semaine passée : un anneau par jour, les minutes, les objectifs tenus et l'écart. Elle dit déjà quelque chose avant d'être touchée.

### D5 — Une seule grammaire pour la semaine et les 7 derniers jours (#348)

Après D4, deux écrans voisins parlaient encore l'ancien langage : les barres « Minutes par jour » de l'onglet Semaine et la liste du Résumé 7 jours. Tous deux passent aux anneaux du récap.

- **Onglet Semaine** : une rangée d'anneaux, du lundi à aujourd'hui. Un jour de repos est pointillé, un jour à venir est une piste pâle, aujourd'hui est mis en avant.
- **« 7 derniers jours »**, qui remplace le Résumé 7 jours :
  - l'en-tête du récap sur une **période glissante** (`RecapPeriod.lastDays`) ;
  - une frise d'anneaux pour choisir un jour ;
  - la **chronologie** de ses sorties, chacune à son heure et à la couleur de son sport, qui ouvre son détail ;
  - la comparaison avec les 7 jours d'avant.

La période qui précède une semaine devient « les 7 jours d'avant ». C'est identique à la semaine ISO précédente pour une semaine calendaire, et c'est la seule réponse juste pour une période glissante.

Le regroupement des sorties par jour quitte la vue pour le modèle (`OutingDay.lastDays`). Son ordre reste celui de #218 et #317 : portions regroupées, puis doublons retirés, puis rangement par jour. Ses tests suivent.

### D6 — Le Bilan absorbe les 7 derniers jours (#350)

Après D5, la semaine se lisait à trois endroits : l'onglet Semaine de l'accueil, la feuille « 7 derniers jours » et le récap de la semaine écoulée. C'était trop pour un même sujet. Il n'en reste qu'un, le **Bilan**.

- **L'onglet Semaine du Bilan couvre les 7 derniers jours glissants**, aujourd'hui compris (`RecapPeriod.current`). Il reprend tout ce que montrait la feuille, qui disparaît :
  - l'en-tête et le verdict ;
  - un anneau par jour, qu'on touche pour choisir un jour ;
  - la chronologie des sorties de ce jour, chacune ouvrant son détail par un *push* (`NavigationStack`) ;
  - la comparaison avec les 7 jours d'avant.
- **Le mois reste le dernier mois terminé.** Ses jours se touchent aussi : le calendrier donne accès aux sorties de chacun.
- **Les sorties par jour viennent de la même lecture** que les récaps (`RecapStore.outings`, construites par `OutingDay.days(in:)`). L'ordre de #218 et #317 ne change pas.
- **L'accueil** :
  - l'onglet Semaine ne garde que ses quatre tuiles, et la rangée d'anneaux est retirée ;
  - « Voir le bilan » ouvre le Bilan sur la semaine, en passant par `RecapRouter` ;
  - la carte Récap montre les 7 derniers jours et se relit quand les minutes du jour bougent.
- **La notification de la semaine passe au dimanche à 19 h.** Une fenêtre glissante ne couvre du lundi au dimanche que le dimanche. Le lundi à 9 h, elle aurait couvert du mardi au lundi matin, presque vide. La notification du mois ne bouge pas.

**Écarté** : garder trois onglets (7 jours, semaine terminée, mois). La semaine terminée et les 7 derniers jours se recouvrent presque entièrement. Deux onglets aussi proches disent la même chose deux fois.

### D7 — L'hydratation dans le Bilan (#356)

Quand l'hydratation est activée, chaque onglet du Bilan se termine par un bloc **Hydratation** :

- la moyenne d'eau par jour sur toute la période, avec son écart sur la période d'avant (même puce que les autres mesures) ;
- les jours où l'objectif d'eau est tenu, sur le nombre de jours de la période.

Le calcul (`RecapWater.make`) est pur et testé. Il part des totaux quotidiens de `dietaryWater` (`waterSeries`, ADR 0005), lus en même temps que le reste du Bilan, sur la même profondeur.

- **La moyenne porte sur tous les jours de la période**, aujourd'hui compris pour la semaine glissante. Un jour sans eau notée compte pour zéro, comme un jour sans minutes compte dans le total.
- **Tous les jours comptent pour l'objectif d'eau**, pas seulement les jours actifs : on boit aussi les jours de repos.
- **Une lecture d'eau refusée n'empêche pas le Bilan** : le bloc disparaît, le reste s'affiche. Hydratation coupée, l'eau n'est pas lue du tout.

## Ce qui reste ouvert

- **Un récap sur la montre**, en complication ou à l'ouverture le lundi, si la version iPhone est adoptée.
