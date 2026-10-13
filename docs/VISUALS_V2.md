# Captures natives AIM/LOCAL V2

La galerie V2 cible la version **1.0.0** et charge réellement `scenes/app/MainV2.tscn`. Elle est distincte de la galerie historique 0.9 : aucun ancien PNG, marqueur CURRENT ou helper de packaging n’est réutilisé.

Recette de diffusion : **70 captures, 536 assertions, 0 échec**, run `20261013T001220_d57612555b4af0d8`. La projection analytique comparée à `Camera3D.unproject_position` présente au plus `0,000152587890625 px` d’écart, sous la tolérance de 0,5 px. Des pixels intérieurs sont vérifiés exactement en sRGB `#42D9CB`. La [galerie téléchargeable](../downloads/AimLocal-1.0.0-visuels.zip) et les [six aperçus directs](screenshots/v2/README.md) proviennent de ce run ; preuves et limites dans [validation/v2](validation/v2/README.md).

## Exécution

Depuis la racine du dépôt, avec Godot 4.7.2 et les ressources déjà importées par le parent :

```bash
bash tools/v2_visual_smoke.sh
python3 tools/package_v2_visuals.py
```

Le helper ne lance aucun import, setup, export Windows ou suite globale. Il effectue un `--check-only`, ouvre un affichage X11 existant ou temporaire, puis exécute uniquement `tests/v2_visual_smoke.gd`. Le rendu par défaut utilise Compatibility et Mesa logiciel ; `LIBGL_ALWAYS_SOFTWARE=0` permet un GPU disponible. Le serveur temporaire est arrêté par son propre PID.

`AIM_LOCAL_V2_SCREENSHOT_DIR` permet de choisir un dossier V2 distinct ; le défaut est `dist/preview_v2`. Chaque exécution crée `runs/<identifiant>/` et un profil QA sous `/tmp/aimlocal-v2-visual.*/userdata`. Le `V2Store` temporaire est injecté avant l’entrée de MainV2 dans l’arbre : les captures ne lisent ni n’écrivent les rapports utilisateur. Les journaux et le profil de test sont conservés pour diagnostic.

Le fichier `CURRENT` n’est publié qu’après les contrôles natifs réussis et la vérification indépendante du packager. Le runner prépare uniquement `CURRENT.pending` ; le helper ne le promeut qu’après avoir refusé toute erreur de script dans le journal, même lorsque Godot retourne zéro. Une exécution interrompue ne remplace pas la galerie précédente. Le packager revalide le manifeste, les PNG, les sources et les ressources avant de créer `dist/AIM_LOCAL_V2_visuals_1.0.0.zip` et son SHA-256. L’archive contient une galerie HTML locale, les captures, les contrats JSON, les fixtures CAL d’origine, le manifeste et `SHA256SUMS`. Son `CURRENT` référence le manifeste au sein de l’archive ; le marqueur source reste inchangé.

Pendant une intégration parent encore en cours, `AIM_LOCAL_V2_VISUAL_DRAFT=1 bash tools/v2_visual_smoke.sh` produit uniquement un run de diagnostic. Son manifeste porte `draft: true`, aucun `CURRENT` n’est publié, et le packager refuse de le promouvoir. Relancer sans cette variable après stabilisation des sources.

## Couverture

- Accueil, préparation, réglages, historique vide et état réel du service CAL en 800×450, 1280×720 et 1920×1080.
- Accueil capturé avec le pointeur retiré des cartes et le focus sur la navigation ; aucun aperçu d’un survol précédent ne masque les cartes.
- Aperçu réellement déclenché par survol, rendu par `V2Preview` et son moteur, avec rectangle de clipping enregistré.
- Les huit programmes Standard, toutes leurs phases, et un échantillon Novice/Avancé pour chaque programme.
- Pause native et résultat dérivé du moteur sans entrée joueur.
- Les huit statuts CAL, calculés par le service natif à partir de `docs/reference/v2/donnees/calibration_v2_comparison_examples.json`, avec une vue de synthèse et une vue native défilée vers les comparaisons et actions.

Les pratiques sont des **échantillons QA à temps actif explicite**, sans entrée joueur ; leurs zéros viennent des compteurs réels du moteur. Elles ne constituent pas des performances humaines ni une comparaison de sensibilité. Les résultats CAL sont **synthétiques**, issus des fixtures nommées du kit. Chaque image CAL porte cette mention et chaque ligne du manifeste conserve le nom, l’origine et l’empreinte de sa fixture. Les boutons d’application et de continuation restent désactivés pour ces exemples.

## Contrôles et traçabilité

La revue prévol UI expose `calibration_level_adjustment_requested(task: String, difficulty: String)`. Le parent fournit `stage: preflight` ou `preflight_review`, `phase: express`, `active: true` et `preflight.proposals` avec `task`, `suggested_level`, `can_adjust`. `preflight.records` peut être un dictionnaire par tâche ou une liste de lignes `{task, diagnostic_utility, difficulty}`. Les U absents restent absents ; les U présents sont uniquement diagnostiques. Un niveau de confirmation gelé, une validation déjà en cours ou une autorisation retirée désactivent les tests de 24 s. Le parent exécute et audite ces tests ; l’UI ne modifie jamais le plan elle-même.

Les captures facultatives de `tests/v2_ui_tests.gd` portent un marqueur de données synthétiques et ne font jamais partie de la galerie MainV2 publiée.

`show_history(rows: Array, progress_groups: Array = [])` reçoit directement les groupes de `V2Progress.summarize`. Il affiche les records entiers arrondis demi-vers-haut, séparés par programme, niveau, phase, famille et contexte. Les médianes des cinq premières et cinq dernières séances ne sont affichées qu’à partir de dix séances du même groupe, et uniquement si le backend les fournit. Aucun graphique ou groupe longitudinal n’est recalculé dans l’UI.

Le manifeste enregistre la version cible 1.0.0, la version effectivement déclarée dans `project.godot`, la scène chargée, le moteur, le renderer/driver réellement interrogé, l’adaptateur vidéo, le serveur d’affichage, les dimensions, MSAA, les snapshots, les profils, les graines et l’origine des données. Il inclut les SHA-256 des PNG, du projet, des sources UI/runtime et des polices ainsi que les empreintes du catalogue, des 24 définitions et du protocole `sustained_blocks_v2`. Les empreintes sémantiques emploient AIM-CANON-1 et sont recalculées par le packager. Les pratiques conservent le reçu d’arène observé après `RenderingServer.frame_post_draw`, sans prétendre prouver le scanout physique.

Pour chaque cible de pratique visible, le test compare le centre et les 128 points du cône tangent issus de **la même géométrie V2** à `Camera3D.unproject_position`. L’erreur maximale admise est **0,5 pixel**. Ce contrôle vérifie la projection analytique et les transforms du renderer ; il ne mesure pas l’erreur du contour rasterisé.

Le PNG est exporté en RGBA 8 bits. Des pixels intérieurs réellement rendus doivent valoir exactement **sRGB `#42D9CB`** ; leurs coordonnées sont enregistrées, puis les octets PNG sont décodés et vérifiés indépendamment par le packager. Une différence de gamma, une ressource stale, un mauvais hash ou une source modifiée pendant/après le run bloque la validation.

Ces captures proviennent de la **scène source native**, avec un affichage Linux pouvant être logiciel. Elles ne valident pas le binaire Windows exporté, l’écoute audio, la fidélité physique de la souris, les FPS matériels ou la latence du moniteur. L’export et la réception Windows restent sous la responsabilité du parent.
