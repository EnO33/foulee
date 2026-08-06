# Politique de confidentialité — Foulée

_Dernière mise à jour : 6 août 2026_

Foulée est une application **locale**. Elle t'aide à entretenir une série de
sorties — marche ou course — à partir de tes données d'activité. **Aucune
donnée n'est envoyée vers un serveur qui nous appartiendrait, et il n'y a aucun
compte à créer.** Tout reste sur tes appareils : ton iPhone, ton Apple Watch, et ta
montre Garmin si tu y installes l'app Connect IQ de Foulée.

## Données de santé (HealthKit)

Avec ton autorisation, Foulée **lit** depuis l'app Santé : tes pas, ta distance,
tes minutes d'exercice, tes calories actives, ta fréquence cardiaque, l'eau que
tu as bue et tes séances. Ces données servent uniquement à afficher tes
statistiques dans l'app et à calculer ta série.

Foulée **écrit** aussi dans l'app Santé, si tu le souhaites : tes sorties
(sous forme de séances) et l'eau que tu enregistres dans le suivi
d'hydratation.

Ces données de santé **ne quittent jamais ton appareil** : elles ne sont ni
transmises à un tiers, ni stockées ailleurs que dans l'app Santé d'Apple, que tu
contrôles entièrement.

## Montres Garmin

Si tu portes une montre Garmin, tes données arrivent dans Foulée **par l'app
Santé**, comme toutes les autres : c'est Garmin Connect qui les y écrit, et
Foulée les lit sur ton appareil, sans faire de différence de source.

Foulée **ne communique jamais avec les serveurs Garmin** : aucune connexion à
un compte Garmin, aucune API Garmin, aucun échange avec un serveur — ni le
nôtre, ni celui de Garmin. La promesse reste inchangée — tes données de santé
**ne quittent jamais tes appareils**.

### L'app Foulée pour montre Garmin (Connect IQ)

Foulée propose aussi une petite app à installer **sur la montre elle-même**,
depuis le Connect IQ Store. Elle est facultative : sans elle, tout continue de
fonctionner par l'app Santé, comme décrit ci-dessus.

**Ce qu'elle lit sur la montre** — uniquement les compteurs du jour que la
montre tient déjà (`ActivityMonitor`) : tes pas, ta distance, tes minutes
actives, tes minutes actives intenses et tes calories. Pas de GPS, pas de
fréquence cardiaque, pas de séances, aucun capteur allumé pour l'occasion.

**Ce qu'elle envoie** — un instantané de ces **cinq valeurs**, plus l'heure de
la mesure, le numéro de version du format et un numéro d'envoi qui permet à
l'iPhone d'ignorer un instantané qu'il a déjà reçu. Le tout part **directement
vers ton iPhone par Bluetooth**, au plus une fois toutes les cinq minutes, et
**seulement si ces valeurs ont changé** depuis le dernier envoi. Quand le
téléphone n'est pas à portée, la montre n'envoie rien et attend simplement le
prochain passage.

**Ce qu'elle n'envoie pas** — rien ne part vers les serveurs de Garmin, ni vers
les nôtres (nous n'en avons pas). Il n'y a aucun compte à créer dans cette app,
aucun réglage, et rien n'est enregistré ailleurs que sur la montre et sur ton
iPhone.

Une fois arrivées sur l'iPhone, ces valeurs suivent exactement le même chemin
que les autres : elles servent à afficher tes statistiques et à calculer ta
série, et restent sur ton appareil.

**Elle ne sert à rien sans l'app iPhone.** Installée seule, elle se contente
d'afficher tes compteurs du jour sur la montre.

## Localisation

Avec ton autorisation, Foulée utilise ta position **uniquement pendant que
l'app est ouverte** (« lorsque l'app est active ») pour deux usages :

- afficher la **météo** à ton endroit ;
- tracer le **parcours** de ta sortie en cours sur une carte.

Pour la météo, tes coordonnées sont transmises à **Apple WeatherKit**, qui
renvoie les conditions locales (voir la
[politique de confidentialité d'Apple](https://www.apple.com/legal/privacy/)).
Le tracé de la sortie reste sur ton appareil pendant la séance et n'est ni
enregistré durablement, ni partagé.

## Mouvement et forme

Foulée utilise le **podomètre** (CoreMotion) pour compter tes pas en direct
pendant ta sortie. Ces données sont traitées localement, en temps réel.

## Ce que Foulée ne fait pas

- ❌ Aucun compte, aucune inscription, aucune adresse e-mail collectée.
- ❌ Aucun outil d'analyse, aucun traceur tiers, aucune publicité.
- ❌ Aucune vente ni aucun partage de tes données.

## Préférences

Tes réglages (objectif, activité, fenêtre, thème, rappels) sont enregistrés
**localement** sur ton appareil. Désinstaller l'app les supprime.

## Manifeste de confidentialité Apple

L'app et ses extensions (widgets, app Watch) embarquent un **manifeste de
confidentialité** (`PrivacyInfo.xcprivacy`), le format standard d'Apple pour
déclarer ce qu'une app fait de tes données. Celui de Foulée déclare :

- **aucun pistage** et aucun domaine de pistage ;
- **aucune donnée collectée** — rien ne quitte ton appareil ;
- un seul accès à une API dite « à raison obligatoire » : les **préférences
  locales** (UserDefaults), utilisées pour tes réglages et partagées entre
  l'app et ses widgets via un groupe d'apps, toujours sur ton appareil.

## Tes choix

Comme tout est local, tu gardes le contrôle à tout moment via les **Réglages
iOS** :

- **Confidentialité et sécurité → Santé → Foulée** pour l'accès aux données de santé ;
- **Confidentialité et sécurité → Service de localisation → Foulée** pour la localisation ;
- **Notifications → Foulée** pour les rappels.

Supprimer l'application efface toutes les préférences qu'elle a stockées. Les
données dans l'app Santé restent gérées par Santé.

## Contact

Une question sur cette politique ? Écris à **mattmar33@gmail.com**.
