# Notes de version

Un fichier par version de l'app, nommé comme le tag sans le `v` : `1.56.0.md`
pour `v1.56.0`. Le workflow `release.yml` en fait le texte de la release
GitHub, que le site affiche dans sa page « Nouveautés ».

Pour les utilisateurs, pas pour les développeurs : en français, en
tutoyant, 2 à 5 points forts, sans numéro d'issue ni nom de code. Le fichier
doit être dans le commit tagué : sans lui, la release échoue avant le build.
