# FAQ — Foulée avec une montre Garmin

Foulée fonctionne avec une montre Garmin grâce à la synchronisation native
**Garmin Connect → Apple Santé** : ta montre envoie tes données à l'app Garmin
Connect, qui les écrit dans l'app Santé, où Foulée les lit — le tout sur ton
appareil. Foulée ne parle jamais aux serveurs Garmin (voir la
[politique de confidentialité](privacy.md)).

Avant tout, vérifie que l'autorisation est donnée **des deux côtés** — c'est
un aller-retour, et un seul « Ne pas autoriser » suffit à tout bloquer.

1. **Côté Garmin Connect** : ouvre les réglages puis la section **Apple
   Santé** (selon les versions : « Applications tierces » ou « Applications
   connectées ») et autorise le partage des pas, de la distance, des
   activités et de l'eau bue.
2. **Côté Santé** : ouvre **Santé → Profil (en haut à droite) → Partage et
   accès → Apps et services → Garmin Connect**, et vérifie que les
   catégories sont bien activées. Si tu as touché « Ne pas autoriser » sur
   la fenêtre affichée par Santé la première fois, c'est ici que ça se
   répare — Garmin Connect ne la repropose pas.

## Mes données du jour n'apparaissent pas (ou en retard)

C'est le cas de loin le plus fréquent. Garmin Connect synchronise **par
rafales**, principalement quand tu ouvres l'app : tant qu'elle n'a pas tourné,
tes données restent sur la montre et Santé (donc Foulée) ne les voit pas.
Selon les retours d'utilisateurs, le délai va de quelques minutes à parfois
24 h.

**La solution : ouvre Garmin Connect.** La synchro se déclenche, les données
arrivent dans Santé, et Foulée se met à jour au refresh suivant. Bonne
nouvelle : si des minutes arrivent après coup, ta série est **réparée
rétroactivement** — un jour validé en retard compte quand même.

## Ma série ne valide pas alors que j'ai marché

Si tes pas sont bien là mais que ta série refuse de valider, c'est
probablement que ta marche n'a **pas été enregistrée comme activité**.

Les « minutes d'exercice » d'Apple n'existent que si tu portes une Apple
Watch : aucune app tierce, Garmin comprise, ne peut en écrire. Foulée les
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

Garmin Connect n'écrit dans Apple Santé qu'**à partir du moment où tu actives
le partage** : il ne recopie pas ton historique Garmin passé. C'est une limite
de Garmin Connect, commune à toutes les apps qui lisent Santé — Foulée ne peut
pas y remédier. Tes statistiques se construisent à partir de l'activation.

## Mes pas sont comptés en double (montre + iPhone)

Si tu portes ta Garmin en gardant l'iPhone en poche, les deux comptent tes
pas. L'app Santé sait dédupliquer, mais elle suit un **ordre de priorité des
sources** que tu peux régler : ouvre **Santé → Parcourir → Activité → Pas →
Sources de données et accès**, puis touche **Modifier** et place ta source
préférée (Garmin Connect ou iPhone) en haut de la liste. Foulée lit les
totaux dédupliqués de Santé et reflète donc ce réglage.

## En cas de données manquantes

**Notre politique de support est simple : des données absentes de Foulée sont
presque toujours un problème de synchro Garmin ↔ Santé, à vérifier en
premier — pas un bug de l'app.** Le test : ouvre l'app Santé et cherche la
donnée manquante. Si elle n'y est pas, Foulée ne peut pas l'afficher — passe
par Garmin Connect (synchro, autorisations des deux côtés). Si elle y est mais
pas dans Foulée, vérifie d'abord qu'il ne s'agit pas des minutes d'exercice
(voir « Ma série ne valide pas alors que j'ai marché » : elles viennent de tes
activités enregistrées, pas de tes pas) — sinon, écris-nous :
**mattmar33@gmail.com**.
