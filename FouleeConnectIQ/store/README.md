# Publier Foulée sur le Connect IQ Store

Tout ce qui peut être préparé hors ligne l'est ici. Ce qui reste demande un
navigateur connecté au compte développeur Garmin — c'est signalé à chaque fois.

| Fichier | Contenu |
|---|---|
| [`listing-fr.md`](listing-fr.md) | Nom, descriptions et champs annexes, en français |
| [`listing-en.md`](listing-en.md) | La même fiche, en anglais |

L'app montre parle **la langue de la montre** : français sur une montre réglée
en français, anglais partout ailleurs (`resources-fre/` et `resources/`, #471).
L'app iPhone, elle, reste en français, et la description anglaise le dit. La
fiche store est bilingue : le Connect IQ Store est mondial.

---

## 1. Fabriquer le paquet

Par un tag, depuis la CI (workflow
[`garmin-release.yml`](../../.github/workflows/garmin-release.yml)) :

```sh
git tag garmin-v1.0.0 && git push origin garmin-v1.0.0
```

Le job valide le projet, construit le paquet signé et l'attache à la release
GitHub `garmin-v1.0.0` sous le nom `foulee-1.0.0.iq`. La version à saisir dans
le formulaire du store est celle du tag. Il faut le secret
`CIQ_DEVELOPER_KEY_BASE64` en plus de ceux de la compilation :

```sh
base64 -i $HOME/.garmin/foulee_developer_key.der | pbcopy
```

En local, `./build.sh package` produit le même paquet dans `bin/foulee.iq`.

Le `.iq` contient un binaire par appareil du manifeste. C'est le seul
fichier à téléverser. Il est construit en `--release`, ce que `monkeyc --help`
résume en une ligne :

```
-r,--release                      Strip debug information
```

C'est bien ce qui se mesure. Sur `venu2`, SDK 9.2.0, même code, même clé, seule
l'option change : le `.prg` fait **107 404 octets** sans `--release` (la taille
qu'affiche `./build.sh build venu2`) et **19 372 octets** avec, soit 5,5 fois
moins. Et `strings` ne trouve plus un seul chemin `…/source/*.mc` dans le
binaire de release, là où il en trouve sept dans celui de debug.

> Ne pas mesurer ça sur les `.iq` : ce sont des archives 7-zip contenant un
> binaire par appareil (sept lors de cette mesure), elles pèsent ~95 ko et ~93,5 ko selon la variante — et pas
> même à l'octet près, la taille bouge de quelques dizaines d'octets d'une
> exécution à l'autre. L'écart de ~1,6 % qu'on lit là ne dit rien du binaire
> qui tourne réellement sur la montre.

**Conséquence sur ERA : non vérifiée.** La documentation du SDK
(*Core Topics → Error Reporting Application*) indique qu'un plantage est
identifié par « file name, function, and line number », mais **aucune page du
SDK 9.2.0 ne dit d'où vient cette symbolisation** : ni si elle est reconstruite
à partir du paquet téléversé, ni si Garmin s'appuie sur le
`<sortie>.prg.debug.xml` que `monkeyc` écrit à côté de chaque build par
appareil — il l'écrit d'ailleurs dans les deux variantes (71 113 octets en
release, 72 619 en debug, pour `venu2`), mais pas à côté du `.iq`. Rien n'y
relie non plus `--release` à ERA, dans un sens ou dans l'autre.

Donc : on publie en `--release` (c'est ce que fait `./build.sh package`), et le
premier vrai rapport de plantage tranchera. S'il arrive sans numéros de ligne
exploitables, refaire le paquet sans `--release` et comparer — c'est un
changement d'une option, et cette note existe pour qu'on sache quoi essayer.

## 2. Les images

Les **icônes** et l'**image d'en-tête** sont dans le dépôt, sous
[`assets/`](assets/), rendues depuis l'icône de l'app iPhone : le marcheur blanc
sur dégradé violet, une seule identité Foulée sur l'iPhone, l'Apple Watch et
Garmin (#468). Les **captures d'écran** sont sous
[`screenshots/`](screenshots/) : elles viennent du simulateur graphique (voir
§ 3).

### Tailles exigées

Relevées sur <https://developer.garmin.com/brand-guidelines/connect-iq/>
(consulté le 5 août 2026) :

| Élément | Taille | Détail |
|---|---|---|
| Icône de la fiche store | **500 × 500 px**, sRGB | prévoir **10 px** de marge autour du motif |
| Icône du store embarqué | **128 × 128 px**, sRGB | version couleur pour les écrans AMOLED ; pour les écrans *memory-in-pixel*, se limiter à la **palette de 64 couleurs** |
| Image d'en-tête (*hero*) | **1440 × 720 px** | facultative mais elle occupe le haut de la fiche |

Le forum développeurs mentionne en plus un plafond de **300 ko** pour les
icônes et images de couverture et de **150 ko** par capture d'écran. Ce chiffre
est communautaire, pas documenté par Garmin : le vérifier sur le formulaire.

| Fichier | Pour | Poids |
|---|---|---|
| `assets/icon-500.png` | icône de la fiche | 105 ko |
| `assets/icon-128.png` | icône du store embarqué, écrans AMOLED | 10 ko |
| `assets/icon-128-mip.png` | la même, écrans *memory-in-pixel* : le marcheur blanc sur le violet le plus proche de la palette 64 couleurs, sans dégradé ni tramage (un dégradé ramené à 64 couleurs fait des bandes, un tramage du bruit) | 0,5 ko |
| `assets/hero.png` | image d'en-tête, 1440 × 720 : la carte de partage de getfoulee.app en thème sombre, sans phrase à traduire puisque le store est mondial | 186 ko |

Tous tiennent sous les plafonds annoncés par le forum. Ils sont produits, avec
les icônes de lancement de chaque appareil, par :

```sh
tools/render_icons.py     # brew install imagemagick librsvg
```

Le script part de `Foulee/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
à la taille de chaque appareil. À relancer, puis committer, si l'icône iPhone
change.
Le rendu est reproductible : relancé sur une source inchangée, avec la même
version d'ImageMagick, il ne modifie aucun fichier. Une autre version
d'ImageMagick décale quelques pixels d'un niveau (0,2 % mesurés entre deux
versions) : inutile de committer ce bruit si l'icône n'a pas changé.
L'image d'en-tête reprend les couleurs de `scripts/generate-assets.mjs` dans
`getfoulee/web` : si la carte du site change, reporter ses couleurs dans
`HERO_SVG`.

### Captures d'écran, par format d'écran

Une capture par format suffit pour la fiche : rond AMOLED 454 × 454, rond MIP
260 × 260 (fēnix 7, Forerunner 255) et rectangle 320 × 360 (Venu Sq 2) couvrent
ce qu'un relecteur regarde. La résolution de chaque montre est dans la famille
d'écran de [`devices.json`](../devices.json).

| Fichier | Format | Poids |
|---|---|---|
| `screenshots/venu3-view.png` | rond AMOLED, 454 × 454 | 12 ko |
| `screenshots/fenix7-view.png` | rond MIP, 260 × 260 | 3 ko |
| `screenshots/venusq2-view.png` | rectangle, 320 × 360 | 4 ko |

Ce sont les vues principales, en anglais (la langue du simulateur), avec
8 400 pas, 62 minutes actives, 6,3 km et 1 850 kcal. Le bandeau « Open Foulée on
your iPhone » y figure parce que le simulateur n'est jamais relié à un
téléphone. Les *glances* n'y sont pas : le simulateur les dessine dans le haut
d'une capture plein écran, le reste est noir, et la fiche n'y gagne rien.

Ne pas confondre avec les **icônes de lancement** embarquées dans l'app, d'une
taille propre à chaque montre, que `./build.sh validate` vérifie déjà à chaque
PR.

## 3. Prendre les captures — procédure manuelle

**Le simulateur Connect IQ n'a pas de mode sans interface graphique.** Sur macOS
`bin/connectiq` se réduit à `open -a ConnectIQ.app` : c'est une application
Aqua, pilotée à la souris, et ni `monkeydo` ni aucun autre binaire du SDK
n'expose de commande de capture. Il n'y a donc rien à automatiser ici, et les
captures ne peuvent pas être produites par la CI.

Pour chaque appareil :

```sh
./build.sh build <appareil>
"$SDK/bin/connectiq" &                                   # attendre l'ouverture
"$SDK/bin/monkeydo" bin/foulee-<appareil>.prg <appareil>
```

Puis, dans le simulateur :

1. Fermer la boîte « There is no data connection » qui s'ouvre à chaque
   lancement : l'app cherche le téléphone, le simulateur n'en a pas.
2. **Simulation → Activity Monitoring → Set Activity Monitor Info** — injecter
   des valeurs crédibles (~8 400 pas, ~6,3 km), puis **Apply**, puis
   **File → Kill App** et relancer `monkeydo` : l'app ne relit pas les valeurs
   en cours de route. Une capture à zéro donne une fiche store qui ne montre
   rien. Les valeurs survivent au changement d'appareil.
   - **Distance : saisir des mètres, pas des centimètres.** La colonne s'appelle
     « Distance (cm) », mais le simulateur multiplie la valeur saisie par 100 :
     630 000 s'affiche 630 km, 6 300 s'affiche 6,3 km (SDK 9.3.0). L'app, elle,
     lit bien des centimètres, comme le documente `ActivityMonitor.Info`.
   - Les minutes actives affichées valent modérées + 2 × intenses : 32 et 15
     donnent 62.
   - Une cellule s'édite en ajoutant au contenu existant : effacer avant de
     saisir, sinon 5 000 suivi de 10 000 donne 500 010 000, ramené à 40 000.
3. **Settings → Glance Launch Mode → Launch in Normal Mode** pour que l'app
   s'ouvre directement sur la vue principale. Sinon elle démarre en *glance*, et
   sur les montres à boutons (fēnix 7) le clic sur START ne l'ouvre pas.
4. **File → Save Screen Capture** : le simulateur écrit un PNG **à la taille
   exacte de l'écran de l'appareil**, sans décor de montre ni fond d'écran de
   bureau. Il ajoute `.png` au nom saisi : taper le nom sans extension.

> Ne **jamais** utiliser `screencapture` sur l'écran entier pour ça : la capture
> embarquerait le bureau du développeur, et sa taille n'aurait aucun rapport
> avec celle de l'appareil.

Ranger les fichiers sous `store/screenshots/<appareil>-view.png`, et vérifier
avant de committer qu'aucune donnée personnelle n'apparaît à l'écran.

## 4. Téléverser

1. Compte développeur Garmin — **gratuit**, 18 ans et plus.
2. <https://apps.garmin.com/developer/upload> → **Submit an App**, déposer
   `bin/foulee.iq`. Garmin valide le binaire avant de proposer la suite.
3. Coller les champs depuis `listing-fr.md` puis `listing-en.md`, ajouter les
   images du § 2.
4. Soumettre. La documentation du SDK annonce une revue **sous 72 heures** hors
   circonstances particulières. Pendant la revue l'app n'est pas visible
   publiquement mais **reste téléchargeable par son auteur** — c'est le moyen
   de la tester sur une montre réelle avant publication.

## 5. Canal beta

Le SDK est explicite : une app beta a besoin d'un **identifiant d'application
différent**, parce qu'elle occupe une entrée de store distincte. Il est réservé
et épinglé dans [`tools/validate_project.py`](../tools/validate_project.py)
(`BETA_APP_ID`).

Un tag suffit :

```sh
git tag garmin-v1.0.0-beta1 && git push origin garmin-v1.0.0-beta1
```

Le job remplace l'identifiant de production par l'identifiant beta **dans sa
propre copie du dépôt**, après `validate`, puis construit le paquet et
l'attache à une pré-release GitHub. Le manifeste committé garde toujours
l'identifiant de production, et `validate` le vérifie sur chaque PR. Le
remplacement à la main, et le risque de le committer, n'existent plus.

Téléverser ensuite en cochant **Beta App**.

Rien à changer côté iPhone : l'app écoute les deux identifiants
(`GarminConnectIQConfiguration.watchApps`), donc une montre beta parle à
n'importe quel build, TestFlight compris. L'identifiant beta y est épinglé
contre `BETA_APP_ID` par `./build.sh validate`.

La beta se met à jour autant de fois qu'on veut, ses URL ne sortent pas du
compte, et ERA remonte ses plantages comme ceux d'une app publiée. C'est le
canal à utiliser pour l'appel à testeurs sur le forum Connect IQ (#191 : les
appareils que nous ne possédons pas).

## 6. ERA — suivi des plantages

Rien à activer, ni dans le manifeste ni dans le code : ERA est un service
serveur, indexé sur l'identifiant d'application, qui agrège les plantages des
apps **publiées ou beta**. Il ne remonte évidemment rien tant que l'app n'est
pas sur le store.

```sh
"$SDK/bin/era" -a 859c7300a91149fdb6ce7e4453bfe59d   # JSON, en ligne de commande
java -jar "$SDK/bin/era.jar"                         # même chose, en fenêtre
```

Les deux demandent une connexion au compte développeur la première fois.

À savoir :

- Les rapports sont conservés **30 jours**. Un passage par mois ne suffit pas :
  viser une relecture après chaque publication, puis une fois par semaine le
  temps que la version se diffuse.
- Chaque plantage est identifié par **fichier, fonction et numéro de ligne**.
  D'où l'importance de savoir quel commit a produit quelle version publiée. En
  revanche, savoir si ces numéros de ligne survivent au `--release` du paquet
  n'est **pas** documenté par le SDK : voir la note du § 1, à trancher au
  premier rapport reçu.
- La case **Fixed** persiste d'une session à l'autre : s'en servir, sinon la
  liste redevient illisible.
- Le code de l'app est écrit pour ne pas produire de plantage sur données
  manquantes (double garde `info has :champ` puis contrôle de type). Un rapport
  ERA sur `DailySnapshot` signifie donc qu'une famille d'appareils expose un
  symbole d'un type inattendu : c'est exactement l'information qu'une montre
  physique ne nous aurait pas donnée.
