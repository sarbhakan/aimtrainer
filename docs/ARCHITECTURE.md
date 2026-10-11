# Architecture — 0.4.0

## Responsabilités

| Module | Responsabilité |
|---|---|
| `scripts/core/main.gd` | Navigation, focus, compte à rebours, orchestration des séances/calibrations |
| `scripts/core/session_clock.gd` | Temps monotone actif, pauses exclues |
| `scripts/input/aim_camera.gd` | `screen_relative` → angles explicites, sans delta, lissage ou accélération |
| `scripts/input/aim_timeline.gd` | File circulaire de 32 768 poses horodatées, counts reçus et trajet angulaire |
| `scripts/training/scenario_definition.gd` | Paramètres angulaires validés et empreinte immuable du contexte |
| `content/scenarios/*.tres` | 16 exercices pilotés par les données |
| `scripts/training/scenario_engine.gd` | RNG local, cibles, trajectoires, tirs, intégration et métriques |
| `scripts/training/aim_geometry.gd` | Directions, erreur angulaire stable près de zéro, rayons/sphères |
| `scripts/training/target_pool.gd` | Six instances de sphères, mesh/matériau partagés |
| `scripts/sensitivity/` | Unités physiques, conversions, plan expérimental et recommandation |
| `scripts/sensitivity/game_profile_service.gd`, `scripts/ui/sensitivity_import.gd` | Validation des profils source, provenance et import sans confusion DPI source/actuels |
| `scripts/sensitivity/adaptive_sensitivity_service.gd` | Recherche bornée, choix des plages et historique vérifié depuis les passages |
| `scripts/presentation/crosshair_profile.gd`, `scripts/ui/crosshair_settings.gd` | Viseur validé, dessin natif et aperçu live |
| `scripts/ui/interaction_feedback.gd`, `record_celebration.gd` | Interactions et célébrations bornées, animations réduites |
| `scripts/statistics/performance_insights.gd`, `scripts/ui/progress_board.gd` | Mesures expliquées, filtres et tableau comparable |
| `scripts/statistics/` | Score versionné, contexte comparable, progression |
| `scripts/persistence/local_store.gd` | JSON local, validation, backups, checkpoint, archives, CSV |
| `scripts/ui/` | Tableau de bord et bilan ; aucun calcul de scoring caché dans l'interface |
| `scripts/ui/aim_ui.gd`, `scenario_copy.gd` | Composants communs et textes de présentation séparés des définitions versionnées |
| `scripts/ui/training_browser.gd`, `scenario_preview.gd`, `exercise_preview_popup.gd` | Cartes filtrables et bulles au survol/focus/clic, RNG local distinct des séances |
| `scripts/ui/training_hud.gd`, `session_panel.gd`, `score_chart.gd` | HUD discret, résultats progressifs et courbes des scores comparables |
| `scripts/presentation/`, `content/weapons/` | Profils d’arme et retour audiovisuel cosmétique, sans effet sur les mesures |
| `scenes/`, `assets/` | Assemblage de l'arène, caméra à hauteur 1,6 m, HUD, pause, thème |
| `tests/`, `tools/` | Tests synthétiques, benchmark, export vérifié et installation épinglée |

## États

`HOME → COUNTDOWN → TRAINING → RESULTS`, ou `REST → COUNTDOWN` dans le parcours guidé. `TEST` conserve le diagnostic souris sans score. `PAUSED` mémorise l'état interrompu ; aucune reprise automatique après un retour de focus.

Le compte à rebours de deux secondes permet de préparer le geste. Il accepte la rotation mais pas les tirs ni les métriques ; le moteur démarre avec la pose obtenue à son terme. Un abandon garde une séance partielle, exclue des records. Une variation du format de fenêtre invalide la séance et la calibration reprend uniquement au format d'origine.

Le clic et le dernier tick peuvent demander simultanément la fin : un drapeau et un appel différé garantissent une seule sauvegarde. La progression de calibration est validée seulement si l'écriture du checkpoint réussit ; sinon le passage reste disponible en mémoire et l'index est annulé. Un checkpoint complet permet de revoir le bilan après redémarrage, y compris après une interruption entre sa dernière écriture et celle du bilan.

## Trois chemins temporels

1. **Input** : pose caméra immédiatement modifiée par le delta `screen_relative`, jamais par un frametime. Yaw/counts accumulés en `float` 64 bits ; yaw rendu ramené dans ±180° pour limiter la perte de précision de la pose 3D.
2. **Mesure** : poses horodatées avec le chronomètre actif dans trois tableaux `PackedFloat64Array`. L'intégrateur tracking lit la dernière pose connue aux milieux de pas fixes de 1/240 s. Les clics utilisent le rayon caméra et la position analytique au moment du clic. Les expirations suivent l'horloge, pas les frames.
3. **Rendu** : positions analytiques actualisées sur le pool, HUD à 10 Hz. Histogramme d'erreurs de 0,1° et frametimes récents bornés à 4 096 entrées ; médianes/percentiles calculés en fin de séance, hors du handler souris.

Les événements peuvent être regroupés par Godot : l'horodatage reflète la réception dans l'application, pas l'heure native de chaque paquet HID. L'intégration fixe rend un même replay logiciel comparable entre FPS, mais ne restitue pas les mouvements perdus ou fusionnés en amont. Une saturation invalide le résultat au lieu de masquer la perte. La métrique de frametime ignore le premier tick après départ/reprise pour ne pas compter une pause comme un freeze de jeu.

## Présentation indépendante

Les 16 ressources d’exercice passent en révision 2 avec une profondeur de 4 m depuis l’origine réelle de la caméra. C02 a un diamètre de 1,2°, C07 reste entièrement au-dessus du sol, S02 conserve des couloirs séparés, T03 respecte sa vitesse totale et T05 inverse continûment sa vitesse en 120 ms. La sphère complète doit tenir dans le frustum ; son rayon rendu est celui utilisé pour la collision. Les empreintes changent et protègent les anciens résultats de toute comparaison trompeuse.

`ScenarioCopy` fournit les noms et consignes. Les aperçus utilisent une instance distincte de `ScenarioEngine` ; leur cadrage illustratif ne sert jamais au scoring. Les miniatures sont statiques, la bulle apparaît après 180 ms au survol/focus ou immédiatement au clic ; un seul aperçu est animé à 30 Hz par écran. La fermeture, le changement de page, la recherche ou le défilement coupent la bulle et les traitements masqués.

`WeaponFeedback` préalloue quatre lecteurs de tir et un lecteur continu. Il reçoit un profil au lancement de la séance, hors du chemin souris, puis réutilise ses ressources. La boucle PCM est dupliquée avant configuration pour ne pas modifier la ressource partagée ; sa fin est exprimée en frames (`durée × fréquence`). L’import des six WAV désactive la compression QOA par défaut. La transformation de recul affecte uniquement le sprite HUD, jamais la caméra. Le clic maintenu en tracking n’appelle pas `ScenarioEngine.shoot` et n’ajoute aucune contrainte de score.

L’interface responsive conserve les boutons de lancement et d’enregistrement hors des défilements. Les bilans affichent trois indicateurs utiles et replient les données techniques ; les erreurs de persistance restent visibles indépendamment de ce repli. Les choix UX et l’ajout d’équipements sont documentés dans `docs/UI_UX.md`.

## Recherche et retours 0.4.0

`CalibrationService` reste le comparateur de cinq blocs 3+9, avec trois facteurs configurables et un protocole 3. Le protocole 2 garde ses facteurs historiques ; la reprise rejoue et valide les passages. `AdaptiveSensitivityService` ne pilote ni caméra ni difficulté : il vérifie les bilans complets, choisit une prochaine plage et borne la recherche à quatre comparaisons. Les choix sont reconstruits depuis les passages, pas depuis un score ou un gagnant déclarés arbitrairement.

`Main` demande une action explicite entre comparaisons. Un départ hors de la zone attend le réalignement avec un repère et une flèche, sans reset des counts ou des angles. Le chronomètre de mesure commence seulement quand toute la zone peut tenir dans le champ.

Les viseurs sont cosmétiques et validés par `CrosshairProfile`. Le hitmarker dure 110 ms et ne décale pas la caméra. Les records sont recherchés avant l’écriture de la nouvelle séance puis célébrés seulement après une sauvegarde réussie, à contexte identique. La validation recalcule également la clé depuis les métadonnées du rapport et le score depuis ses mesures. Un vieux renderer absent signifie le backend Compatibility implicite, pas une métadonnée arbitraire acceptée.

## Persistance

`user://` est fixé au dossier applicatif `AIM_LOCAL`. Toutes les données produit vont dans `aim_local/` : `profile.json`, `sessions/<id>.json`, `calibration_checkpoint.json`, `calibrations/<id>.json`, `archives/`, `exports/`. Les tests injectent un autre dossier aléatoire sous `user://tests/` et ne touchent pas aux données réelles.

Schéma JSON 1, score 1, protocole 3 avec reprise compatible 2. Cinq blocs de trois familiarisations puis neuf mesures ; les positions A/B/C tournent. Les médianes brutes restent séparées de l’utilité normalisée. Refaire conserve candidat, graine et checkpoint jusqu’à validation.

`guided_calibration_checkpoint.json` contient la phase, le checkpoint du contrôleur et celui du comparateur dans un remplacement atomique unique. `comparing` peut être entièrement terminé mais pas encore traité ; `transition` conserve le bilan accepté et la prochaine plage ; `complete` conserve le conseil. L’enveloppe vérifie la cohérence entre les deux états, les facteurs, profils, graines, identifiants et passages. Une panne annule la décision mémoire ; une reprise n’accepte pas deux fois le même bilan. Les anciennes recherches sont archivées, les fichiers inconnus ou incohérents restent protégés.

Le float canonique des champs source est séparé du `Range` et de l’affichage arrondi ; focus/blur sans modification ne réinterprète pas une mesure historique. JSON Godot peut déplacer les derniers bits lors d’une relecture : les tests utilisent une tolérance relative de 1e−14, sans quantification intermédiaire du profil.

Sauvegarde en précision complète, temporaire + flush + backup + rename, sans enlever l'original avant le remplacement. Un ancien protocole 1 reconnu est archivé avant une nouvelle comparaison ; aucun replay n’est tenté avec la nouvelle géométrie. Les JSON incohérents ou inconnus ne sont pas écrasés. Les rapports de séances/bilans sont immuables ; revoir un bilan identique est idempotent. Les identifiants ne peuvent pas être des chemins. Le chargement d'historique porte sur les 2 000 fichiers les plus récents ; les fichiers plus anciens restent sur disque.

Le modèle distingue `current_distance_cm`/`destination_yaw_deg` des SpinBox arrondis. `reference_game` conserve les DPI, la sensibilité, le coefficient, la distance et la provenance **historiques**, indépendamment des ajustements AIM/LOCAL ultérieurs. L’import conserve les DPI actifs, n’agit pas sur le matériel et sauvegarde avant d’appliquer à la caméra. CoD/autre exigent une mesure par titre/version ; sans référence connue, la copie d’une conversion est désactivée. Ces métadonnées ne modifient pas la clé mécanique de comparaison.

Le profil accepte en plus les champs optionnels `weapon_id`, `sound_enabled`, `sound_volume`, `show_weapon` et `reduced_motion`. Un profil 0.1.0 sans ces champs reste valide et reçoit les valeurs par défaut dans l’interface. Leur validation refuse les types et valeurs invalides ; ces préférences ne font pas partie de la clé de comparaison mécanique. `ProgressService` expose les 20 derniers scores déjà filtrés sans modifier la médiane ni la tendance. La version applicative des nouveaux rapports vient de `project.godot`.

Le backup n'est pas restauré automatiquement : préserver le fichier fautif, puis restaurer une copie valide selon le plan de tests. La résistance à une coupure d'alimentation au niveau filesystem n'est pas prouvée par les seuls tests de rename. Pas de réseau, de compte ou d'accès aux jeux tiers.

## Export

Windows x86-64 release, PCK embarqué, ressources produit complètes. Le filtre `all_resources` inclut les services `class_name` et les scénarios, que le filtre limité aux scènes omettait malgré leur emploi dans les scripts. Tests, docs, outils, captures et anciens téléchargements sont exclus. L’export ouvre ensuite le pack avec Godot Linux dans un dossier vierge, puis lance un harness externe qui exerce les 16 scénarios et vérifie les trois profils d’arme embarqués. Aucune ressource du checkout ne doit servir de remplacement. Le nom du ZIP est dérivé de la version de `project.godot`. Ce n’est pas une validation native Windows.
