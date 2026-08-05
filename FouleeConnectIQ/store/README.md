# Publier Foulée sur le Connect IQ Store

Tout ce qui peut être préparé hors ligne l'est ici. Ce qui reste demande un
navigateur connecté au compte développeur Garmin — c'est signalé à chaque fois.

| Fichier | Contenu |
|---|---|
| [`listing-fr.md`](listing-fr.md) | Nom, descriptions et champs annexes, en français |
| [`listing-en.md`](listing-en.md) | La même fiche, en anglais |

L'app elle-même est **en français uniquement** (`<iq:language>fre</iq:language>`),
comme l'app iPhone. La fiche store, elle, est bilingue : le Connect IQ Store est
mondial et la description anglaise dit explicitement que les libellés de la
montre sont en français.

---

## 1. Fabriquer le paquet

```sh
./build.sh package     # → bin/foulee.iq
```

Le `.iq` contient les binaires des sept appareils du manifeste. C'est le seul
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

> Ne pas mesurer ça sur les `.iq` : ce sont des archives 7-zip contenant les
> sept binaires, elles pèsent ~95 ko et ~93,5 ko selon la variante — et pas
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

Aucune n'est dans le dépôt : ce sont des captures d'écran d'appareils qui
n'existent qu'en simulateur graphique (voir § 3), et il vaut mieux ne pas
committer d'images obtenues à l'arraché.

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

Le motif source est déjà dans le dépôt : `resources-venu2/drawables/launcher_icon.svg`
(les trois barres violettes de Foulée, `#BF5AF2` sur fond noir). Il suffit de le
rendre aux tailles ci-dessus.

### Captures d'écran, par appareil visé

Une capture par famille suffit pour la fiche, mais autant les avoir toutes : la
matrice couvre volontairement deux extrêmes (AMOLED 416 × 416 et monochrome
176 × 176) et c'est précisément ce qu'un relecteur regarde. Résolutions relevées
dans le `compiler.json` de chaque appareil (SDK 9.2.0) :

| Appareil | Capture | Écran |
|---|---|---|
| fēnix 8 43 mm (`fenix843mm`) | 416 × 416 | AMOLED 16 bpp |
| Venu 2 (`venu2`) | 416 × 416 | AMOLED 16 bpp |
| Forerunner 165 (`fr165`) | 390 × 390 | AMOLED 16 bpp |
| vívoactive 5 (`vivoactive5`) | 390 × 390 | AMOLED 16 bpp |
| Venu Sq 2 (`venusq2`) | 320 × 360 | AMOLED 16 bpp |
| Forerunner 55 (`fr55`) | 208 × 208 | MIP 4 bpp |
| Instinct 2 (`instinct2`) | 176 × 176 | MIP 1 bpp |

Ne pas confondre avec les **icônes de lancement** embarquées dans l'app, qui
sont d'autres tailles encore (60, 70, 54, 56, 40, 35 et 62 px respectivement) et
que `./build.sh validate` vérifie déjà à chaque PR.

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

1. **Simulation → Activity Monitoring** — injecter des valeurs crédibles
   (~8 400 pas, ~47 minutes actives, ~6,3 km). Une capture à zéro donne une
   fiche store qui ne montre rien.
2. Laisser la vue plein écran s'afficher, puis **File → Screen Shot** : le
   simulateur écrit un PNG **à la taille exacte de l'écran de l'appareil**,
   sans décor de montre ni fond d'écran de bureau.
3. Recommencer pour le *glance* (**Simulation → Glance View**) sur les cinq
   appareils qui le supportent — fr55 et instinct2 n'en ont pas, c'est attendu.

> Ne **jamais** utiliser `screencapture` sur l'écran entier pour ça : la capture
> embarquerait le bureau du développeur, et sa taille n'aurait aucun rapport
> avec celle de l'appareil.

Ranger les fichiers sous `store/screenshots/<appareil>-{view,glance}.png`. Ce
dossier n'est pas suivi par git tant qu'il n'existe pas ; s'il est committé un
jour, vérifier d'abord qu'aucune donnée personnelle n'apparaît à l'écran.

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
différent**, parce qu'elle occupe une entrée de store distincte. La marche à
suivre :

1. Dans `manifest.xml`, remplacer temporairement `id="859c7300a91149fdb6ce7e4453bfe59d"`
   par l'identifiant beta réservé ici :

   ```
   a0d0785c31b84e24b4a30d6bfd950502
   ```

2. `./build.sh package`, téléverser en cochant **Beta App**.
3. **Rétablir l'identifiant de production dans `manifest.xml`** — ne pas
   committer le manifeste modifié.

Tant que l'identifiant beta est en place, `./build.sh validate` **échoue**, et
c'est voulu : `PRODUCTION_APP_ID` est épinglé dans
[`tools/validate_project.py`](../tools/validate_project.py) et le message
nomme le swap beta comme cause probable. Pendant l'étape 2, cet échec est
attendu — `./build.sh package` n'appelle pas `validate` et fabrique le paquet
normalement. Après l'étape 3, `validate` doit repasser au vert : c'est le
contrôle à lancer avant de committer quoi que ce soit. La CI le lance de toute
façon sur chaque PR, donc un manifeste beta committé par erreur bloque la
fusion au lieu de partir en production.

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
