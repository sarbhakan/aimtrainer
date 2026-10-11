# Architecture de la V1 0.1.0

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
| `scripts/statistics/` | Score versionné, contexte comparable, progression |
| `scripts/persistence/local_store.gd` | JSON local, validation, backups, checkpoint, archives, CSV |
| `scripts/ui/` | Tableau de bord et bilan ; aucun calcul de scoring caché dans l'interface |
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

## Persistance

`user://` est fixé au dossier applicatif `AIM_LOCAL`. Toutes les données produit vont dans `aim_local/` : `profile.json`, `sessions/<id>.json`, `calibration_checkpoint.json`, `calibrations/<id>.json`, `archives/`, `exports/`. Les tests injectent un autre dossier aléatoire sous `user://tests/` et ne touchent pas aux données réelles.

Schéma JSON 1, score 1, protocole 1. Sauvegarde en précision complète, temporaire + flush + backup + rename, sans enlever l'original avant le remplacement. Les JSON invalides ou d'un schéma inconnu ne sont pas écrasés. Les rapports de séances/bilans sont immuables ; revoir un bilan identique est idempotent. Les identifiants ne peuvent pas être des chemins. Le chargement d'historique porte sur les 2 000 fichiers les plus récents ; les fichiers plus anciens restent sur disque.

Le backup n'est pas restauré automatiquement : préserver le fichier fautif, puis restaurer une copie valide selon le plan de tests. La résistance à une coupure d'alimentation au niveau filesystem n'est pas prouvée par les seuls tests de rename. Pas de réseau, de compte ou d'accès aux jeux tiers.

## Export

Windows x86-64 release, PCK embarqué, ressources produit complètes. Le filtre `all_resources` inclut les services `class_name` et les scénarios, que le filtre limité aux scènes omettait malgré leur emploi dans les scripts. Tests, docs et outils sont exclus. L'export ouvre ensuite le pack avec Godot Linux dans un dossier vierge, puis lance un harness externe qui exerce les 16 scénarios embarqués. Aucune ressource du checkout ne doit servir de remplacement. Ce n'est pas une validation native Windows.
