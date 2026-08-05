# FAQ — Foulée avec une montre Garmin

Foulée fonctionne avec une montre Garmin grâce à la synchronisation native
**Garmin Connect → Apple Santé** : ta montre envoie tes données à l'app Garmin
Connect, qui les écrit dans l'app Santé, où Foulée les lit — le tout sur ton
appareil. Foulée ne parle jamais aux serveurs Garmin (voir la
[politique de confidentialité](privacy.md)).

## Activer le partage (première connexion)

La connexion se lance **depuis Garmin Connect**, pas depuis Santé.

1. Ouvre **Garmin Connect**, onglet **« Plus »**.
2. Touche **« Paramètres »**, puis **« Applications connectées »**.
3. Touche **« Apple Health »** — l'entrée garde son nom anglais, même dans
   l'app en français.
4. Touche **« Se connecter avec Apple Health »**.
5. iOS affiche alors sa **fenêtre d'autorisation Santé** : **active les
   catégories** — pas, distance, entraînements, fréquence cardiaque, calories,
   et eau si tu suis ton hydratation.

Les libellés peuvent varier d'une version de Garmin Connect à l'autre : Garmin
a renommé ce menu plusieurs fois (« Applications tierces », « Connect Apps »).
Le chemin, lui, reste le même : les paramètres, puis les applications
connectées.

### Vérifier ou réparer, côté Santé

Une fois la connexion faite, tout se règle aussi depuis l'app Santé — ces
libellés-là sont ceux d'Apple et ne bougent pas :

1. Ouvre **Santé**, onglet **Résumé**.
2. Touche ta **photo ou tes initiales**, en haut à droite.
3. Sous **« Confidentialité »**, touche **« Apps »**.
4. Touche **« Garmin Connect »** (l'app s'appelle aussi **« Connect »** selon
   les endroits) dans la liste.
5. **Vérifie les catégories** : pas, distance, entraînements, fréquence
   cardiaque, calories — et eau si tu suis ton hydratation.

Si tu avais touché « Ne pas autoriser » sur la fenêtre d'autorisation, c'est
ici que ça se répare : Garmin Connect ne la repropose pas.

### Garmin Connect n'apparaît pas dans cette liste

C'est normal tant que la connexion n'a jamais été établie : une app entre dans
cette liste **quand elle a demandé l'accès**, quelle qu'ait été ta réponse —
jamais avant. D'où le diagnostic :

- **Elle n'y est pas** → la connexion n'a jamais été faite. Reprends
  « Activer le partage » ci-dessus, dans Garmin Connect.
- **Elle y est** → la demande a déjà eu lieu. Tout se règle dans Santé, même si
  tu avais refusé, sans retourner dans Garmin Connect.

## Mes données du jour n'apparaissent pas (ou en retard)

C'est le cas de loin le plus fréquent, et c'est documenté par Garmin :
**l'app Garmin Connect doit être ouverte au premier plan pour envoyer des
données vers Santé.** Compte **quelques minutes** avant de voir tes données
arriver (environ 5 lors de nos essais) : ce n'est pas instantané, et beaucoup
de gens concluent trop vite que rien ne marche.
Si elle est fermée, le transfert est mis en pause et ne
se termine qu'à la synchro suivante, app ouverte. Tant que ça n'a pas eu lieu,
tes données restent côté Garmin et Santé (donc Foulée) ne les voit pas.

**La solution : ouvre Garmin Connect.** La synchro se déclenche, les données
arrivent dans Santé, et Foulée se met à jour au refresh suivant. Bonne
nouvelle : si des minutes arrivent après coup, ta série est **réparée
rétroactivement** — un jour validé en retard compte quand même.

## Puis-je tester sans montre ?

Oui. Les données que tu saisis **à la main** dans Garmin Connect (un verre
d'eau, une activité créée manuellement) partent dans Santé exactement comme
celles d'une montre — Foulée ne fait aucune différence, puisqu'elle lit Santé
et jamais Garmin. C'est le moyen le plus simple de vérifier que ta connexion
fonctionne : saisis une activité, laisse Garmin Connect ouverte quelques
minutes, et regarde l'anneau des minutes bouger.

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
« Activer le partage » et « Vérifier ou réparer, côté Santé » ci-dessus, puis
ouvre Garmin Connect pour déclencher une synchro. Si elle y est mais pas dans Foulée, vérifie d'abord
qu'il ne s'agit pas des minutes d'exercice (voir « Ma série ne valide pas alors
que j'ai marché » : elles viennent de tes activités enregistrées, pas de tes
pas) — sinon, écris-nous : **mattmar33@gmail.com**.
