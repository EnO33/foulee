# Politique de confidentialité — Foulée

_Dernière mise à jour : 26 octobre 2026_

Foulée est une application **locale**. Elle t'aide à entretenir une série de
sorties — marche ou course — à partir de tes données d'activité. **Aucune
donnée n'est envoyée vers un serveur qui nous appartiendrait, et il n'y a aucun
compte à créer.** Tout reste sur tes appareils : ton iPhone, ton Apple Watch, et ta
montre Garmin si tu y installes l'app Connect IQ de Foulée.

## Données de santé (HealthKit)

Avec ton autorisation, Foulée **lit** depuis l'app Santé : tes pas, ta distance,
tes minutes d'exercice, tes calories actives, ta fréquence cardiaque, l'eau que
tu as bue, tes séances et leur parcours. Ces données servent uniquement à
afficher tes statistiques et tes sorties dans l'app, et à calculer ta série.
L'écran Hydratation affiche aussi chaque verre du jour avec le nom de l'app qui
l'a enregistré dans Santé.

Foulée **écrit** aussi dans l'app Santé, si tu le souhaites : tes sorties
(sous forme de séances, avec leur parcours quand elles sont enregistrées sur
l'Apple Watch) et l'eau que tu enregistres dans le suivi d'hydratation.
Quand tu **annules un verre**, Foulée supprime de Santé l'enregistrement
qu'elle vient d'écrire, et seulement celui-là : Santé ne permet pas à une app
de supprimer les données écrites par une autre.

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
actives, tes minutes actives intenses et tes calories. En dehors d'une
séance, pas de GPS, pas de fréquence cardiaque, aucun capteur allumé pour
l'occasion.

**Pendant une séance que tu lances sur la montre** — la montre enregistre
elle-même l'activité, avec son propre enregistreur, comme ses apps de sport :
durée, distance, **position GPS** et **fréquence cardiaque**. Le GPS et le
capteur cardiaque ne sont allumés que de « Démarrer » à « Enregistrer » ou
« Supprimer ». Une séance enregistrée part dans **Garmin Connect** comme
n'importe quelle activité de ta montre, et Garmin Connect l'écrit dans Santé ;
une séance supprimée ne laisse aucune trace. L'app Foulée de la montre ne garde
de la position que le tracé de la séance, allégé, pour ton iPhone (ci-dessous) :
il ne reste sur la montre que le temps que l'iPhone le reçoive.

**Pendant la séance**, quand ton iPhone est à portée, elle lui envoie aussi
toutes les dix secondes, ainsi qu'à la pause, à la reprise et à la fin, où en
est la séance : marche ou course, heure du relevé, durée, distance, pas,
**fréquence cardiaque du moment**, en pause ou non, terminée ou non. L'iPhone
l'affiche sur son écran de séance en cours et ne la garde pas une fois la
séance finie. Seul l'état « terminée » attend que l'iPhone l'ait reçu, pour
que son écran ne reste pas ouvert.

**Ce qu'elle envoie** — un instantané de ces **cinq valeurs**, plus l'heure de
la mesure, l'heure de début de ta journée sur la montre (pour compter les
valeurs sur le bon jour quand montre et téléphone ne sont pas dans le même
fuseau horaire), le type de message, le numéro de version du format et un
numéro d'envoi qui permet à l'iPhone d'ignorer un instantané qu'il a déjà
reçu. Le tout part **directement
vers ton iPhone par Bluetooth**, au plus une fois toutes les cinq minutes, et
**seulement si ces valeurs ont changé** depuis le dernier envoi. Quand le
téléphone n'est pas à portée, la montre n'envoie rien et attend simplement le
prochain passage.

**À la fin d'une séance enregistrée**, elle envoie aussi son résumé : marche ou
course, heure de début et de fin, durée, distance, montée et descente, pas et **le tracé de la
séance**, réduit à 64 points au plus. Il sert à l'iPhone à afficher la sortie
et sa carte en attendant que Garmin Connect l'écrive dans Santé, qui la reçoit
sans tracé. Le résumé attend sur la montre que l'iPhone l'ait reçu (avec les
fins de séance et les verres, les trente-deux derniers messages au plus) ; la
fréquence cardiaque n'en fait pas partie. L'iPhone garde le tracé avec la
sortie en attente, et l'oublie avec elle.

**Quand tu touches « J'ai bu »** dans le menu de la montre, elle envoie le
verre : son heure, sa quantité et un identifiant. La montre ne peut pas
écrire dans Santé : c'est l'iPhone qui l'y écrit, avec cet identifiant, pour
qu'un verre reçu deux fois ne compte qu'une fois.

**Sur ton cadran**, si tu y ajoutes la complication « Série Foulée », la
montre affiche ta série. La complication est publique, comme celles de la
montre : tout cadran installé peut la lire. Elle ne quitte pas la montre.

**Ce qu'elle reçoit** — de ton iPhone, et par le même lien Bluetooth : ta
série, tes objectifs de pas et de minutes, ton choix marche / course et tes
réglages d'hydratation (activée ou non, objectif, taille d'un verre). C'est ce
que l'Apple Watch reçoit déjà. Pendant une séance, si tu touches « Arrêter la
séance » sur l'iPhone, la montre reçoit aussi l'ordre de l'enregistrer. La montre garde le dernier état reçu pour
l'afficher hors de portée du téléphone.

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

Avec ton autorisation (« lorsque l'app est active »), Foulée utilise ta
position pour deux usages, et jamais en dehors :

- afficher la **météo** à ton endroit, sur l'iPhone ;
- tracer le **parcours** de ta sortie sur une carte, sur l'iPhone ou sur
  l'Apple Watch — **pendant la sortie seulement**. Sur la montre, la position
  n'est demandée qu'au démarrage d'une sortie et n'est plus lue une fois la
  sortie terminée. Il en va de même sur une **montre Garmin** : le GPS n'y
  est allumé que pendant une séance, et le parcours reste dans l'activité
  enregistrée par la montre (voir « Montres Garmin »).
  Pendant une sortie lancée sur la montre, son parcours est aussi envoyé à
  **ton iPhone**, directement entre tes deux appareils, pour l'afficher sur la
  carte de la séance.
  À l'inverse, pendant une sortie lancée sur l'iPhone, son parcours et ses
  chiffres (durée, pas, distance, calories) sont envoyés à **ton Apple Watch**,
  directement entre tes deux appareils, pour l'afficher au poignet.

Pour la météo, tes coordonnées sont transmises à **Apple WeatherKit**, qui
renvoie les conditions locales (voir la
[politique de confidentialité d'Apple](https://www.apple.com/legal/privacy/)).

Le parcours d'une sortie faite avec l'**Apple Watch** est enregistré **dans
l'app Santé**, avec la séance, comme le fait l'app Forme d'Apple : c'est ce qui
permet de le revoir sur une carte dans Foulée, dans Forme ou dans toute app à
laquelle tu donnes accès à Santé. Il reste sur tes appareils, dans Santé, que
tu contrôles entièrement, et n'est envoyé à personne. Le parcours tracé par
l'iPhone, lui, n'est pas conservé après la sortie.

## Mouvement et forme

Foulée utilise le **podomètre** (CoreMotion) pour compter tes pas en direct
pendant ta sortie et, sur l'**Apple Watch**, pour lire ta cadence et ton allure
du moment : elles s'affichent au poignet et aident à reconnaître si tu marches
ou si tu cours. Ces données sont traitées localement, en temps réel.

Avec ton autorisation, Foulée lit aussi la **détection de mouvement** du
système pour reconnaître toute seule si tu marches ou si tu cours :

- sur l'**Apple Watch**, pendant la séance, pour afficher le sport en cours ;
- sur l'**iPhone**, une seule fois **à l'arrêt de la séance**, en relisant
  l'historique de la sortie qui vient de se terminer — rien n'est lu pendant
  que tu marches, et rien ne tourne en arrière-plan.

Dans les deux cas, la lecture sert à enregistrer ta sortie sous le bon sport
dans Santé. Rien n'est transmis, rien n'est conservé en dehors de la séance
elle-même.

Pendant une séance, le **baromètre** de l'iPhone et de l'Apple Watch mesure le
dénivelé que tu gravis et celui que tu descends. Seuls ces deux totaux sont
gardés : ils sont enregistrés avec la séance dans Santé, comme sa distance.

## Ce que Foulée ne fait pas

- ❌ Aucun compte, aucune inscription, aucune adresse e-mail collectée.
- ❌ Aucun outil d'analyse, aucun traceur tiers, aucune publicité.
- ❌ Aucune vente ni aucun partage de tes données.

## Préférences

Tes réglages (objectif, activité, fenêtre, thème, rappels) sont enregistrés
**localement** sur ton appareil. Désinstaller l'app les supprime.

Le **bilan** des 7 derniers jours et du mois est calculé sur ton iPhone, à partir des
données Santé que Foulée lit déjà. Sa notification est programmée localement :
rien n'est envoyé nulle part pour la produire.

La **notification qui suit une séance** arrivée d'une montre se calcule de la
même façon : ton iPhone compare la sortie à celles des six derniers mois, lues
dans Santé, et programme lui-même la notification. Rien ne quitte ton iPhone
pour l'écrire.

Quand tu **fusionnes deux sorties**, Foulée retient sur ton iPhone quelles
séances n'en font qu'une, et rien d'autre : Santé n'est pas modifié, et la
fusion ne quitte pas ton iPhone. Séparer les sorties efface ce lien.

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
- **Confidentialité et sécurité → Service de localisation → Foulée** pour la localisation, sur l'iPhone comme sur l'Apple Watch ;
- **Notifications → Foulée** pour les rappels.

Supprimer l'application efface toutes les préférences qu'elle a stockées. Les
données dans l'app Santé restent gérées par Santé.

## Et ce site ?

getfoulee.app est hébergé par **Cloudflare**. Pour savoir combien de personnes
le visitent, il utilise **Cloudflare Web Analytics**, une mesure d'audience
**sans cookie** :

- rien n'est enregistré dans ton navigateur, ni cookie ni stockage local ;
- ni ton adresse IP ni ton navigateur ne servent à te reconnaître d'une visite
  à l'autre ;
- seuls des totaux sont gardés : pages vues, site d'où tu arrives, pays, type
  d'appareil et de navigateur, temps de chargement.

Ce que tu fais sur le site n'est jamais relié à l'app, qui n'envoie toujours
rien.

## Contact

Une question sur cette politique ? Écris à **contact@getfoulee.app**.
