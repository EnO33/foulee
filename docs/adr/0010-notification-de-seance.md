# ADR 0010 — Une notification à l'arrivée de chaque séance

- **Statut** : acceptée (2026-10)
- **Issues** : [#525](https://github.com/getfoulee/foulee/issues/525), [#526](https://github.com/getfoulee/foulee/issues/526), [#527](https://github.com/getfoulee/foulee/issues/527), [#528](https://github.com/getfoulee/foulee/issues/528), [#529](https://github.com/getfoulee/foulee/issues/529), [#530](https://github.com/getfoulee/foulee/issues/530), [#531](https://github.com/getfoulee/foulee/issues/531)

## Contexte

Une sortie faite avec une montre (Garmin, Apple Watch, Foulée montre) arrive dans Foulée sans que rien ne le dise, et rien ne la situe par rapport aux précédentes. L'idée de départ comptait trois notifications : « séance importée », « séance traitée, récap disponible », et un message motivant. Trois messages pour un même moment, c'est du bruit.

## Décisions

### D1 — Une seule notification par sortie

Elle part quand la sortie arrive dans Santé, ou dès que la montre Garmin l'envoie. Son **titre** donne le repère le plus motivant du moment, son **texte** les chiffres, et son **toucher** ouvre la sortie (D5). Elle dit à elle seule que la sortie est bien arrivée.

Une sortie enregistrée sur l'iPhone n'en a pas : le téléphone est en main, et l'écran de fin dit la même chose (D6).

### D2 — Un repère vrai, jamais négatif

`SessionBenchmark` situe la sortie parmi celles de **la même activité** sur **6 mois glissants** ; `SessionHighlight` choisit un seul repère, dans cet ordre :

1. un record sur 6 mois : la plus longue, le plus gros dénivelé (randonnée), le rythme le plus rapide ;
2. un rythme meilleur d'au moins 2 % que la moyenne, pondérée par la distance ;
3. une tendance : les 4 dernières semaines meilleures d'au moins 2 % que les mois d'avant ;
4. la régularité : le mois déjà au-dessus du précédent, la nième sortie de la semaine ;
5. sinon, la sortie elle-même et ses chiffres.

Il faut au moins 3 sorties comparables. Un rythme plus lent n'est jamais dit : le repère suivant parle. Le rythme ne compte ni la randonnée (la pente compte plus que le marcheur), ni une sortie de moins de 1 km, ni une sortie qui change de sport.

L'angle de la notification précédente cède la place à un autre quand il y en a un. Un record passe toujours : c'est une nouvelle.

### D3 — Le texte se calcule à l'arrivée

Contrairement au récap (ADR 0004, D3), le texte cite des chiffres : il est écrit au réveil Santé qui apporte la sortie, avec les données du moment, et part une minute plus tard. Rien n'est programmé à l'avance.

### D4 — Un registre des sorties annoncées

Une même sortie se présente plusieurs fois : segment par segment (#316), d'abord depuis la montre Garmin puis par Garmin Connect (ADR 0009), et à chaque réveil Santé. `SessionAnnouncements` garde les sorties annoncées ; une sortie qui en chevauche ou en touche une est celle-là.

- La notification part **une minute** après ; un segment qui arrive dans cette minute la remplace sous le même identifiant.
- Rien pour une sortie terminée il y a plus de **6 h**, ni avant la première ouverture de cette version : pas de rafale à la mise à jour.
- Coupée dans Réglages, la notification n'est plus envoyée mais le registre suit : la rallumer n'annonce rien de ce qui est arrivé entre-temps.

Le registre vit dans les `UserDefaults`, lu et écrit sous un verrou : plusieurs séances d'une même synchronisation Garmin réveillent l'observateur en même temps.

### D5 — Le toucher ouvre la sortie dans le Bilan

La fiche d'une sortie vit dans le Bilan. Le toucher ouvre le Bilan sur la semaine de la sortie, puis pousse sa fiche une fois la semaine lue, quelle que soit la copie gardée. Une sortie que Santé n'a plus laisse le Bilan ouvert.

### D6 — L'écran de fin iPhone dit le même repère

À la fin d'une séance iPhone, une fois la sortie relue dans Santé, l'écran de fin affiche son repère. Rien quand il n'y a que ses chiffres, déjà à l'écran, ni quand l'enregistrement a échoué.

La notification est **activée par défaut** et se coupe dans Réglages → Notifications (« Après une séance »).
