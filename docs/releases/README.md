# Notes de version

Deux fichiers par version de l'app, nommés comme le tag sans le `v` :
`1.56.0.md` en français et sa traduction `1.56.0.en.md` en anglais, pour
`v1.56.0`. Le workflow `release.yml` en fait le texte de la release GitHub,
l'anglais sous un titre `## English`, que le site affiche dans ses pages
« Nouveautés » et « What's new ». fastlane les reprend, en texte brut, comme
« À tester » de la build TestFlight (en français) et comme « Nouveautés » de
la fiche App Store dans chaque langue : 4 000 caractères au plus.

Pour l'écrire, pars du brouillon « Prochaine version » des releases GitHub :
il liste les PR fusionnées depuis le dernier tag.

Pour les utilisateurs, pas pour les développeurs : en tutoyant (« you » en
anglais), 2 à 5 points forts, sans numéro d'issue ni nom de code, chaque
ligne au format `- **Titre.** Texte`. Les deux fichiers doivent être dans le
commit tagué : sans eux, la release échoue avant le build.
