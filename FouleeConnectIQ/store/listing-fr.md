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
affiche tes compteurs du jour et rien d'autre : la série, les rappels, la météo
et l'historique vivent sur le téléphone.

CE QU'ELLE FAIT
• Affiche tes pas, ta distance et tes minutes actives du jour sur la montre ;
  pas et minutes actives aussi dans le glance, sur les modèles qui le gèrent.
• Envoie à ton iPhone, toutes les cinq minutes et seulement quand il est à
  portée, cinq valeurs du jour : pas, distance, minutes actives, minutes
  actives intenses, calories — plus l'heure de la mesure et deux repères
  techniques (version du format, numéro d'envoi). Rien d'autre ne quitte la
  montre. Hors de portée, elle attend le prochain passage — sans message
  d'erreur, sans vider ta batterie.

CE QU'ELLE NE FAIT PAS
• Aucun compte, aucune inscription, aucun réglage.
• Aucune donnée envoyée sur Internet. La montre parle à ton iPhone, point.
• Aucun enregistrement d'activité, aucun GPS, aucune notification.

POURQUOI ELLE EXISTE
Ta montre Garmin mesure des minutes d'intensité qu'un iPhone seul ne voit
jamais. En les lui envoyant directement, Foulée peut tenir ta série aussi
fidèlement qu'avec une Apple Watch, et sans attendre la prochaine synchro de
Garmin Connect.

BATTERIE
La montre se réveille toutes les cinq minutes, lit ces cinq valeurs, et
n'envoie quelque chose que si elles ont bougé — une centaine d'octets. Pas de
GPS, pas de capteur allumé, pas d'écran réveillé.

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
activeMinutesVigorous, calories (plus « ts », un horodatage, « gen », un
compteur d'envoi, et « v », la version du format). Rien d'autre n'est lu ni
transmis, et elle ne contacte aucun serveur.

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
