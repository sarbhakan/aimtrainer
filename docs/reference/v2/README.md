# AIM/LOCAL — Kit de spécification V2 pour Codex

**Révision : 12 octobre 2026.** Huit programmes publics de 60 secondes, trois niveaux par programme, 24 configurations résolues et 54 phases. Le kit contient la conception technique, les visuels et des références numériques de développement. Il ne contient pas un exécutable Godot ni des résultats humains.

## Commencer

1. Lire [AIM_LOCAL_SPECIFICATIONS_V2.md](AIM_LOCAL_SPECIFICATIONS_V2.md). Ses 17 chapitres forment le contrat complet ; il remplace les choix du cahier V1.
2. Ouvrir [ATLAS_EXERCICES_V2.html](ATLAS_EXERCICES_V2.html) dans un navigateur existant pour parcourir les huit programmes, leurs trois niveaux, phases et mouvements. Le fichier est autonome et ne demande aucun réseau.
3. Examiner les planches dans [visuels/](visuels/) et les paramètres dans [donnees/catalogue.v2.json](donnees/catalogue.v2.json).
4. Donner [DEMARRER_AVEC_CODEX.md](DEMARRER_AVEC_CODEX.md) à Codex dans le dépôt existant, avec tout le kit accessible. Codex commence par inventorier les modules et formats réels.

Conserver le dossier entier après extraction : les images du cahier utilisent des chemins relatifs. L’HTML de l’atlas peut être copié seul. Les schémas d’axes et de trajectoires des planches sont documentaires ; ils ne sont pas affichés pendant une épreuve mesurée.

## Contenu

| Emplacement | Contenu |
|---|---|
| Cahier Markdown | Conception, modèles, tailles, vitesses, hasard, scores, états, rendu, calibration, données, réception et lots Codex. |
| `donnees/catalogue.v2.json` | Les 24 configurations complètes. Aucun multiplicateur de niveau implicite à inventer. |
| `donnees/interface.theme.json` | Couleurs, géométrie de scène, HUD, police, feedback, audio et adaptation UI. |
| `donnees/runtime.contract.json` | Tolérances numériques, collision, contact et limites de calcul à porter dans le moteur. |
| `donnees/atlas.etats.json` | Poses initiales et programmes des illustrations. |
| `donnees/calibration_v2_protocol.json` | Méthode `sustained_blocks_v2` et paramètres. |
| `donnees/calibration_v2_plan_example.json` | Plan synthétique complet : 44 cellules notées et 52 manifestes, sur trois séances. |
| `donnees/calibration_v2_comparison_examples.json` | Onze jeux d’entrée/sortie synthétiques couvrant les huit statuts. |
| `donnees/calibration_v2_plan_negative_fixtures.json` | Huit plans invalides réempreintés, à refuser pour leur sémantique. |
| `donnees/empreintes.fixtures.json` | Vecteurs d’encodage AIM-CANON-1. |
| `schemas/catalogue.schema.json` | Schéma fermé, versionné. |
| `outils/` | Références Python et contrôle JavaScript de l’atlas. |
| `visuels/` | 23 SVG et 23 PNG : huit planches, huit vues de jeu, six écrans d’interface et une planche d’états. |
| `assets/fonts/` | DejaVu Sans regular/bold et notice de redistribution. |
| `rapports/` | Contrôles numériques et simulation ; périmètre déclaré dans chaque rapport. |
| `references/EXERCICES_ET_CALIBRATION.md` | Description utilisateur de l’existant, conservée pour la traçabilité. |
| `SHA256SUMS.txt` | Empreintes des fichiers du kit, hors ce fichier d’empreintes lui-même. |

## Les huit cartes

| Carte | Programme |
|---|---|
| EX01 — Acquisition | 20 s micro, 20 s général, 20 s amplitude. |
| EX02 — Multicibles | 20 s grille, 40 s précision. |
| EX03 — Temporisées | 30 s fenêtre fixe, 30 s rétrécissement ; slots de 3 s indépendants des hits. |
| EX04 — Clic mobile | 20 s linéaire, 20 s esquive, 20 s arcs. |
| EX05 — Suivi fluide | 20 s horizontal, 20 s vertical, 20 s ellipse. |
| EX06 — Suivi réactif | 60 s de changements non périodiques avec vitesses et accélérations bornées. |
| EX07 — Contrôle 3D | 60 s de suivi en profondeur, rayon physique constant. |
| EX08 — Transitions | 20 s statique, 20 s mobile, 20 s esquive, avec maintien et points de vie. |

Les résultats C/P des phases différentes restent distincts. Les indices T/S conservent leurs composantes. Les scripts CAL sont des épreuves dédiées et ne réutilisent pas aveuglément les moyennes publiques.

## Calibration : durée et portée

Un gain reste appliqué pendant 192 s : 60 s de prise en main, puis quatre tâches de 24 s avec décomptes et récupérations. L’express explore trois gains en 11 min 36 ; la confirmation oppose le réglage initial et un candidat sur deux journées de 16 min 48, dans des ordres ABBA puis BAAB ou l’inverse. Le budget prévu est **45 min 12 sur trois séances**, hors pauses supplémentaires, reprises et réglages facultatifs. Aux bornes, un express à deux gains prend 7 min 54.

Le résultat décrit un meilleur compromis observé après une courte prise en main. Il ne garantit ni un optimum continu, ni une adaptation durable, ni une amélioration dans chaque jeu. Les 140 000 simulations artificielles exposent notamment une vulnérabilité aux effets de bascule ; elles ne constituent pas une validation humaine ou une garantie statistique.

Les valeurs des plans, écrans et exemples ne proviennent pas de l’utilisateur. Le plan d’exemple porte `engine_executable=false` et son rapport de validation indique `runtime_ready=false` : Codex doit générer un plan réel, renseigner les conditions et le sauvegarder avant la mesure.

## Vérifications reproductibles pour le développeur

Les références Python emploient uniquement la bibliothèque standard. Le contrôle JavaScript emploie uniquement les modules standards de Node et appelle Python comme oracle. Ces outils sont facultatifs sur le poste du joueur : **l’application finale doit fonctionner sans Python, Node, Godot Editor, serveur local ou installation de runtime tiers**.

Depuis la racine du kit :

```bash
python outils/valider_catalogue.py --self-test --report rapports/validation_catalogue.json
python outils/valider_mouvements.py --report rapports/mouvements.validation.json
python outils/calibration_v2_reference.py check
node outils/valider_atlas.js
```

Si l’exécutable Python porte un autre nom, définir la variable `AIM_LOCAL_PYTHON` pour `valider_atlas.js`. Adapter `python` à `python3` ou au launcher Python présent dans l’environnement de développement.

Pour produire un **nouveau** jeu d’exemples de référence dans un dossier séparé :

```bash
python outils/calibration_v2_reference.py build --output-dir ./cal_v2_generated
```

Pour répéter l’analyse des hypothèses de la décision :

```bash
python outils/calibration_v2_reference.py simulate --n 20000 --output ./calibration_simulation_reproduite.json
```

Pour reconstruire les SVG, données d’illustration et HTML à partir du catalogue :

```bash
python outils/construire_visuels.py
```

Cette commande ne rasterise pas les SVG en PNG. Les 23 PNG sont déjà livrés. Leur production relève de la chaîne de documentation, pas de l’application ; un rendu SVG de développement peut les recréer. Après toute modification du catalogue, actualiser les figures, les rapports et les empreintes ensemble.

## Limites de validation

Les rapports établissent la conformité des références Python/JavaScript, des données et des cas testés. Le contrôle de l’atlas utilise un DOM/canvas simulé et ne remplace pas une vérification dans un vrai navigateur. Les PNG ont été examinés comme documents ; le jeu n’a pas été exécuté dans Godot ni sur un PC Windows pendant la rédaction.

Il reste à réceptionner les entrées, le hitscan, l’intégration du contact, les remplacements après hits, les collisions temporelles, le rendu réel, les écritures et l’export Windows dans le dépôt. Le chapitre15 liste ces essais ; le chapitre16 ordonne le travail. L’expérience et la méthode de sensibilité demandent ensuite un pilote humain avant toute promesse de performance.

## Priorité en cas d’écart

Le cahier définit les invariants, le catalogue les valeurs résolues, le thème les tokens de présentation, les références les calculs et les figures leur lecture visuelle. Une contradiction est une erreur à corriger explicitement. Les valeurs fictives d’une maquette ou les états d’illustration ne remplacent jamais un score ou une entrée réelle. Les documents d’origine restent une trace de l’existant ; les anciens paramètres ne doivent pas être réintroduits silencieusement dans V2.

