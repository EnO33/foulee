# Foulée Connect IQ (Monkey C)

App Garmin de Foulée, l'équivalent de l'app Apple Watch (ADR 0009) : l'accueil du jour (série, objectifs), une séance lancée depuis le poignet et enregistrée par la montre elle-même, et un instantané compact des compteurs du jour (`Toybox.ActivityMonitor`) poussé vers l'iPhone toutes les 5 minutes.

Voir [ADR 0001](../docs/adr/0001-garmin-integration.md) (phase 2) et les issues [#188](https://github.com/EnO33/foulee/issues/188) / [#179](https://github.com/EnO33/foulee/issues/179).

Ce dossier est **hors du build Tuist / Xcode** : il n'est référencé par aucune cible Swift et ne participe pas à `tuist generate`.

## Ce que fait l'app

| Élément | Rôle |
|---|---|
| `source/DailySnapshot.mc` | Assemblage pur de l'instantané (lecture des métriques, génération, payload). Aucune E/S. |
| `source/SnapshotService.mc` | Service d'arrière-plan : lit, persiste, décide, transmet ; stocke l'état de l'iPhone reçu app fermée. |
| `source/FouleeGlanceView.mc` | Glance : série + minutes actives / objectif (les pas tant que l'iPhone n'a rien envoyé). |
| `source/FouleeView.mc` | Accueil, comme `WatchTodayView` : série, pas / objectif, minutes / objectif, km, kcal ; « Ouvre Foulée sur ton iPhone » avant la première synchro. |
| `source/HomeFormat.mc` | Textes de l'accueil et du glance : progression vers l'objectif, série, largeur disponible sur un cadran rond. |
| `source/MetricPalette.mc` | Couleurs des chiffres, celles de l'iPhone ; les écrans MIP 64 couleurs les ramènent à leur palette. |
| `source/SnapshotFormat.mc` | Formatage dans la langue de la montre : espace et virgule en français, virgule et point en anglais. |
| `source/PhoneSync.mc` | État envoyé par l'iPhone (série, objectifs, mode, hydratation) : décodage tolérant et stockage (ADR 0009, D5), app ouverte ou fermée. |
| `source/SessionMath.mc` | Arithmétique d'une séance : chrono, allure, alerte au kilomètre (ADR 0009, D9). |
| `source/SessionRecorder.mc` | Enregistrement de la séance par l'enregistreur FIT de la montre (`ActivityRecording`), GPS et cardio allumés pendant la séance seulement (D2). |
| `source/SessionFlow.mc`, `source/SessionDelegates.mc` | « Démarrer » depuis l'accueil (choix Marche / Course en mode « Les deux »), pause en `Menu2` : Reprendre, Enregistrer, Supprimer (avec confirmation). |
| `source/SessionMessage.mc`, `source/Outbox.mc` | Résumé de fin de séance pour l'iPhone (ADR 0009, D2), gardé dans une file d'envoi jusqu'à sa réception ; le service d'arrière-plan réessaie toutes les 5 minutes. |
| `source/SessionView.mc` | Page Séance : chrono, distance, allure, fréquence cardiaque, vibration et kilomètre affiché à chaque borne. |
| `source/SessionPages.mc` | Pages de la séance en `ViewLoop` : Séance, puis Journée (l'accueil). |
| `source/SummaryView.mc` | Résumé d'une séance enregistrée : durée, pas, distance, « Terminer » vers l'accueil. |
| `source/*Test.mc` | Tests unitaires Run No Evil. |
| `build.sh` | Point d'entrée : `validate`, `build`, `test`, `package`. |
| `tools/validate_project.py` | Contrôles statiques sans SDK — ce que lance la CI. |
| `tools/device_catalog.py`, `devices.json` | Catalogue des montres compatibles, depuis les profils Garmin, et la matrice qui en sort (voir « Matrice d'appareils »). |
| `tools/render_icons.py` | Icônes de lancement par famille d'écran, et icônes du store. |
| `store/` | Fiche Connect IQ Store (FR + EN) et procédure de publication. |

### Métriques lues

`ActivityMonitor.getInfo()` → `steps`, `distance` (cm), `calories`, et surtout **`activeMinutesDay`** (`total` / `vigorous`), l'équivalent Garmin natif des minutes d'exercice — la métrique qui rend le streak de Foulée possible pour un porteur de Garmin.

Chaque champ est gardé deux fois : `info has :champ` (les familles n'exposent pas les mêmes symboles) puis contrôle de type/nullité dans `DailySnapshot.asCount`. Une famille qui ne remonte rien produit un instantané à zéro, jamais une exception.

### Instantané transmis

```json
{
  "t": "snapshot",
  "v": 2,
  "steps": 8421,
  "distanceCm": 634000,
  "activeMinutes": 47,
  "activeMinutesVigorous": 12,
  "calories": 2103,
  "ts": 1754380800,
  "day": 1754344800,
  "gen": 7
}
```

- `t` : type de message. D'autres types partageront le lien (ADR 0009, D6).
- `ts` : epoch en secondes.
- `day` : début de la journée locale **de la montre** (`Time.today()`), en
  epoch. Ses compteurs repartent à son minuit à elle, qui n'est pas celui du
  téléphone quand les deux ne sont pas dans le même fuseau (#473). L'iPhone
  accepte aussi la v1, sans `t` ni `day`, des montres pas encore mises à jour.
- `gen` : compteur monotone **qui n'avance que si les métriques ont bougé**. Un instantané qui n'est pas arrivé est donc retransmis sous la *même* génération, et l'iPhone peut ignorer une génération déjà ingérée. C'est ce qui rend l'échange idempotent (côté iOS : #189).
- Clés courtes, valeurs entières hors `t` : le lien BLE tourne autour de 1 ko/s.

### Absence de téléphone

Une montre hors de portée du téléphone est le **cas normal**, pas une erreur. Le service :

1. vérifie `System.getDeviceSettings().phoneConnected` avant de dépenser du budget BLE ;
2. implémente `ConnectionListener.onError()`, qui se contente de terminer le service ;
3. ne réessaie qu'au prochain événement temporel — pas de boucle, pas de spam, pas de message d'erreur.

Le glance et la vue plein écran ne touchent jamais au téléphone : elles s'affichent à l'identique sans aucun appairage.

## Prérequis

- SDK Connect IQ 9.3.0 : `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.3.0-2026-10-20-95888f262`
- Un JDK (le SDK est en Java). Sur cette machine : `export JAVA_HOME=/opt/homebrew/opt/openjdk@21`
- Une **clé développeur**, générée hors du dépôt (elle ne doit jamais y entrer) :

```sh
mkdir -p $HOME/.garmin
openssl genrsa -out $HOME/.garmin/foulee_developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
  -in $HOME/.garmin/foulee_developer_key.pem \
  -out $HOME/.garmin/foulee_developer_key.der -nocrypt
```

## Compiler

```sh
./build.sh build            # tous les appareils du manifeste, dans bin/
./build.sh build venu2      # un seul
```

`build.sh` retrouve seul le SDK (via `current-sdk.cfg`), le JDK et la clé, et
sort les `.prg` dans `bin/`. Sous le capot, pour un appareil :

```sh
"$SDK/bin/monkeyc" -f monkey.jungle -d fenix843mm \
  -o bin/foulee-fenix843mm.prg \
  -y $HOME/.garmin/foulee_developer_key.der -w -l 3
```

`-w` active les avertissements, `-l 3` le contrôle de types **strict** (même exigence que SwiftLint/Periphery côté iOS). Tous les appareils du manifeste compilent proprement à ce niveau.

Le script va plus loin que `monkeyc` : il **échoue sur tout avertissement**,
sans exception ni dispense. C'est l'équivalent Monkey C de `swiftlint --strict`,
et c'est ce qui fait de `./build.sh build` la barrière qualité du dossier, en
local comme en CI (section suivante).

Trois réglages, si besoin : `CIQ_SDK_HOME`, `CIQ_DEVELOPER_KEY`, `JAVA_HOME`.

## Simulateur

```sh
"$SDK/bin/connectiq"                       # lance le simulateur (GUI)
"$SDK/bin/monkeydo" bin/foulee-venu2.prg venu2   # ./build.sh build venu2 d'abord
```

Le simulateur doit tourner *avant* `monkeydo`, et il vaut mieux le relancer entre deux sessions : il garde l'app précédente chargée et `monkeydo` reste alors bloqué.

Le service d'arrière-plan se déclenche à la main via le menu **Simulation → Trigger Background Event** (interface graphique uniquement).

## Tests unitaires

```sh
./build.sh test             # compile bin/foulee-test-venu2.prg
"$SDK/bin/connectiq"
"$SDK/bin/monkeydo" bin/foulee-test-venu2.prg venu2 -t
```

Cinq tests couvrent l'assemblage de l'instantané à partir d'une structure `info` injectée (`FakeActivityInfo`), les champs absents ou nuls, la stabilité de la génération entre deux essais, la coercition des compteurs et le formatage français.

`monkeydo` a besoin du simulateur, donc ce n'est pas headless au sens strict, mais tout se pilote depuis le terminal.

## Intégration continue

Deux jobs de [`ci.yml`](../.github/workflows/ci.yml) couvrent ce dossier, sur
chaque PR qui le touche (ou qui touche `ci.yml`, l'action `prepare-connectiq`
ou les identifiants côté iPhone) : le job `Changes` les saute sinon, et ne lance
pas les jobs de l'app iOS pour une PR qui ne touche que ce dossier.

### `Connect IQ build` : la compilation

Il compile tous les appareils du manifeste avec `./build.sh build` (donc en
`-w -l 3`, sans aucun avertissement toléré),
puis la version de tests unitaires avec `./build.sh test`. Il signe avec une
clé jetable générée pour le job : compiler demande une clé, pas *la* clé, qui
ne sert qu'au paquet du store.

Le SDK se télécharge sans compte, mais les **profils d'appareils** demandent
un jeton de compte Garmin. Ils viennent de
[`connect-iq-sdk-manager`](https://github.com/lindell/connect-iq-sdk-manager-cli)
(version et somme SHA-256 épinglées dans le job), puis restent en cache
(`actions/cache`, clé : version du SDK + empreinte du manifeste). Le jeton ne
sert donc qu'au premier remplissage du cache, ou quand la matrice change. Il
n'est jamais mis en cache, et les profils ne sont jamais committés : l'accord
Connect IQ interdit de les redistribuer (§ I(b)).

#### Mise en place, une fois

1. Installer l'outil, dans la même version et avec la même vérification qu'en
   CI. Le tap Homebrew de l'auteur ne convient pas : sa formule est restée en
   0.7.1, et son cask déclare un binaire qui n'est pas dans l'archive.

   ```sh
   # Apple Silicon ; sur Intel : Darwin_x86_64 et d355fb6f…7315749.
   archive=connect-iq-sdk-manager-cli_0.8.4_Darwin_ARM64.tar.gz
   curl -fsSLO "https://github.com/lindell/connect-iq-sdk-manager-cli/releases/download/v0.8.4/$archive"
   echo "afc3903034ec081942f3480ec140859d0bb73158c1a6badd64b57f88f6bf936b  $archive" | shasum -a 256 -c
   mkdir -p ~/.local/bin && tar -xzf "$archive" -C ~/.local/bin connect-iq-sdk-manager
   ```

2. Lire l'accord développeur, puis l'accepter par son empreinte : l'outil
   refuse toute connexion avant. Une empreinte qui ne correspond plus au texte
   en ligne est refusée.

   ```sh
   ~/.local/bin/connect-iq-sdk-manager agreement view    # lien + empreinte
   ~/.local/bin/connect-iq-sdk-manager agreement accept --agreement-hash <empreinte>
   ```

   La même empreinte va dans la **variable** de dépôt `CIQ_AGREEMENT_HASH`
   (Settings → Secrets and variables → Actions → Variables). Ce n'est pas un
   secret, et c'est elle qui dit quel texte a été accepté.

3. Se connecter **par le navigateur**. Aucun mot de passe ne passe par l'outil,
   et la connexion par mot de passe casse dès que la double authentification
   est active :

   ```sh
   ~/.local/bin/connect-iq-sdk-manager login
   ```

4. Le jeton va dans le **secret** `CIQ_SDK_TOKEN_BASE64` :

   ```sh
   base64 -i "$HOME/.Garmin/ConnectIQ/token.json" | pbcopy
   ```

Un compte Garmin dédié, sans montre ni données, reste conseillé : le jeton est
limité au client SDK Manager, mais il appartient au compte qui s'est connecté.

#### Quand le jeton expire

Garmin fixe la durée de vie du jeton de rafraîchissement, sans la documenter,
et la CI ne peut pas réécrire un jeton renouvelé dans le secret. À
l'expiration, le job échoue avec « Jeton Garmin expiré ? » : refaire les
étapes 3 et 4. Rien ne casse tant que le cache tient, c'est-à-dire tant que la
matrice ne change pas et que le cache sert au moins une fois tous les sept
jours.

Une PR de fork n'a ni le secret ni la variable : elle compile depuis le cache
de `main`, et échoue avec un message explicite si le cache est vide.

### `Connect IQ` : les contrôles statiques

`./build.sh validate` ne demande que `python3` et vérifie ce qui se lit dans
les fichiers, plus vite que la compilation :

- `manifest.xml` bien formé, attributs et permissions `Background` /
  `Communications` présents ;
- `minApiLevel` au moins 5.0.0, le plancher de la matrice. Il couvre aussi ce
  que le code demande : `Application.Storage` écrit en arrière-plan (3.2.0,
  sans quoi une exception que personne ne voit, #469), le glance d'une
  `watch-app` (4.0.0) ;
- l'identifiant d'application est bien celui **de production** (`PRODUCTION_APP_ID`
  dans le validateur) : c'est ce qui attrape un manifeste resté sur
  l'identifiant beta après un paquet de test (voir `store/README.md` § 5) ;
- chaque `<iq:product>` a bien son dossier `resources-<id>/` avec un
  `drawables.xml` exposant l'identifiant que `launcherIcon` désigne — celui du
  manifeste, pas un nom en dur, pour qu'un renommage cohérent passe et qu'un
  renommage à moitié fait échoue ;
- chaque icône est **exactement** à la taille attendue par l'appareil (sinon le
  compilateur redimensionne en silence et avertit), qu'elle soit en SVG — via
  `width`/`height` ou à défaut le `viewBox` — ou en PNG, lu dans son IHDR ;
- aucun dossier `resources-<id>/` orphelin. Les qualifieurs du SDK sont
  épargnés (`resources-fre`, `resources-round-416x416`…) : ce sont des dossiers
  légitimes, pas des restes d'un appareil retiré ;
- l'app iPhone écoute bien ces identifiants : `productionApplicationUUID` et
  `betaApplicationUUID`, dans `Foulee/Connectivity/GarminConnectIQClient.swift`,
  valent `PRODUCTION_APP_ID` et `BETA_APP_ID`. Sans quoi l'iPhone ne reçoit
  rien, sans aucune erreur visible (#465) ;
- aucun matériel de clé (`.der`, `.pem`, `.p12`, `.key`, `.p8`, `.pfx`, `.jks`,
  `.keystore`) **dans tout le dépôt**, pas seulement sous `FouleeConnectIQ/` —
  la CI récupère l'arbre entier, et un feu vert restreint à ce dossier se
  lirait comme un feu vert global.

## Publication sur le Connect IQ Store

La fiche store (FR + EN), les tailles d'images exigées, la procédure de capture
d'écran, le canal beta et le suivi des plantages **ERA** sont dans
[`store/README.md`](store/README.md).

En deux lignes : un tag `garmin-vX.Y.Z` (ou `garmin-vX.Y.Z-betaN`) fait
construire par la CI le paquet signé, attaché à une release GitHub, qu'on
dépose ensuite sur <https://apps.garmin.com/developer/upload>. ERA ne demande **rien** dans le
manifeste ni dans le code — c'est un service serveur indexé sur l'identifiant
d'application, qui agrège les plantages des apps publiées ou beta pendant 30
jours, et se consulte avec `"$SDK/bin/era" -a <identifiant>`.

## Matrice d'appareils

**Toutes les montres Garmin qui peuvent faire tourner l'app** (#472) : 73
appareils, listés dans [`devices.json`](devices.json) avec leurs caractéristiques
(famille d'écran, type et profondeur d'écran, taille d'icône, CIQ, mémoire).
Ce fichier et les `<iq:products>` du manifeste sont écrits ensemble par
[`tools/device_catalog.py`](tools/device_catalog.py) à partir des profils
Garmin, et `./build.sh validate` vérifie qu'ils concordent.

Une montre est retenue si elle a une *watch app* et un service d'arrière-plan,
tourne en Connect IQ 5.0.0 ou plus (le `minApiLevel`) et a un écran couleur :
- **AMOLED** (fēnix 8/9, Forerunner 165/265/570/965/970, Venu 2/3/4/X1/Sq 2,
  vívoactive 5/6, epix 2, Instinct 3 AMOLED, MARQ…) : les couleurs de Foulée
  telles quelles ;
- **MIP 64 couleurs** (fēnix 7, fēnix 8 et 9 Solar, Forerunner 255/955,
  Enduro 3/4) : chaque couleur est ramenée par la montre à la plus proche de sa
  palette.

Restent dehors :
- les compteurs vélo et GPS de randonnée (Edge, eTrex, GPSMAP), qui font
  tourner des *watch apps* sans être des montres ;
- les écrans à 1 bit (Instinct 3 Solar, Instinct E) : l'app dessine en
  couleur, et ces montres ne lui laissent que 128 ko ;
- tout ce qui est sous Connect IQ 5.0.0, dont **Forerunner 55 et Instinct 2**,
  bloqués en 3.4.2 par Garmin : sans glance, ils retenaient le plancher d'API
  de toute l'app.

Les icônes de lancement sont **regroupées par famille d'écran**
(`resources-round-454x454/`) à la taille la plus courante de la famille ; une
montre dont l'icône diffère a son propre dossier (`resources-venu3/`), que le
SDK préfère à celui de sa famille. 30 dossiers pour 73 montres.

### Mettre la matrice à jour

Garmin publie de nouvelles montres : la matrice se recalcule, elle ne s'écrit
pas à la main.

1. Lancer le workflow **Garmin devices** depuis l'onglet Actions. Il
   télécharge tous les profils publiés par Garmin et affiche la liste des
   montres retenues dans son résumé, puis les mêmes lignes en JSON dans son
   journal.
2. Enregistrer ces lignes JSON dans un fichier, puis
   `tools/device_catalog.py --from <fichier> --write` : `devices.json` et le
   manifeste sont réécrits. En local, après
   `connect-iq-sdk-manager device download --download-all`,
   `tools/device_catalog.py --write` lit directement les profils.
3. `tools/render_icons.py` : produit les icônes de chaque famille et des
   exceptions **à la taille exacte** (sans quoi le compilateur redimensionne et
   avertit), et supprime les dossiers devenus inutiles. Le jungle du SDK
   résout déjà `resources-<famille>` et `resources-<appareil>` : ne pas les
   redéclarer dans `monkey.jungle`, ça provoque un avertissement de doublon.
4. `./build.sh validate && ./build.sh build`.

## Ce qui ne peut PAS être testé ici

**Le canal iOS.** Le simulateur Connect IQ ne parle à une app compagnon que via **ADB, donc uniquement Android**. Il n'existe aucun chemin simulateur → iPhone. En essayant de transmettre depuis le simulateur, on obtient exactement :

> `There is no data connection. Please connect an Android device to ADB`

**Ce n'est pas un bug de l'app.** C'est la limite du simulateur, et c'est aussi ce que verra quiconque tente une validation bout-en-bout sans matériel.

Restent donc non validés sans une montre physique + un iPhone (cf. [#191](https://github.com/EnO33/foulee/issues/191)) :

- la réception effective par le Companion App SDK iOS ;
- la fiabilité du `transmit` depuis le contexte arrière-plan vers un iPhone suspendu ;
- la réception de l'état de l'iPhone par le service d'arrière-plan, app montre fermée (#492) ;
- le rendu réel du glance et des polices sur chaque famille ;
- la consommation batterie d'un réveil toutes les 5 minutes.

**Le rendu des vues**, toujours pas inspecté visuellement : elles compilent et
l'app se lance sans erreur console, c'est tout ce qu'on sait. Le simulateur
Connect IQ est une application graphique — sur macOS `bin/connectiq` se réduit à
`open -a ConnectIQ.app` — et aucun binaire du SDK n'expose de commande de
capture. Il n'y a donc rien à automatiser : les captures d'écran du store se
prennent à la main, via **File → Screen Shot** du simulateur, qui écrit un PNG à
la taille exacte de l'appareil. Procédure complète dans
[`store/README.md`](store/README.md).

## Licence du SDK et politique de support

Publier sur le Connect IQ Store, c'est signer l'accord développeur Garmin. Le
SDK 9.2.0 n'embarque aucun fichier de licence ; le texte de référence est en
ligne : <https://developer.garmin.com/downloads/connect-iq/sdks/agreement.html>.
Version lue : celle datée du **6 août 2024**, consultée le 5 août 2026. Elle
n'est pas versionnée publiquement — **la relire au moment de publier**, et
vérifier que les renvois ci-dessous tiennent toujours. Ce que l'auteur prend
sur lui :

- **Le support, c'est nous.** § I(d) *Application Requirements* : le
  développeur est seul responsable du développement et de l'usage de son app,
  « including related documentation, user assistance, support and warranty ».
  § I(c) s'intitule d'ailleurs *Updates; No Support or Maintenance*. Les
  *App Review Guidelines* (§ 2(b)) ajoutent que la politique de support doit
  être **annoncée clairement aux utilisateurs** — d'où la section suivante.
- **Garmin peut dire non, à tout moment.** § II(a)(5) *Submission Process;
  Takedown* : Garmin peut refuser de publier ou retirer l'app « for any reason,
  even if your Application meets the Application Requirements », et restreindre
  l'accès au compte. § III(b)(2) : résiliation possible si un manquement
  matériel n'est pas corrigé sous 30 jours. § III(b)(3) : après résiliation
  l'app est retirée du store, mais ceux qui l'avaient déjà téléchargée peuvent
  la garder indéfiniment.
- **Aucune garantie, responsabilité plafonnée.** § V(c) : le SDK est fourni
  « AS IS ». § VI : hors sommes dues au titre du service marchand, la
  responsabilité totale de Garmin est plafonnée à **100 $**.
- **Confidentialité.** Exhibit A, I(a) : une politique de confidentialité
  conforme aux lois applicables est obligatoire dès qu'on collecte des données
  utilisateur, et elle doit dire clairement que ces données vont au développeur
  et non à Garmin. I(d) : consentement préalable explicite avant tout accès aux
  informations d'un utilisateur. Foulée ne collecte rien et n'envoie rien
  ailleurs que vers l'iPhone appairé ; la
  [politique](../docs/privacy.md) est celle de l'app iPhone, et sa section
  « L'app Foulée pour montre Garmin (Connect IQ) » couvre explicitement cette
  app-ci : ce qu'elle lit, ce qu'elle transmet, et vers où. C'est l'URL
  déclarée dans les deux fiches store. Toute modification de `makePayload`
  oblige à reprendre cette section *et* les deux fiches — elles énumèrent le
  contenu de l'envoi, et une énumération qui se termine par « rien d'autre ne
  quitte la montre » doit rester exacte.
- **Pas de redistribution du SDK.** § I(b) *Restrictions* interdit notamment
  d'« upload to or host on any website or server » les *Program Materials*.
  C'est ce qui interdit de committer les profils d'appareils pour faire tourner
  la CI (voir « Intégration continue »).

### Politique de support annoncée

Ce que la fiche store promet, donc ce qu'il faut tenir :

- **Canal unique** : les [issues GitHub](https://github.com/EnO33/foulee/issues)
  du dépôt. Pas d'adresse e-mail dédiée, pas de support par les avis du store.
- **Délai** : une réponse sous une semaine, en français ou en anglais.
- **Périmètre** : l'app montre et sa synchronisation avec l'iPhone. Tout ce qui
  relève du firmware Garmin, de Garmin Connect ou de la montre elle-même
  renvoie vers le support Garmin.
- **Appareils** : les modèles du manifeste. Nous n'en possédons pas la
  totalité (#191) : un bug spécifique à un modèle absent de notre matériel sera
  traité à l'aveugle, avec l'aide de son signaleur et des rapports ERA — et
  c'est dit franchement plutôt que promis.
- **Fin de vie** : si l'app est retirée, elle continue de fonctionner chez ceux
  qui l'ont installée (§ III(b)(3)), et la voie Garmin Connect → Apple Santé
  (phase 1) reste, elle, entièrement indépendante du Connect IQ Store.

## Clé développeur et dépôt

La clé (`*.pem` / `*.der`) vit dans `$HOME/.garmin`, **jamais** dans le dépôt. Le `.gitignore` racine couvre `*.pem`, `*.der` et les artefacts de build Connect IQ (`*.prg`, `*.iq`, `*.prg.debug.xml`) par sécurité.
