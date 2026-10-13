# AIM/LOCAL

Aim trainer 3D hors ligne pour Windows, en **Godot 4.7.2 stable et GDScript**.

La **1.0.0 — V2** remplace le catalogue public par **huit programmes de 60 secondes**, chacun décliné en Novice, Standard et Avancé : **24 configurations originales et 54 phases**. Le clic libre, les fenêtres temporisées, le suivi et les transitions avec points de vie ont leurs propres règles et scores. Les paramètres proviennent du kit fourni ; aucune difficulté n’est ajustée selon les résultats du joueur.

**Version 1.0.0 intégrée.** Les exercices, le parcours de calibration, le profil et la progression utilisent maintenant le moteur V2 natif. Les preuves logicielles et les limites matérielles sont consignées dans le [plan de réception](docs/TEST_PLAN_V2.md). L’export Windows est vérifié dans le cloud Linux ; son lancement natif et les essais avec une souris physique restent à effectuer.

- [Guide actuel des exercices, du moteur et de la calibration V2](docs/EXERCICES_ET_CALIBRATION_V2.markdown).
- [Plan de réception V2 et résultats effectivement observés](docs/TEST_PLAN_V2.md).
- [Cahier V2 original, conservé sans modification](docs/reference/v2/AIM_LOCAL_SPECIFICATIONS_V2.md).
- [Atlas animé hors ligne](docs/reference/v2/ATLAS_EXERCICES_V2.html), outil documentaire sans tir ni mesure humaine.
- [Documentation historique 0.9.0](docs/EXERCICES_ET_CALIBRATION.markdown), pour les anciens exercices, scores et protocoles.

## Télécharger et ouvrir

Distribution Windows : [AimLocal-1.0.0-windows-x64.zip](https://github.com/sarbhakan/aimtrainer/raw/refs/heads/main/downloads/AimLocal-1.0.0-windows-x64.zip) · [SHA-256](downloads/AimLocal-1.0.0-windows-x64.zip.sha256). Extraire **tout** le ZIP, puis lancer `AimLocal.exe`. L’application exportée ne demande ni Godot Editor, ni Python, ni Node, ni serveur local.

```powershell
Get-FileHash .\AimLocal-1.0.0-windows-x64.zip -Algorithm SHA256
```

Sur Mac, la [galerie V2](https://github.com/sarbhakan/aimtrainer/raw/refs/heads/main/downloads/AimLocal-1.0.0-visuels.zip) et sa [somme SHA-256](downloads/AimLocal-1.0.0-visuels.zip.sha256) permettent de consulter **70 captures natives** : menus, exercices, aperçus et exemples de bilans. Extraire le ZIP et ouvrir `gallery.html`. Ce n’est pas une application macOS. Les données de démonstration CAL sont explicitement synthétiques. Les [anciennes captures](docs/screenshots/README.md) restent historiques.

Pour ouvrir les sources, utiliser l’édition standard de Godot **4.7.2 stable**, avec les templates de cette version depuis les [releases officielles](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable). `project.godot` annonce 1.0.0 et utilise `scenes/app/MainV2.tscn` comme point d’entrée.

## Les huit programmes

| Programme | Déroulement actif | Résultat |
|---|---|---|
| EX01 — Acquisition | Micro 20 s, général 20 s, amplitude 20 s | Trois scores de clic séparés |
| EX02 — Multicibles | Grille 20 s, précision répartie 40 s | Deux scores de clic séparés |
| EX03 — Temporisées | Fenêtre fixe 30 s, rétrécissante 30 s | Deux scores d’opportunités, dix fenêtres par phase |
| EX04 — Clic mobile | Linéaire 20 s, évasif 20 s, arcs 20 s | Trois scores de clic séparés |
| EX05 — Suivi fluide | Horizontal 20 s, vertical 20 s, ellipse 20 s | Trois scores de contact et un indice du programme |
| EX06 — Suivi réactif | Une phase de 60 s | Contact et diagnostics des inversions |
| EX07 — Contrôle 3D | Une phase de 60 s, profondeur réelle de 3 à 5 m | Contact avec rayon physique constant |
| EX08 — Transitions | Statique 20 s, mobile 20 s, évasif 20 s | Maintien à 100 PV/s, destructions et dégâts partiels crédités |

Les trois niveaux gardent le même ordre et la même durée. Le suivi n’exige aucun bouton. Seule la deuxième phase d’EX03 rétrécit ; seules les cibles d’EX03 expirent selon une fenêtre programmée. Les cibles de clic libre restent jusqu’au hit ; les cibles de suivi persistent pendant leur phase. Le changement de phase conserve la visée et ne rajoute aucun temps mort.

## Souris, profil et données

Le contrôleur V2 utilise `InputEventMouseMotion.screen_relative`, applique le gain une fois par événement reçu et conserve l’ordre mouvement/clic. Il ne multiplie pas les mouvements par le temps d’une image. `received_pose_hold_v1` maintient la dernière pose reçue jusqu’au prochain événement ; la cadence de rendu ne reconstruit pas un trajet de souris inventé.

Le profil initial V2 utilise **800 DPI déclarés, 35 cm/360°**, soit `914,4 / (800 × 35)` degré par unité relative reçue. Le FOV de référence vaut **103° horizontal à 16:9**, soit environ **70,5328° vertical**. Les DPI ne sont pas mesurés par le logiciel ; la distance physique et le comportement Windows doivent être vérifiés à la règle et à la souris. CS2/Valorant et les profils de jeux restent des conversions documentées, sans accès aux processus ou fichiers de ces jeux ; l’ADS et le ressenti à FOV différent ne sont pas automatiquement équivalents.

Échap et perte de focus interrompent la capture. Une reprise exige une action explicite ; une pratique reprise garde ses diagnostics et reste exclue des records continus. Modifier le profil demande une nouvelle séance avec de nouvelles conditions de comparaison.

Les nouvelles données sont dans **`user://aim_local/v2`**, sous `%APPDATA%\AIM_LOCAL\aim_local\v2` sur Windows. Le stockage V2 conserve versions, conditions et empreintes. Les anciens rapports restent historiques et ne sont pas convertis en records V2. Une trace complète des poses reçues est une option de QA ; le mode léger courant ne permet pas de promettre un replay exact des entrées physiques.

## Calibration V2

Le protocole fourni est **`sustained_blocks_v2`**. Il remplace le parcours 0.9 de cinq activités et cinq sensibilités successives. Chaque période conserve un gain pendant **192 s** : 60 s de prise en main, puis quatre tâches dédiées de 24 s avec décomptes et récupérations. Ces tâches ne réutilisent pas la moyenne d’une carte de pratique.

L’express explore jusqu’à trois gains en **11 min 36 s** programmées. La confirmation compare la référence et un candidat pendant **deux journées distinctes de 16 min 48 s**, en ordres opposés ABBA/BAAB. Express à trois gains plus confirmation : **45 min 12 s sur trois séances**, hors attentes, reprises et pauses supplémentaires. Les intervalles entre journées, les conditions techniques, les garde-fous par tâche et les modalités de reprise sont explicités dans le [guide V2](docs/EXERCICES_ET_CALIBRATION_V2.markdown).

Le parcours natif sauvegarde le plan, exige une action avant chaque décompte, conserve les audits complets et restaure le profil initial après interruption. L’application du candidat demande une confirmation et conserve un retour au réglage précédent. Les conditions techniques ou une comparaison incomplète peuvent bloquer cette action. Aucun score d’exemple n’est un résultat utilisateur. Le bilan décrit un compromis observé parmi les gains testés après une prise en main courte, pas une sensibilité universellement parfaite.

## Développer et vérifier

Depuis la racine du checkout existant, l’import documentaire et ses tests utilisent seulement la bibliothèque standard de Python :

```bash
python3 -B tools/import_v2_atlas.py --kit docs/reference/v2 --output-dir content/v2 --check
python3 -B tests/v2_atlas_import_tests.py --kit docs/reference/v2
bash tools/godot.sh --headless --script res://tests/v2_catalog_tests.gd
```

L’import vérifie les **81 fichiers** du manifeste SHA-256 épinglé, l’accord de l’Atlas avec les **24 configurations et 54 définitions de phase**, puis les cinq JSON copiés octet pour octet. Il n’exécute aucun JavaScript et n’ouvre aucune URL. Le catalogue conserve sa structure originale ; les positions illustratives de l’Atlas ne deviennent pas des données du runtime.

Pour préparer un poste de développement et lancer les vérifications :

```bash
bash tools/setup_godot.sh
bash tools/godot.sh --headless --editor --import
bash tools/test.sh
bash tools/godot.sh res://scenes/app/MainV2.tscn
```

Le wrapper utilise Godot 4.7.2 et les outils vérifiés dans `/workspace/.aim-local-tools`, indépendamment du binaire global. `AIM_LOCAL_TOOLS_DIR` et `GODOT_BIN` permettent de sélectionner une installation compatible. Les services de jeu sont natifs : Python et les références du kit restent des outils de développement.

## Exporter et réceptionner

Le script importe les ressources, exécute les suites, exporte puis ouvre le pack hors du checkout avant d’empaqueter :

```bash
bash tools/export_windows.sh
```

Fichiers produits : `dist/AimLocal.exe`, `dist/AimLocal-1.0.0-windows-x64.zip` et sa somme `.sha256`. `downloads/` conserve seulement les dernières archives Windows et visuels ; les anciennes versions restent accessibles dans l’historique Git.

Pour reproduire la galerie native avec X11, Xvfb ou Xorg dummy :

```bash
bash tools/visual_smoke.sh
python3 tools/package_visuals.py
```

Le [plan de réception V2](docs/TEST_PLAN_V2.md) distingue tests logiciels, rendu réel, pack exporté et lancement natif Windows. Un import Godot réussi, un score de bot ou une galerie PNG ne prouve ni fidélité matérielle de la souris, ni latence de présentation, ni efficacité humaine de la calibration. Le build n’est pas signé ; la recette Windows, le polling physique et un pilote humain sur deux journées restent à réaliser.
