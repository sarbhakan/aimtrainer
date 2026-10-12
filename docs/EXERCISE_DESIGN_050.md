# Exercices 0.5.0 — difficulté fixe, révision 3

Les seize exercices passent ensemble en révision 3. La géométrie est choisie pour chaque intention d'entraînement ; le diamètre angulaire, et non la seule distance, rend les cibles normales plus lisibles. C05 et T09 restent deux exercices de précision avancée facultatifs, identifiés dans leurs titres et consignes.

## Transmission immédiate : archives de checkpoints de révision 2

Les instantanés ci-dessous ont été relevés **avant toute modification**, avec Godot 4.7.2 et les seize ressources du checkout. L'ordre des paramètres est celui de l'empreinte historique :

```text
[id, revision, family, motion, layout, angular_diameter_deg,
 yaw_extent_deg, pitch_extent_deg, min_transition_deg, speed_deg_s,
 active_targets, lifetime_s, reference_hits_s, distance_m]
```

Pour `strafe` uniquement, `turn_duration_s` est ajouté en dernière position. L'empreinte est exactement `JSON.stringify(parameters).sha256_text()` dans Godot ; conserver les nombres flottants comme dans ces tableaux, sans réinterpréter les ressources actuelles. Titres et consignes ne font pas partie de l'empreinte mécanique.

```gdscript
const REVISION_2_PARAMETERS: Array[Array] = [
	["C01", 2, "click", "static", "scatter", 1.5, 12.0, 6.0, 3.0, 12.0, 1, 0.0, 2.0, 4.0],
	["C02", 2, "click", "static", "scatter", 1.2, 4.0, 3.0, 1.4, 12.0, 1, 0.0, 1.6, 4.0],
	["C03", 2, "click", "static", "grid", 1.2, 16.0, 9.0, 2.5, 12.0, 6, 0.0, 3.0, 4.0],
	["C04", 2, "click", "static", "scatter", 1.4, 24.0, 10.0, 14.0, 12.0, 1, 0.0, 1.8, 4.0],
	["C05", 2, "click", "static", "scatter", 0.7, 16.0, 9.0, 2.5, 12.0, 6, 0.0, 2.4, 4.0],
	["C07", 2, "click", "static", "scatter", 1.0, 4.0, 17.0, 6.0, 12.0, 1, 0.0, 2.0, 4.0],
	["D01", 2, "click", "static", "scatter", 1.5, 14.0, 8.0, 2.5, 12.0, 1, 1.0, 2.0, 4.0],
	["D02", 2, "click", "horizontal", "scatter", 1.8, 14.0, 6.0, 2.5, 16.0, 1, 0.0, 1.8, 4.0],
	["T01", 2, "tracking", "horizontal", "scatter", 2.0, 12.0, 3.0, 2.5, 12.0, 1, 0.0, 2.0, 4.0],
	["T02", 2, "tracking", "vertical", "scatter", 2.0, 3.0, 10.0, 2.5, 12.0, 1, 0.0, 2.0, 4.0],
	["T03", 2, "tracking", "diagonal", "scatter", 2.0, 12.0, 8.0, 2.5, 16.0, 1, 0.0, 2.0, 4.0],
	["T04", 2, "tracking", "circle", "scatter", 2.0, 13.0, 8.0, 2.5, 18.0, 1, 0.0, 2.0, 4.0],
	["T05", 2, "tracking", "strafe", "scatter", 1.8, 12.0, 3.0, 2.5, 26.0, 1, 0.0, 2.0, 4.0, 0.12],
	["T09", 2, "tracking", "horizontal", "scatter", 0.9, 12.0, 3.0, 2.5, 8.0, 1, 0.0, 2.0, 4.0],
	["S01", 2, "switching", "static", "scatter", 1.3, 22.0, 10.0, 4.0, 12.0, 4, 0.0, 2.8, 4.0],
	["S02", 2, "switching", "horizontal", "lanes", 1.8, 22.0, 10.0, 2.5, 14.0, 4, 0.0, 2.4, 4.0],
]
```

| ID | SHA-256 exact de révision 2 |
|---|---|
| C01 | `2d53ba690f9193a22297ed88195e6095413de70311dc333b6c72dbb6f9a97b31` |
| C02 | `a7fa138239543b4a6640556a2ada4bf2b969e1fbe0d41e478d8a1bb7b6f82602` |
| C03 | `1795b2281d6da16036da53b61351431286db7f084540b555e927afad33ca2f14` |
| C04 | `03334159e7e3601d16d4e79edbfef121a92198d5e4c017a2d81891b29aedcf92` |
| C05 | `d0e8281b35b2d3f8383d65bfd83870abdba1e848f9d6b1592d7d0255f75e917c` |
| C07 | `012aa5e030148ff415bcd03f153ae7e86754053df046df714fe106fa37c896d0` |
| D01 | `4757d9c517bf0bf972c7ba6db14c3fe247bcf7949eb38607ba5b958ac9b68a7f` |
| D02 | `5c0754e1d96ae843cc6b08d9e6d9a72c12695a542943831792b246f4ecbfa780` |
| T01 | `57d0ba43baf2b2a130b269dc7ee0186bb6d8d88d6a0821ab5607de788f39fb7f` |
| T02 | `a6a6b1bf45ff66d7d0f36b1a1c2f517c88181228ea0f98f78aa5e022caa18e03` |
| T03 | `d9dee3a5f889ba0b69176b9c7724927648d9006cbf81f8df122ffae638424f66` |
| T04 | `550ba9f5399212c75eb4601681f8dc203861866f00e985456d044e605d5d8ff7` |
| T05 | `661fcda2e1c27988d1463b20762f7d0152d4a4c5e1f322a985154612262e9bdf` |
| T09 | `8ab8bc353bf1870dfe0f76b66a069b1f734d7b5fa015283d8ec8857c81e037ce` |
| S01 | `2d35b015e4b51ec81c0a21c26c0f9e0aba9da9f89125ff9115e80172b64e1f08` |
| S02 | `3fe6e8a3e57f8767befe2e8c00721d8076363beab5a12fb4eb989e3d51979d2b` |

L'archivage est **implémenté par le parent**, propriétaire de la persistance, dans `CalibrationRevisionArchive` et les validateurs associés. Le parent annonce 123 assertions ciblées de migration réussies ; cette vérification est distincte des suites exercées ici. La fixture de protocole 1 utilise désormais ses paramètres gelés et ne dépend plus des ressources courantes. Contrat de migration conservé pour revue :

- Reconnaître explicitement les checkpoints de protocoles 2 et 3 utilisant ces empreintes, y compris les checkpoints encore sans essais. Le sous-ensemble de calibration est **C02, C04, S01, T01, T05**.
- Valider leur schéma, ordre des essais, facteurs candidats, graines, durées, profils, scores, contexte moteur/renderer et empreintes contre ces instantanés historiques. Ne pas reconstruire une ancienne difficulté depuis les ressources de révision 3.
- Archiver un checkpoint reconnu avant de démarrer une comparaison de révision 3 ; ne pas reprendre ses essais sous la nouvelle géométrie. Une recherche guidée et sa comparaison imbriquée doivent rester une même transaction cohérente.
- Conserver exactement les séances et bilans historiques, leurs références de cadence et leurs clés de comparaison. Les nouveaux records et tendances restent séparés par empreinte/révision.
- Préserver l'archive de protocole 1 et les fixtures historiques de révision 1. Les données corrompues, versions inconnues, ensembles d'empreintes mixtes et archives contradictoires restent conservés avec une erreur explicite ; pas d'écrasement ni d'archive automatique d'un fichier non reconnu.
- Tester les checkpoints v2/v3 partiels et vides, les recherches guidées, une archive idempotente, les conflits, les interruptions de transaction et l'absence de réinterprétation des anciens rapports.

## Réglages et intentions par exercice

Les limites yaw/pitch sont les demi-amplitudes déclarées, en degrés. La distance est celle du centre de la sphère depuis la caméra, pas simplement sa coordonnée Z. « Libre » signifie un clic par tir, remplacement immédiat après impact, sans cadence imposée ni tir automatique. Les vitesses indiquées sont des limites angulaires totales ; les sinusoïdes ralentissent naturellement aux extrémités.

| ID | Ce qui est entraîné et action du joueur | Distance | Diamètre | Limites yaw / pitch | Espacement, vitesse et cadence |
|---|---|---:|---:|---:|---|
| C01 | Acquisition statique générale : centrer, cliquer, rejoindre la suivante. La sphère tolère une arrivée encore imparfaite. | 4,5 m | 3,2° | ±14° / ±8° | Une cible, transition ≥4°, clic libre. |
| C02 | Courtes corrections près du centre : freiner et stabiliser avant le clic. L'entrée reste lisible ; la difficulté vient du geste court, pas d'un point minuscule. | 3 m | 2,5° | ±6° / ±4° | Une cible, transition ≥3°, clic libre. |
| C03 | Rythme et choix d'itinéraire : cliquer sur six grandes sphères réparties dans neuf cellules fixes. | 4 m | 4,8° | ±18° / ±10° | Grille 3×3, pas yaw 18° et pitch 10°, transition de remplacement ≥5,5°, clic libre. |
| C04 | Grands flicks et freinage : franchir un grand angle puis s'arrêter sur une cible confortable. | 5 m | 3,2° | ±30° / ±12° | Une cible, transition ≥20°, clic libre. |
| C05 | Précision fine avancée facultative : viser exactement puis cliquer sur six petites cibles. Une profondeur plus lointaine accompagne cette intention sans changer la taille angulaire de 0,7°. | 7 m | 0,7° | ±16° / ±9° | Six cibles, séparation ≥1,19°, transition de remplacement ≥2,5°, clic libre. |
| C07 | Freinage vertical : monter ou descendre dans une colonne étroite, puis cliquer. La faible profondeur garde les positions basses au-dessus du sol. | 3 m | 3° | ±3° / ±20° | Une cible, transition ≥10°, clic libre. |
| D01 | Détection et acquisition sous une échéance logicielle : cliquer avant expiration. | 4 m | 3,4° | ±16° / ±9° | Une cible, transition ≥4,5°, vie 1 s ; remplacement immédiat au clic ou à l'expiration. |
| D02 | Synchronisation du clic sur mobile : rejoindre et accompagner la sphère avant de cliquer. | 3,5 m | 3° | ±16° / ±6° | Une cible horizontale, ≤14°/s, clic libre. Un remplacement choisit une nouvelle base et phase. |
| S01 | Décision et transitions propres : choisir parmi quatre cibles, toucher puis changer immédiatement. | 4,5 m | 3,4° | ±24° / ±10° | Quatre cibles statiques, séparation ≥5,78°, transition de remplacement ≥6°, clic libre. |
| S02 | Transitions sur mobiles : sélectionner une sphère dans un autre couloir, anticiper son déplacement et cliquer. | 5 m | 3,2° | ±22° / ±12° | Quatre couloirs aux pitch −9°, −3°, +3°, +9°, écart ≥6° ; ≤16°/s, clic libre. |
| T01 | Suivi horizontal d'entrée : accompagner une grande sphère, ralentir avec elle, repartir régulièrement ; sans cliquer. | 4 m | 4° | ±16° / ±2° | Mouvement effectif yaw ±14,4°, pitch 0° ; ≤12°/s, cycle ≈7,54 s. |
| T02 | Corrections verticales continues : suivre sur une colonne jusqu'aux demi-tours ; sans cliquer. | 3,5 m | 3,6° | ±2° / ±16° | Mouvement effectif yaw 0°, pitch ±14,4° ; ≤12°/s, cycle ≈7,54 s. |
| T03 | Coordination des deux axes : suivre un aller-retour diagonal régulier ; sans cliquer. | 4,5 m | 3,4° | ±16° / ±10° | Mouvement effectif yaw ±14,4° et pitch ±9° ; vitesse totale ≤16°/s, cycle ≈6,67 s. |
| T04 | Fluidité dans une courbe : relier les deux axes sur une ellipse continue ; sans cliquer. | 5 m | 3,4° | ±15° / ±11° | Ellipse effective ±13,5° / ±9,9° ; vitesse totale ≤18°/s, cycle ≈4,71 s. |
| T05 | Maintien rapide et réacquisition : poursuivre à vitesse régulière puis changer de direction ; sans cliquer. | 3 m | 3,6° | ±16° / ±2° | Yaw effectif ±14,4°, pitch 0°, croisière 26°/s ; retournement 160 ms, demi-cycle ≈1,19 s, accélération ≤325°/s². |
| T09 | Micro-ajustements continus avancés facultatifs : suivre une petite sphère lente de faible amplitude ; sans cliquer. | 8 m | 0,9° | ±8° / ±2° | Yaw effectif ±7,2°, pitch 0° ; ≤6°/s, cycle ≈7,54 s. |

Pour D02/S02, le moteur choisit une base yaw dans ±45 % de la limite, puis lui ajoute une sinusoïde d'amplitude 45 % : l'enveloppe horizontale totale reste dans ±90 %. D02 conserve un pitch de base dans ±2,7° ; S02 utilise ses quatre pitch de couloir. La transition de remplacement de ces mobiles porte sur leurs coordonnées de base, pas sur un seuil garanti entre les centres mobiles à tout instant. Les couloirs S02 garantissent néanmoins une séparation de silhouettes pendant toute la trajectoire et après remplacement.

## Géométrie, visibilité et comparaison

La caméra reste à `(0, 1.6, 0)` et les directions sont fixées au monde. Une pose initiale différente change la visée et la timeline, jamais l'ancrage du champ. Le décor du parent utilise un sol à Y=0 et un mur à Z=−12 m ; toutes les sphères restent entre 3 et 8 m de leur caméra. Même l'extrémité arrière de T09 reste devant Z≈−8,063 m, avec plus de 3,8 m avant le mur.

Le rayon visible et le rayon analytique sont identiques : `distance_m × sin(diamètre / 2)`. Changer uniquement la distance ne rend pas la cible plus grosse à l'écran. Les grossissements normaux sont donc des modifications explicites de `angular_diameter_deg`. À 1280×720 et FOV vertical 75°, le diamètre central de C02 passe d'environ 9,83 à 20,47 px, C01 de 12,28 à 26,21 px et C03 de 9,83 à 39,33 px. À 800×450, C02 atteint environ 12,80 px. Ces valeurs décrivent la projection ; elles n'imposent aucun minimum en pixels ni aucun agrandissement dépendant de la fenêtre.

La borne conservatrice du bas de la sphère est `1.6 − distance_m × (sin(pitch_extent_deg) + sin(diamètre / 2))`. Le pire cas déclaré est C04/S02, à environ **0,421 m** au-dessus du sol. Les définitions de révision 3 incompatibles avec le sol sont refusées. Les grandes cellules de C03 sont vérifiées avant génération ; S02 garde 6° entre couloirs pour un diamètre 3,2°, au-delà de la marge 1,7×diamètre = 5,44°. Les autres champs à plusieurs cibles utilisent la même marge de génération sans chevauchement.

Tous les exercices tiennent intégralement dans **16:9 / FOV vertical 75°**. Les profils conservent leur plage de FOV 40–110° ; un cadrage incompatible avec toute la silhouette, par exemple C07 à 40°, est refusé par la garde de frustum. Aucun rétrécissement automatique du champ, snap de caméra, agrandissement lié au FOV, aux performances ou à la fenêtre n'est introduit.

La préparation utilise un second moteur avec la même graine : les sphères restent visibles à leur position `t=0` pendant les 3 secondes de décompte, sans avance du temps, expiration, tir ou mesure. Le moteur mesuré redémarre à zéro avec ces mêmes directions et phases. Les counts reçus pendant la préparation orientent toujours la caméra ; le départ les prend comme origine de compteurs, et ne les ajoute pas au trajet mesuré.

L'aperçu utilise une copie de la nouvelle difficulté et un moteur indépendant. Il relit la taille et la distance après reconfiguration et n'écrit aucune mesure joueur. Sa cadence de clic simulée appartient à l'illustration ; elle n'impose aucune cadence dans l'exercice réel.

## Scores et calibration

La formule de score reste **V1** : clic/switching `round(1000 × hits_per_s × accuracy_fraction² / reference_hits_s)` ; tracking `round(1000 × on_target_time_s / target_exposed_time_s)`. Les références de cadence restent celles de révision 2 : C01/C07/D01 = 2 touches/s, C02 = 1,6, C03 = 3, C04/D02 = 1,8, C05/S02 = 2,4, S01 = 2,8. Le champ par défaut 2 reste inchangé pour les suivis, où il ne normalise pas le score.

Ces références sont des échelles de score provisoires, pas des cadences obligatoires ni des seuils validés sur une population. Les cibles plus grandes pourront relever le score habituel : cela justifie des nouveaux contextes, pas un ajustement arbitraire de la formule ou des seuils. Une future modification de référence devra publier les mesures qui la motivent, mettre à jour l'empreinte et séparer de nouveau les comparaisons.

La calibration garde **C02/C04/S01/T01/T05**, mêmes géométries et vitesses pour tous les candidats, avec les graines, durées et compteurs mesurables. La taille plus confortable de C02 ne supprime pas son geste court ; C04 conserve des grandes transitions ; S01 exige de choisir ; T01 entraîne le suivi souple ; T05 reste plus rapide et impose des réacquisitions. C05/T09 ne deviennent pas des étapes obligatoires de calibration. Les performances humaines, la fatigue et le transfert en FPS devront toujours être évalués séparément.

Les titres et consignes des ressources C05/T09 indiquent explicitement « avancé » et « facultatif ». La présentation du parent doit conserver cette distinction dans `ScenarioCopy`, qui remplace les titres et descriptions des ressources dans les cartes.

## Validation ciblée

Godot 4.7.2 épinglé et imports existants sont disponibles. Suites géométrie et qualité de gameplay en headless, sans capture graphique ni export concurrent : validation des bords de silhouette avec Camera3D, distances et frustum, sol/mur, espacements après remplacement, limites de vitesse/accélération, replays 60/144/240 FPS avec RNG et événements identiques, aperçu indépendant et préparation sans mesures. La fixture C02 de révision 1 conserve explicitement son diamètre 0,65°, son champ ±4°/±3°, sa transition 1,4° et sa profondeur 8 m.

- Géométrie : **2 001 assertions, 0 échec** ; commande `bash tools/godot.sh --headless --script res://tests/geometry_regression_tests.gd`, journal `/tmp/aimtrainer-exercise-geometry.log`.
- Gameplay : **3 418 assertions, 0 échec** ; le runner temporaire `/tmp/aimtrainer_focused_gameplay.gd` appelle uniquement `GameplayQualityTests.run`, journal `/tmp/aimtrainer-exercise-gameplay.log`.
- Les deux journaux confirment leurs marqueurs de fin, un code de sortie 0 et aucune ligne `ERROR`/`SCRIPT ERROR` ni fuite signalée. L'import existant est disponible ; aucune nouvelle installation ou configuration d'environnement n'est nécessaire.
- La géométrie exerce 4 096 remplacements pour chacun des huit exercices statiques. Minimum mesuré : grille C03 10°, S01 5,781°, C05 1,194° ; S02 reste à 6° sur 64 graines et 601 instants, puis 100 remplacements. La borne conservative du sol 0,421 m est confirmée aux extrêmes, pour toutes les poses initiales permises.
- Vitesses maximales mesurées : D02 13,999°/s, T01/T02 12°, T03 16°, T04 17,732°, T05 26,001°, T09 6°, S02 15,979°. L'accélération T05 mesurée par différence finie est 327,223°/s², compatible avec la borne analytique 325°/s² et la tolérance numérique du test.
- Les tests de préparation exercent réellement l'application pour les 16 exercices : cibles visibles figées, clic ignoré, counts souris conservés, second moteur non mesuré, même RNG et sphères au départ, temps de naissance et métriques remis à zéro.
- Les captures graphiques, l'export et la suite finale intégrée restent sous coordination du parent. Les tests headless ne certifient ni visibilité rendue en pixels, ni souris physique, ni expérience joueur.
