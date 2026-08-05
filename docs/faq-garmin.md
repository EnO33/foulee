# FAQ — Foulée avec une montre Garmin

Foulée fonctionne avec une montre Garmin grâce à la synchronisation native
**Garmin Connect → Apple Santé** : ta montre envoie tes données à l'app Garmin
Connect, qui les écrit dans l'app Santé, où Foulée les lit — le tout sur ton
appareil. Foulée ne parle jamais aux serveurs Garmin (voir la
[politique de confidentialité](privacy.md)).

## Activer (ou réparer) le partage

Tout se règle **depuis l'app Santé**. C'est aussi par là que commence la page
d'aide de Garmin, et pour une bonne raison : ces libellés sont ceux d'Apple,
ils ne bougent pas d'une version de Garmin Connect à l'autre.

1. Ouvre **Santé**, onglet **Résumé**.
2. Touche ta **photo ou tes initiales**, en haut à droite.
3. Sous **« Confidentialité »**, touche **« Apps »**.
4. Touche **« Garmin Connect »** (l'app s'appelle aussi **« Connect »** selon
   les endroits) dans la liste.
5. **Active les catégories** : pas, distance, entraînements, fréquence
   cardiaque, calories — et eau si tu suis ton hydratation.

Si tu avais touché « Ne pas autoriser » sur la fenêtre affichée la première
fois, c'est ici que ça se répare : Garmin Connect ne la repropose pas.

### Garmin Connect n'apparaît pas dans la liste

Une app figure dans cette liste **dès qu'elle a demandé l'accès**, quelle
qu'ait été ta réponse. D'où le diagnostic :

- **Elle y est** → la demande a déjà eu lieu. Tout se règle dans Santé, tu n'as
  aucune raison d'aller dans Garmin Connect.
- **Elle n'y est pas** → l'app n'a jamais demandé. C'est le seul cas où il faut
  passer par Garmin Connect.

Dans ce cas, l'objectif est de **lancer la connexion depuis Garmin Connect**,
dans la section des applications connectées / tierces. Attention, on ne peut
pas te donner un chemin fiable : Garmin a renommé ce menu plusieurs fois, et
ses propres pages d'aide ne disent pas la même chose en français et en anglais.
Cherche une section du genre « Applications connectées », « Applications
tierces » ou « Connect Apps » dans les paramètres, puis Apple Santé parmi les
applications **disponibles** — l'entrée disparaît souvent une fois la connexion
établie, ce qui explique qu'on ne la retrouve pas toujours. Une fois la
connexion lancée, reprends la liste ci-dessus dans Santé pour vérifier les
catégories.

## Mes données du jour n'apparaissent pas (ou en retard)

C'est le cas de loin le plus fréquent, et c'est documenté par Garmin :
**l'app Garmin Connect doit être ouverte au premier plan pour envoyer des
données vers Santé.** Si elle est fermée, le transfert est mis en pause et ne
se termine qu'à la synchro suivante, app ouverte. Tant que ça n'a pas eu lieu,
tes données restent côté Garmin et Santé (donc Foulée) ne les voit pas.

**La solution : ouvre Garmin Connect.** La synchro se déclenche, les données
arrivent dans Santé, et Foulée se met à jour au refresh suivant. Bonne
nouvelle : si des minutes arrivent après coup, ta série est **réparée
rétroactivement** — un jour validé en retard compte quand même.

## Ma série ne valide pas alors que j'ai marché

Si tes pas sont bien là mais que ta série refuse de valider, c'est
probablement que ta marche n'a **pas été enregistrée comme activité**.

Les « minutes d'exercice » d'Apple n'existent que si tu portes une Apple
Watch : aucune app tierce, Garmin comprise, ne peut en écrire — Garmin précise
d'ailleurs que ses données ne font pas avancer les anneaux d'Apple. Foulée les
remplace donc par la **durée de tes activités enregistrées** — toutes
disciplines confondues, pas seulement la marche. C'est ce qui permet à une
montre Garmin de faire avancer ta série.

La conséquence : une marche que ta montre n'a comptée qu'en pas ne donne
aucune minute. **Enregistre ta marche comme une activité** sur la Garmin
(démarre l'activité « Marche » avant de partir), ou active la **détection
automatique d'activité** dans les réglages de ta montre pour qu'elle la crée
toute seule. Une fois l'activité synchronisée vers Santé, le jour se valide —
y compris rétroactivement.

## Mon historique d'avant l'installation est vide

Pas tout à fait : **à l'activation du partage, Santé importe tes données Garmin
des deux semaines précédentes**. Au-delà, en revanche, rien ne remonte —
Garmin Connect ne recopie pas ton historique complet. C'est une limite de
Garmin Connect, commune à toutes les apps qui lisent Santé, et Foulée ne peut
pas y remédier : tes statistiques se construisent à partir de là.

## Mes pas sont comptés en double (montre + iPhone)

Si tu portes ta Garmin en gardant l'iPhone en poche, les deux comptent tes
pas. L'app Santé sait dédupliquer, mais elle suit un **ordre de priorité des
sources**. Bonne nouvelle : une source qui vient d'être ajoutée est placée
**au-dessus de toutes les autres**, donc une Garmin fraîchement connectée
passe déjà devant l'iPhone.

Pour vérifier ou changer cet ordre : ouvre **Santé → Parcourir → Activité →
Pas → Sources de données et accès**, puis touche **Modifier** et place ta
source préférée (Garmin Connect ou iPhone) en haut de la liste. Foulée lit les
totaux dédupliqués de Santé et reflète donc ce réglage.

## En cas de données manquantes

**Notre politique de support est simple : des données absentes de Foulée sont
presque toujours un problème de synchro Garmin ↔ Santé, à vérifier en
premier — pas un bug de l'app.** Le test : ouvre l'app Santé et cherche la
donnée manquante. Si elle n'y est pas, Foulée ne peut pas l'afficher — reprends
« Activer (ou réparer) le partage » ci-dessus, puis ouvre Garmin Connect pour
déclencher une synchro. Si elle y est mais pas dans Foulée, vérifie d'abord
qu'il ne s'agit pas des minutes d'exercice (voir « Ma série ne valide pas alors
que j'ai marché » : elles viennent de tes activités enregistrées, pas de tes
pas) — sinon, écris-nous : **mattmar33@gmail.com**.
