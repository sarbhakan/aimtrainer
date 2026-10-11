# AIM/LOCAL

- Utiliser Godot 4.7.2 stable, édition standard, et GDScript typé.
- Lire `docs/SPECIFICATION.md` et `docs/DECISIONS.md` avant une implémentation majeure. La spécification décrit la cible complète ; implémenter seulement la phase demandée.
- Priorités : fidélité de la souris, pertinence des exercices, mesure réelle de la progression ; puis performances et interface.
- Nommer explicitement les unités : `_deg`, `_counts`, `_s`, `_ms`, `_cm`.
- Lire `InputEventMouseMotion.screen_relative` en capture. Ne jamais multiplier un déplacement souris par le delta temporel d'une frame.
- Garder le traitement des mouvements léger ; pas d'écriture disque ni de statistiques coûteuses sur ce chemin.
- Pause, menu et perte de focus libèrent la souris ; une reprise après perte de focus nécessite une action explicite.
- Séparer navigation, caméra/input, scénarios, métriques et persistance. Les futurs exercices partageront un moteur piloté par des données.
- Aucun plugin, compte, serveur ni accès à un jeu tiers n'est nécessaire au prototype. Les futures données utilisateur vont dans `user://`.
- Travailler dans le checkout existant ; ne pas créer de worktree, de branche ou de commit sans demande explicite.
- Vérifier les changements avec `bash tools/godot.sh --headless --editor --import`, puis `bash tools/test.sh` ; un code de sortie Godot nul ne suffit pas si le journal contient une erreur de script.
- Garder le protocole et les scores versionnés, les difficultés fixes pendant une comparaison, les échauffements et abandons exclus des tendances. Ne jamais annoncer une sensibilité universellement parfaite.
- Vérifier un jalon Windows avec `bash tools/export_windows.sh`. Distinguer export réussi, lancement natif et validation physique ; ne jamais annoncer un essai non exécuté.
- Consigner les limites et les choix provisoires dans `docs/DECISIONS.md` et `docs/TEST_PLAN.md`.
