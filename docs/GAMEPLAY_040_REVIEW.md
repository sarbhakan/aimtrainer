# Revue Gameplay 0.4.0 — poses initiales

Reprise du lot partagé non commité le 12 octobre 2026 (Europe/Paris). Godot 4.7.2 stable est disponible via `bash tools/godot.sh`. Validation limitée à la compilation `--check-only`, aux tests Gameplay ciblés et à la régression géométrique ; intégration finale laissée au parent.

## Résultat de l’audit

L’occlusion par le sol liée au pitch initial n’est pas reproduite dans le checkout actuel. Le compte à rebours accepte effectivement les rotations souris. `begin_training()` transmet les angles courants à `ScenarioEngine.start()` ; ces angles initialisent la timeline de visée. Les directions des cibles restent ancrées dans les angles mondiaux du scénario.

`TargetPool.sync()` place chaque centre à `camera.global_position + target_direction * distance_m`. Il ne multiplie pas la direction par la rotation caméra. Changer le pitch initial ne descend donc pas la cible sous le sol. Toute la sphère reste au-dessus du sol actuel à y = 0 m ; la borne analytique minimale du catalogue vaut 0,395607 m pour C07 à pitch mondial −17°, rayon 0,034906 m, profondeur 4 m et origine caméra y = 1,6 m. Le segment entre l’origine caméra et toute surface de cible reste au-dessus du sol. Cette conclusion ne dépend pas de la rotation de visée.

Le frustum doit en revanche être évalué depuis `camera.global_basis.inverse() * target_direction`. Les angles mondiaux seuls décrivent le cadrage nominal. Une caméra détournée pendant le compte à rebours peut commencer avec une cible hors écran ; elle retrouve cette cible en revenant vers ses angles mondiaux. La recadrer, déplacer les cibles ou remettre la visée à zéro modifierait ce comportement et n’est pas nécessaire pour corriger une occlusion dans cette version.

Le rapport moteur omettait `renderer`, alors que sa clé de comparaison encode déjà `compatibility`. L’audit de contexte a confirmé ce champ manquant sur des rapports clic et tracking. `ScenarioEngine.result()` le déclare désormais explicitement avec le label historique `compatibility`, sans utiliser `gl_compatibility` ni changer le protocole. Les mesures, scores, clés et empreintes restent identiques ; la compatibilité des anciens rapports reste gérée par le parent.

## Cas concret, scène réelle

C07, seed 23, t = 0 s, viewport 1280 × 720, FOV vertical 75°, yaw caméra 30°. La cible conserve yaw mondial 3,132039°, pitch mondial −16,474002°, centre (−0,209577 ; 0,465679 ; −3,830065) m et rayon 0,034906 m.

| Pitch caméra | Bas de la sphère | Erreur entre regard réel et cible | Centre projeté | Silhouette entière dans le frustum |
| --- | --- | --- | --- | --- |
| −30° | 0,430773 m | 28,040617° | (870,369 ; 263,189) px | Oui, cible turquoise effectivement rendue |
| +30° | 0,430773 m | 53,199234° | (979,424 ; 887,328) px | Non, centre sous les 720 px du viewport |

Les six captures C04/C07/S02 aux deux pitches et les cinq captures d’aperçu sont enregistrées sous `user://tests/`, dans des dossiers propres à chaque exécution. Les rendus sont obtenus avec OpenGL Compatibility, Mesa llvmpipe et Xorg dummy. Ils ne constituent pas un essai matériel Windows.

## Périmètre et invariants

Cette reprise complète le champ de rapport dans `scripts/training/scenario_engine.gd`, les preuves dans `tests/gameplay_quality_tests.gd` et cette note. Les poses testées comprennent yaw/pitch ±30°, pitch ±89°, yaw ±732°, yaw 180° et la pose nominale. Pour chaque pose, les 16 exercices, seeds 1/23/42/57 et temps 0/0,5/7,5/30 s sont comparés au moteur nominal. Les extrêmes angulaires déclarés sont aussi vérifiés contre le sol.

Les tests vérifient la base de Camera3D, les six plans réels du frustum, la projection des cibles cadrées, le rayon identique entre rendu et collision, la timeline initiale et la conservation du transform caméra et de tous les compteurs souris. Les tests d’aperçu existants comparent centres et rayons tangents à Camera3D avec trois couples FOV/ratio, y compris une cible C05 de moins d’un pixel sans agrandissement minimal. Les replays de démonstration restent vérifiés à 60/144/240 FPS.

Aucun changement mécanique, de génération, de hitbox, de vitesse, d’amplitude ou de difficulté n’est ajouté par cette reprise. Les scénarios et empreintes restent en révision 2 ; le patch Gameplay préexistant est conservé. Main, input, statistiques et les autres écrans restent sous la responsabilité du parent. Aucun export, import global, commit ou push n’est exécuté.

## Validation

Avant complément : Gameplay ciblé 803 assertions sans affichage et 832 avec rendu, géométrie 1560 assertions ; zéro échec.

| Contrôle final | Résultat | Journal |
| --- | --- | --- |
| Compilation Gameplay `--check-only` | Code 0, aucune erreur de script | `/tmp/aimlocal-gameplay-check-after.log` |
| Compilation géométrie `--check-only` | Code 0, aucune erreur de script | `/tmp/aimlocal-geometry-check-after.log` |
| Gameplay ciblé sans affichage | 2606 assertions, 0 échec | `/tmp/aimlocal-gameplay-after.log` |
| Gameplay ciblé avec rendu | 2635 assertions, 0 échec | `/tmp/aimlocal-gameplay-render-after.log` |
| Régression géométrique | 1560 assertions, 0 échec | `/tmp/aimlocal-geometry-after.log` |

Les six captures finales des poses sont dans `/workspace/.aim-local-tools/data/AIM_LOCAL/tests/gameplay_initial_pose_d7b49fecd95174bb/` ; les cinq captures finales des aperçus dans `/workspace/.aim-local-tools/data/AIM_LOCAL/tests/gameplay_quality_2ea109afeacda69b/`. Aucun journal final ne contient d’erreur de script ou de fuite. Le pilote logiciel signale seulement l’absence de contrôle VSync. La régression géométrique sans affichage annonce explicitement ses propres captures comme non exécutées.

Le runner temporaire `/tmp/aimlocal-gameplay-review.gd` appelle le module Gameplay existant depuis un `SceneTree`, compte les assertions et retourne un code non nul en cas d’échec. Il ne modifie pas le runner racine. Les commandes passent par `tools/godot.sh` ; les journaux sont contrôlés pour les erreurs de script et les fuites, en plus du code de sortie et du compteur final d’assertions.

Reproduction ciblée depuis `/workspace/aimtrainer` :

```bash
bash tools/godot.sh --headless --check-only --script /tmp/aimlocal-gameplay-review.gd
bash tools/godot.sh --headless --script /tmp/aimlocal-gameplay-review.gd
bash tools/godot.sh --headless --check-only --script res://tests/geometry_regression_tests.gd
bash tools/godot.sh --headless --script res://tests/geometry_regression_tests.gd
bash /tmp/aimlocal-gameplay-render.sh
```

Lot gelé après ces contrôles : aucune correction d’arène ou de mécanique n’est justifiée par les poses reproduites. Le parent conserve l’intégration des suites racine et adaptive, ainsi que les autres fichiers partagés.
