# Foulée Connect IQ (Monkey C)

App Garmin de Foulée. Elle est volontairement minuscule : **la montre est un capteur, pas une seconde app**. Elle lit les compteurs du jour (`Toybox.ActivityMonitor`), les affiche sobrement, et pousse un instantané compact vers l'iPhone toutes les 5 minutes.

Voir [ADR 0001](../docs/adr/0001-garmin-integration.md) (phase 2) et les issues [#188](https://github.com/EnO33/foulee/issues/188) / [#179](https://github.com/EnO33/foulee/issues/179).

Ce dossier est **hors du build Tuist / Xcode** : il n'est référencé par aucune cible Swift et ne participe pas à `tuist generate`.

## Ce que fait l'app

| Élément | Rôle |
|---|---|
| `source/DailySnapshot.mc` | Assemblage pur de l'instantané (lecture des métriques, génération, payload). Aucune E/S. |
| `source/SnapshotService.mc` | Service d'arrière-plan : lit, persiste, décide, transmet. |
| `source/FouleeGlanceView.mc` | Glance : pas du jour + minutes actives. |
| `source/FouleeView.mc` | Vue plein écran : pas, minutes actives, distance. |
| `source/SnapshotFormat.mc` | Formatage français (espace des milliers, virgule décimale). |
| `source/DailySnapshotTest.mc` | Tests unitaires Run No Evil. |
| `build.sh` | Point d'entrée : `validate`, `build`, `test`, `package`. |
| `tools/validate_project.py` | Contrôles statiques sans SDK — ce que lance la CI. |
| `store/` | Fiche Connect IQ Store (FR + EN) et procédure de publication. |

### Métriques lues

`ActivityMonitor.getInfo()` → `steps`, `distance` (cm), `calories`, et surtout **`activeMinutesDay`** (`total` / `vigorous`), l'équivalent Garmin natif des minutes d'exercice — la métrique qui rend le streak de Foulée possible pour un porteur de Garmin.

Chaque champ est gardé deux fois : `info has :champ` (les familles n'exposent pas les mêmes symboles) puis contrôle de type/nullité dans `DailySnapshot.asCount`. Une famille qui ne remonte rien produit un instantané à zéro, jamais une exception.

### Instantané transmis

```json
{
  "v": 1,
  "steps": 8421,
  "distanceCm": 634000,
  "activeMinutes": 47,
  "activeMinutesVigorous": 12,
  "calories": 2103,
  "ts": 1754380800,
  "gen": 7
}
```

- `ts` : epoch en secondes.
- `gen` : compteur monotone **qui n'avance que si les métriques ont bougé**. Un instantané qui n'est pas arrivé est donc retransmis sous la *même* génération, et l'iPhone peut ignorer une génération déjà ingérée. C'est ce qui rend l'échange idempotent (côté iOS : #189).
- Clés courtes et valeurs entières : le lien BLE tourne autour de 1 ko/s.

### Absence de téléphone

Une montre hors de portée du téléphone est le **cas normal**, pas une erreur. Le service :

1. vérifie `System.getDeviceSettings().phoneConnected` avant de dépenser du budget BLE ;
2. implémente `ConnectionListener.onError()`, qui se contente de terminer le service ;
3. ne réessaie qu'au prochain événement temporel — pas de boucle, pas de spam, pas de message d'erreur.

Le glance et la vue plein écran ne touchent jamais au téléphone : elles s'affichent à l'identique sans aucun appairage.

## Prérequis

- SDK Connect IQ 9.2.0 : `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`
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
./build.sh build            # les sept appareils du manifeste, dans bin/
./build.sh build venu2      # un seul
```

`build.sh` retrouve seul le SDK (via `current-sdk.cfg`), le JDK et la clé, et
sort les `.prg` dans `bin/`. Sous le capot, pour un appareil :

```sh
"$SDK/bin/monkeyc" -f monkey.jungle -d fenix843mm \
  -o bin/foulee-fenix843mm.prg \
  -y $HOME/.garmin/foulee_developer_key.der -w -l 3
```

`-w` active les avertissements, `-l 3` le contrôle de types **strict** (même exigence que SwiftLint/Periphery côté iOS). Les sept appareils compilent proprement à ce niveau.

Le script va plus loin que `monkeyc` : il **échoue sur tout avertissement**
autre que les deux avertissements de glance attendus sur `fr55` et `instinct2`
(voir « Matrice d'appareils »). La dispense est **nominative** : elle ne
s'applique qu'à ces deux appareils, parce que `monkeyc` préfixe chaque
avertissement de l'appareil concerné (`WARNING: fr55: …`). Le même
avertissement sur un appareil en CIQ 4+ signifierait que le glance est
réellement cassé, et il fait donc échouer la compilation. C'est l'équivalent
Monkey C de `swiftlint --strict`, et c'est ce qui fait de `./build.sh build` la
barrière qualité du dossier — la CI, elle, ne peut pas compiler (section
suivante).

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

**La CI ne compile pas le Monkey C, et elle ne le peut pas.** Voici pourquoi,
en détail, parce que c'est contre-intuitif et que ça mérite d'être re-vérifié
si Garmin change quelque chose.

> **À retenir : une CI verte ne veut pas dire que le Monkey C compile.** Le job
> `Connect IQ` ne lit que des fichiers ; du code qui ne compile pas, ou qui
> compile avec un avertissement, passe le vert sans broncher. Seul
> `./build.sh build`, sur une machine munie du SDK, le prouve — à lancer avant
> de pousser.

### Ce qui marche sans compte

Le SDK lui-même se récupère très bien en script. Garmin publie un index et des
archives servies anonymement :

```sh
curl -s https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json
curl -sI https://developer.garmin.com/downloads/connect-iq/sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2.zip
# HTTP/2 200 — content-length: 213780514
```

`monkeyc` n'est qu'un script de trois lignes qui lance `monkeybrains.jar` : le
SDK Linux tourne sur n'importe quelle machine munie d'un JDK.

### Ce qui bloque

**Le SDK ne contient aucun profil d'appareil.** L'archive n'a pas de dossier
`Devices/`, et un `monkeyc` fraîchement dézippé, lancé avec un `user.home`
vierge — ce qu'est un runner GitHub — répond :

```
ERROR: Invalid device id specified: 'venu2'.
```

Les profils viennent d'ailleurs : `https://api.gcs.garmin.com/ciq-product-onboarding/devices`,
qui renvoie **401** sans jeton de compte Garmin. Le SDK Manager qui les
télécharge est une application graphique avec un login SSO. Le seul chemin non
interactif connu est un outil communautaire
([`lindell/connect-iq-sdk-manager-cli`](https://github.com/lindell/connect-iq-sdk-manager-cli)),
et il réclame `GARMIN_USERNAME` / `GARMIN_PASSWORD`.

Ce serait le mot de passe du compte Garmin de l'auteur — celui qui contient ses
données Garmin Connect *et* son identité de publication sur le store. Pour une
app qui se revendique locale et sans compte, le mettre dans les secrets d'un
dépôt public serait un mauvais échange. Et embarquer les profils dans le dépôt
ou dans une image Docker n'est pas une option non plus : l'accord Connect IQ
l'interdit explicitement (§ I(b), pas d'hébergement ni de redistribution des
« Program Materials »).

### Ce que fait la CI à la place

Le job **`Connect IQ`** de [`ci.yml`](../.github/workflows/ci.yml) lance
`./build.sh validate`, qui ne demande que `python3` et vérifie tout ce qui est
connaissable depuis les fichiers :

- `manifest.xml` bien formé, attributs et permissions `Background` /
  `Communications` présents ;
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
- aucun matériel de clé (`.der`, `.pem`, `.p12`, `.key`, `.p8`, `.pfx`, `.jks`,
  `.keystore`) **dans tout le dépôt**, pas seulement sous `FouleeConnectIQ/` —
  la CI récupère l'arbre entier, et un feu vert restreint à ce dossier se
  lirait comme un feu vert global.

C'est ce qui attrape les vraies régressions de ce dossier : elles viennent
presque toutes d'un changement de matrice d'appareils. Le reste — la
compilation des sept appareils en `-w -l 3` — est à la charge de
`./build.sh build`, **à lancer avant de pousser** toute modification de
`FouleeConnectIQ/`.

### Si l'arbitrage change un jour

Pour activer une vraie compilation en CI il faudrait, dans l'ordre :

1. Créer les secrets `GARMIN_USERNAME` et `GARMIN_PASSWORD` (compte Garmin
   complet — c'est là qu'est le vrai coût) ;
2. créer le secret `CIQ_DEVELOPER_KEY_BASE64` :

   ```sh
   base64 -i $HOME/.garmin/foulee_developer_key.der | pbcopy
   ```

   La clé se matérialise et se nettoie exactement comme le matériel de
   signature Apple dans [`release.yml`](../.github/workflows/release.yml) :

   ```yaml
   - name: Materialise the Connect IQ developer key
     env:
       CIQ_DEVELOPER_KEY_BASE64: ${{ secrets.CIQ_DEVELOPER_KEY_BASE64 }}
     run: |
       set -euo pipefail
       echo "$CIQ_DEVELOPER_KEY_BASE64" | base64 --decode > "$RUNNER_TEMP/ciq.der"

   # …compilation…

   - name: Tidy the developer key
     if: always()
     run: rm -f "$RUNNER_TEMP/ciq.der"
   ```

   `build.sh` lit déjà `CIQ_DEVELOPER_KEY`, il n'y a rien d'autre à changer de
   ce côté.
3. Mettre en cache le SDK (`actions/cache`, épinglé par SHA comme le reste) :
   213 Mo à chaque run sinon.
4. Installer `connect-iq-sdk-manager`, accepter l'accord avec
   `agreement accept --acceptance-hash=…`, puis
   `device download --manifest=FouleeConnectIQ/manifest.xml`.

Le point 1 est le seul vrai obstacle, et il est politique, pas technique.

## Publication sur le Connect IQ Store

La fiche store (FR + EN), les tailles d'images exigées, la procédure de capture
d'écran, le canal beta et le suivi des plantages **ERA** sont dans
[`store/README.md`](store/README.md).

En deux lignes : `./build.sh package` produit `bin/foulee.iq`, qu'on dépose sur
<https://apps.garmin.com/developer/upload>. ERA ne demande **rien** dans le
manifeste ni dans le code — c'est un service serveur indexé sur l'identifiant
d'application, qui agrège les plantages des apps publiées ou beta pendant 30
jours, et se consulte avec `"$SDK/bin/era" -a <identifiant>`.

## Matrice d'appareils

Chaque identifiant a été vérifié dans `~/Library/Application Support/Garmin/ConnectIQ/Devices`.

| Appareil | Identifiant | CIQ | Famille | Glance |
|---|---|---|---|---|
| fēnix 8 43 mm | `fenix843mm` | 6.0.2 | round-416x416 | oui |
| Forerunner 165 | `fr165` | 5.2.0 | round-390x390 | oui |
| Forerunner 55 | `fr55` | 3.4.2 | round-208x208 (4 bpp) | non |
| Instinct 2 | `instinct2` | 3.4.2 | semioctagon-176x176 (1 bpp) | non |
| Venu 2 | `venu2` | 5.0.0 | round-416x416 | oui |
| Venu Sq 2 | `venusq2` | 5.0.0 | rectangle-320x360 | oui |
| vívoactive 5 | `vivoactive5` | 5.2.0 | round-390x390 | oui |

La matrice couvre volontairement les deux extrêmes : AMOLED 416×416 et monochrome 176×176 sur un service d'arrière-plan limité à 32 ko.

**Forerunner 55 et Instinct 2** tournent en CIQ 3.4.2 : le glance d'une `watch-app` demande 4.0.0. Sur ces deux modèles l'app s'installe et fonctionne normalement (vue plein écran + service d'arrière-plan), seul le glance manque. Le compilateur le signale sous deux formes, c'est attendu :

> `WARNING: fr55: source/FouleeGlanceView.mc:14: Glance applications are not supported for app type 'watch-app' on device 'fr55' with minimum API Level 3.4.2. The (:glance) annotation will be ignored.`
>
> `WARNING: fr55: resources/strings/strings.xml:3,4: String resource 'UnitSteps' specifies the 'glance' resource scope, but app type 'watch-app' does not support glances on device 'fr55'.`

Ce sont les **seuls** avertissements restants (28 au total, 14 par appareil, uniquement sur ces deux-là). Les cinq autres appareils compilent sans un seul avertissement, en `-w -l 3`. Les faire disparaître demanderait de sortir `fr55` et `instinct2` de la matrice : le compromis retenu est l'inverse — ces deux modèles très répandus gagnent le service d'arrière-plan, qui est l'objet de l'app.

### Ajouter un appareil

1. Vérifier l'identifiant dans le dossier `Devices`.
2. L'ajouter aux `<iq:products>` du manifeste.
3. Créer `resources-<identifiant>/drawables/` avec `drawables.xml` et un `launcher_icon.svg` **à la taille exacte** indiquée par `launcherIcon` dans le `compiler.json` de l'appareil. Sans ça le compilateur redimensionne et avertit. Le jungle du SDK ajoute déjà `resources-<identifiant>` au chemin de ressources : ne pas le redéclarer dans `monkey.jungle`, ça provoque un avertissement de doublon.
4. Reporter cette même taille dans `LAUNCHER_ICON_PX`, dans
   [`tools/validate_project.py`](tools/validate_project.py) — c'est ce qui
   permet à la CI de vérifier l'icône alors qu'elle n'a pas accès aux profils
   d'appareils. Le script échoue explicitement sur un appareil qu'il ne connaît
   pas, donc l'oubli se voit.
5. `./build.sh validate && ./build.sh build`.

## Ce qui ne peut PAS être testé ici

**Le canal iOS.** Le simulateur Connect IQ ne parle à une app compagnon que via **ADB, donc uniquement Android**. Il n'existe aucun chemin simulateur → iPhone. En essayant de transmettre depuis le simulateur, on obtient exactement :

> `There is no data connection. Please connect an Android device to ADB`

**Ce n'est pas un bug de l'app.** C'est la limite du simulateur, et c'est aussi ce que verra quiconque tente une validation bout-en-bout sans matériel.

Restent donc non validés sans une montre physique + un iPhone (cf. [#191](https://github.com/EnO33/foulee/issues/191)) :

- la réception effective par le Companion App SDK iOS ;
- la fiabilité du `transmit` depuis le contexte arrière-plan vers un iPhone suspendu ;
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
- **Appareils** : les sept modèles du manifeste. Nous n'en possédons pas la
  totalité (#191) : un bug spécifique à un modèle absent de notre matériel sera
  traité à l'aveugle, avec l'aide de son signaleur et des rapports ERA — et
  c'est dit franchement plutôt que promis.
- **Fin de vie** : si l'app est retirée, elle continue de fonctionner chez ceux
  qui l'ont installée (§ III(b)(3)), et la voie Garmin Connect → Apple Santé
  (phase 1) reste, elle, entièrement indépendante du Connect IQ Store.

## Clé développeur et dépôt

La clé (`*.pem` / `*.der`) vit dans `$HOME/.garmin`, **jamais** dans le dépôt. Le `.gitignore` racine couvre `*.pem`, `*.der` et les artefacts de build Connect IQ (`*.prg`, `*.iq`, `*.prg.debug.xml`) par sécurité.
