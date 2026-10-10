# ADR 0004 — Récap de la semaine et du mois

- **Statut** : acceptée (2026-10)
- **Issues** : [#344](https://github.com/EnO33/foulee/issues/344)

## Contexte

L'accueil suit la journée en cours et les 7 derniers jours, mais rien ne fait le **bilan** d'une semaine ou d'un mois écoulés. Un bilan régulier donne une raison de revenir et de mesurer le chemin parcouru. Il demande deux choses : un écran de récap, et une notification qui l'annonce.

## Décisions

### D1 — Le récap porte sur la dernière période terminée

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

Chaque lundi et chaque 1er du mois à 9 h, une notification répétée (`UNCalendarNotificationTrigger`) annonce le récap. **Son texte ne cite aucun chiffre** : une notification est programmée à l'avance et ne peut pas lire Santé au moment où elle s'affiche. Elle annonce donc le récap au lieu de le citer, et les chiffres, toujours à jour, sont à un toucher.

Toucher la notification ouvre le bon récap. Le délégué de notifications, qui s'exécute avant qu'un écran existe, passe la demande à `RecapRouter`. L'accueil la présente ensuite (`RecapPresentation`), que le toucher ait lancé l'app ou l'ait trouvée ouverte. La carte « Tes récaps » de l'accueil passe par le même routeur : une seule façon d'ouvrir un récap.

La notification est **activée par défaut** et se coupe dans Réglages → Notifications.

**Écarté** : recalculer le texte de la notification en arrière-plan (`BGAppRefreshTask`) pour y mettre les chiffres. iOS ne garantit ni l'heure ni l'exécution d'une tâche de fond. Une notification qui affiche des chiffres faux, ou qui n'arrive pas, coûte plus cher qu'un texte fixe.

## Ce qui reste ouvert

- **Un récap sur la montre**, en complication ou à l'ouverture le lundi, si la version iPhone est adoptée.
