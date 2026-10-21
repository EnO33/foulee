# Fiche Connect IQ Store — français

Texte prêt à coller dans le formulaire de <https://apps.garmin.com/developer/upload>.
Ne pas l'y réécrire à la main : ce fichier est la version de référence, le
formulaire en est la copie.

---

## Nom

```
Foulée
```

## Description courte

```
Le compagnon montre de Foulée : tes compteurs du jour, envoyés à ton iPhone.
```

## Description complète

```
Foulée est une app iPhone qui t'aide à garder ta série de sorties quotidiennes.
Cette app Connect IQ en est le compagnon montre.

ELLE NE FONCTIONNE PAS TOUTE SEULE. Sans Foulée installée sur ton iPhone, elle
affiche tes compteurs du jour et enregistre tes séances, rien de plus : la
série, les objectifs, les rappels, la météo et l'historique vivent sur le
téléphone.

CE QU'ELLE FAIT
• Affiche ta série, puis tes pas et tes minutes actives face à tes objectifs,
  ta distance et tes calories du jour, aux couleurs de Foulée ; série et
  minutes aussi dans le glance, sur les modèles qui le gèrent.
• Met ta série sur ton cadran : une complication « Série Foulée » pour Face It
  et les cadrans qui les affichent.
• Lance une séance de marche ou de course depuis le poignet : chrono,
  distance, allure, fréquence cardiaque, une vibration à chaque kilomètre,
  pause, puis « Enregistrer » ou « Supprimer ». La montre l'enregistre
  elle-même et elle part dans Garmin Connect comme tes autres activités.
• Envoie à ton iPhone, toutes les cinq minutes et seulement quand il est à
  portée, cinq valeurs du jour : pas, distance, minutes actives, minutes
  actives intenses, calories — plus l'heure de la mesure, l'heure de début
  de ta journée sur la montre et trois repères techniques (type de message,
  version du format, numéro d'envoi). Pendant une séance, toutes les dix
  secondes, où elle en est pour l'écran de l'iPhone : marche ou course,
  heure, durée, distance, pas, fréquence cardiaque, pause, fin. À la fin
  d'une séance, son résumé : marche ou course, début, fin, durée, distance,
  pas, tracé allégé (64 points au plus). À chaque « J'ai bu », le verre : heure, quantité, identifiant. Rien
  d'autre ne quitte la montre. Hors de portée, elle attend le prochain passage — sans message
  d'erreur, sans vider ta batterie.

CE QU'ELLE NE FAIT PAS
• Aucun compte, aucune inscription, aucun réglage.
• Aucune donnée envoyée sur Internet. La montre parle à ton iPhone, point.
• Aucune notification. Hors séance, aucun GPS.

POURQUOI ELLE EXISTE
Ta montre Garmin mesure des minutes d'intensité qu'un iPhone seul ne voit
jamais. En les lui envoyant directement, Foulée peut tenir ta série aussi
fidèlement qu'avec une Apple Watch, et sans attendre la prochaine synchro de
Garmin Connect.

BATTERIE
La montre se réveille toutes les cinq minutes, lit ces cinq valeurs, et
n'envoie quelque chose que si elles ont bougé — une centaine d'octets. Pas de
GPS, pas de capteur allumé, pas d'écran réveillé. Le GPS et le capteur
cardiaque ne s'allument que pendant une séance.

CONFIDENTIALITÉ
Foulée est une app locale : rien ne part vers un serveur qui nous
appartiendrait, il n'y a aucun compte à créer, et rien n'est vendu à personne.
Politique complète : https://github.com/EnO33/foulee/blob/main/docs/privacy.md

SUPPORT
Une question, un bug : https://github.com/EnO33/foulee/issues
Réponse sous une semaine, en français ou en anglais.
```

## Notes de soumission (champ « Notes to reviewer »)

```
Cette app est le compagnon montre d'une app iPhone (Foulée). Elle lit
ActivityMonitor.getInfo() et transmet au téléphone, via Communications, un
instantané de cinq entiers : steps, distanceCm, activeMinutes,
activeMinutesVigorous, calories (plus « ts », un horodatage, « day », le
début de la journée locale de la montre, « gen », un compteur d'envoi, « t »,
le type de message, et « v », la version du format). À la fin d'une séance
enregistrée, elle transmet aussi son résumé (« t » = "summary" : sport,
début, fin, durée, distance, pas, tracé allégé à 64 points), et pendant la séance, toutes les dix
secondes, son état (« t » = "session" : sport, heure, durée, distance, pas,
fréquence cardiaque, pause, fin). À chaque « J'ai bu », elle transmet le verre
(« t » = "water" : identifiant, heure, quantité), que l'iPhone écrit dans
Santé. Rien d'autre n'est lu ni transmis, et elle ne contacte aucun serveur.

Elle enregistre aussi des séances de marche ou de course avec
ActivityRecording (permissions Fit, Positioning, Sensor) : GPS et capteur
cardiaque ne sont allumés que pendant la séance, et l'activité est enregistrée
dans Garmin Connect comme une activité native. La position ne part au
téléphone que dans le tracé allégé du résumé ; la fréquence cardiaque du
moment ne l'est que dans l'état de séance, pour l'écran de l'iPhone.

Le canal iOS ne peut pas être démontré dans le simulateur Connect IQ, qui ne
relaie les échanges compagnon que vers Android (ADB). Sans iPhone appairé,
l'app affiche simplement les compteurs du jour et n'émet rien.
```

## Champs annexes

| Champ | Valeur |
|---|---|
| Catégorie | Health & Fitness (« Santé et forme ») |
| Type d'app | Watch App |
| Site web / support | <https://github.com/EnO33/foulee/issues> |
| Politique de confidentialité | <https://github.com/EnO33/foulee/blob/main/docs/privacy.md> |
| Prix | Gratuit |
| ANT+ | Non |
