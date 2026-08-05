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
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export PATH="$JAVA_HOME/bin:$PATH"
SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"

"$SDK/bin/monkeyc" -f monkey.jungle -d fenix843mm \
  -o /tmp/foulee-fenix843mm.prg \
  -y $HOME/.garmin/foulee_developer_key.der -w -l 3
```

`-w` active les avertissements, `-l 3` le contrôle de types **strict** (même exigence que SwiftLint/Periphery côté iOS). Les sept appareils compilent proprement à ce niveau.

## Simulateur

```sh
"$SDK/bin/connectiq"                       # lance le simulateur (GUI)
"$SDK/bin/monkeydo" /tmp/foulee-venu2.prg venu2
```

Le simulateur doit tourner *avant* `monkeydo`, et il vaut mieux le relancer entre deux sessions : il garde l'app précédente chargée et `monkeydo` reste alors bloqué.

Le service d'arrière-plan se déclenche à la main via le menu **Simulation → Trigger Background Event** (interface graphique uniquement).

## Tests unitaires

```sh
"$SDK/bin/monkeyc" -f monkey.jungle -d venu2 \
  -o /tmp/foulee-test-venu2.prg \
  -y $HOME/.garmin/foulee_developer_key.der -w -l 3 --unit-test
"$SDK/bin/connectiq"
"$SDK/bin/monkeydo" /tmp/foulee-test-venu2.prg venu2 -t
```

Cinq tests couvrent l'assemblage de l'instantané à partir d'une structure `info` injectée (`FakeActivityInfo`), les champs absents ou nuls, la stabilité de la génération entre deux essais, la coercition des compteurs et le formatage français.

`monkeydo` a besoin du simulateur, donc ce n'est pas headless au sens strict, mais tout se pilote depuis le terminal.

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

## Ce qui ne peut PAS être testé ici

**Le canal iOS.** Le simulateur Connect IQ ne parle à une app compagnon que via **ADB, donc uniquement Android**. Il n'existe aucun chemin simulateur → iPhone. En essayant de transmettre depuis le simulateur, on obtient exactement :

> `There is no data connection. Please connect an Android device to ADB`

**Ce n'est pas un bug de l'app.** C'est la limite du simulateur, et c'est aussi ce que verra quiconque tente une validation bout-en-bout sans matériel.

Restent donc non validés sans une montre physique + un iPhone (cf. [#191](https://github.com/EnO33/foulee/issues/191)) :

- la réception effective par le Companion App SDK iOS ;
- la fiabilité du `transmit` depuis le contexte arrière-plan vers un iPhone suspendu ;
- le rendu réel du glance et des polices sur chaque famille ;
- la consommation batterie d'un réveil toutes les 5 minutes.

Les captures de layout du simulateur n'ont pas non plus pu être prises dans cet environnement (pas de session graphique accessible) : les vues compilent et l'app se lance sans erreur console, mais leur rendu n'a pas été inspecté visuellement.

## Clé développeur et dépôt

La clé (`*.pem` / `*.der`) vit dans `$HOME/.garmin`, **jamais** dans le dépôt. Le `.gitignore` racine couvre `*.pem`, `*.der` et les artefacts de build Connect IQ (`*.prg`, `*.iq`, `*.prg.debug.xml`) par sécurité.
