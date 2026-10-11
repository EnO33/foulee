# ADR 0006 — Isolation sur le main actor par défaut

- **Statut** : acceptée (2026-10)
- **Issues** : [#407](https://github.com/EnO33/foulee/issues/407)

## Contexte

L'essentiel du code de Foulée vit sur le main actor : vues SwiftUI, stores `@Observable`, réglages, Bilan. Jusqu'ici, le module était non isolé par défaut, et chaque type d'interface portait son `@MainActor` écrit à la main (85 annotations). Un oubli ne se voyait qu'à la compilation, au premier appel depuis une vue.

Swift 6.2 permet d'inverser ce défaut module par module : `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (SE-0466). Les réglages « approachable concurrency » (`SWIFT_APPROACHABLE_CONCURRENCY`) vont avec :
- une fonction `async` non isolée s'exécute sur l'acteur de l'appelant (`nonisolated(nonsending)`) ;
- une conformance prend l'isolation de son type ;
- la sendabilité est inférée depuis les captures.

## Décisions

### D1 — Le main actor par défaut, cible par cible

- **L'app iOS et ses tests unitaires** l'activent en premier (`mainActorByDefault` dans `Project.swift`).
- **La montre, puis les extensions** suivront, chacune dans sa propre PR, une fois la précédente stable en CI.
- **Une cible sans le réglage garde le défaut de Swift** (non isolé). Les fichiers partagés entre cibles doivent donc compiler sous les deux règles.

### D2 — Ce qui quitte le main actor le dit là où c'est déclaré

- **`nonisolated`** sur le type ou l'extension :
  - les données : modèles, snapshots, charges utiles, types `Codable` ;
  - la logique pure : calculs, formats, allègement de parcours ;
  - les clients swift-dependencies et leurs conformances `DependencyKey`, dont les valeurs sont lues depuis n'importe quel thread ;
  - les délégués système appelés sur une file d'arrière-plan.
  - les `Shape` SwiftUI : `path(in:)` est une exigence non isolée, que SwiftUI appelle hors du main actor.
- **`@concurrent`** sur une fonction `async` dont le travail doit vraiment quitter l'acteur de l'appelant. Sans cette marque, elle reste sur l'acteur de l'appelant.
- **Les types de `Foulee/Shared/`** compilés aussi dans la montre ou les extensions sont `nonisolated`, sauf ceux qui ne servent qu'à l'interface. Les deux compilations s'accordent ainsi sur leur isolation.

### D3 — Plus de `@MainActor` redondant

Les annotations `@MainActor` sur les déclarations de l'app iOS sont retirées : elles ne disent plus rien. Elles restent sur les types de fonctions (`@MainActor () -> Void`) et dans les types `nonisolated`, où elles changent le sens.

## Règle pour le code à venir

- **Une vue, un store ou un helper d'interface** : rien à écrire.
- **Un type de données ou un calcul pur** : `nonisolated`.
- **Un client de dépendance ou un délégué système** : `nonisolated`, avec `@Sendable` sur les closures.
- **Un travail lourd** : une fonction `@concurrent`, appelée avec `await`.

## Conséquences

- **Un type de données oublié** reste sur le main actor. Le compilateur le signale dès qu'il est utilisé ailleurs, par exemple dans une closure HealthKit, un décodage en arrière-plan ou un `liveValue`.
- **Une fonction `async` non isolée ne change plus de thread d'elle-même.** Un calcul lourd appelé depuis une vue doit être marqué `@concurrent`, sinon il bloque l'interface.
