# Politique de confidentialité — Foulée

_Dernière mise à jour : 10 juillet 2026_

Foulée est une application **locale**. Elle t'aide à entretenir une série de
marches du midi à partir de tes données d'activité. **Aucune donnée n'est
envoyée vers un serveur qui nous appartiendrait, et il n'y a aucun compte à
créer.** Tout reste sur ton iPhone et ton Apple Watch.

## Données de santé (HealthKit)

Avec ton autorisation, Foulée **lit** depuis l'app Santé : tes pas, ta distance,
tes minutes d'exercice, ta fréquence cardiaque et tes séances de marche. Ces
données servent uniquement à afficher tes statistiques dans l'app et à calculer
ta série.

Foulée **écrit** aussi tes marches du midi dans l'app Santé sous forme de
séances, si tu le souhaites.

Ces données de santé **ne quittent jamais ton appareil** : elles ne sont ni
transmises à un tiers, ni stockées ailleurs que dans l'app Santé d'Apple, que tu
contrôles entièrement.

## Localisation

Avec ton autorisation, Foulée utilise ta position **uniquement pendant que
l'app est ouverte** (« lorsque l'app est active ») pour deux usages :

- afficher la **météo du midi** à ton endroit ;
- tracer le **parcours** de ta marche en cours sur une carte.

Pour la météo, tes coordonnées sont transmises à **Apple WeatherKit**, qui
renvoie les conditions locales (voir la
[politique de confidentialité d'Apple](https://www.apple.com/legal/privacy/)).
Le tracé de la marche reste sur ton appareil pendant la séance et n'est ni
enregistré durablement, ni partagé.

## Mouvement et forme

Foulée utilise le **podomètre** (CoreMotion) pour compter tes pas en direct
pendant la marche. Ces données sont traitées localement, en temps réel.

## Ce que Foulée ne fait pas

- ❌ Aucun compte, aucune inscription, aucune adresse e-mail collectée.
- ❌ Aucun outil d'analyse, aucun traceur tiers, aucune publicité.
- ❌ Aucune vente ni aucun partage de tes données.

## Préférences

Tes réglages (objectif, fenêtre de marche, thème, rappels) sont enregistrés
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
