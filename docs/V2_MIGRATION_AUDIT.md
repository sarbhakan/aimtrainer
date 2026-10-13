# Audit de migration AIM/LOCAL V2

## 1. Périmètre et état réellement observé

Audit documentaire du checkout `/workspace/aimtrainer`, avec lecture d'[AGENTS.md](../AGENTS.md), des [décisions](DECISIONS.md) et du préambule de la [spécification existante](SPECIFICATION.md). Le commit observé est **`4e945c85f1060fa0ce17a043be0e3c108fd6c862`**, et [project.godot](../project.godot) déclare **0.9.0**, `Main.tscn`, Godot 4.7 et Compatibility. Les instructions et outils épinglent **Godot 4.7.2 stable standard**. Aucun binaire moteur ni exécutable Windows n'a été lancé par ce travail documentaire.

La référence normative est le [cahier V2](reference/v2/AIM_LOCAL_SPECIFICATIONS_V2.md), complété par l'[Atlas](reference/v2/ATLAS_EXERCICES_V2.html) et les fichiers numériques du kit. Le commit `68b111699409972e7799994969ef5e90983c7277` cité dans le cahier décrit son contexte de rédaction ; il ne correspond pas au HEAD observé ici. Les mentions de 16 exercices ou de rendu sans ombres dans les anciennes décisions décrivent des étapes antérieures : elles ne doivent pas remplacer l'inventaire 0.9 ci-dessous.

Le kit complet fourni ensuite est lisible dans `/workspace/attachments/aimlocal-kit-v2/AIM_LOCAL_KIT_CODEX_V2` ; **82 fichiers** ont été inventoriés. Son cahier et son HTML sont identiques octet pour octet aux deux pièces jointes initiales. Le parent archive les sources exactes dans `docs/reference/v2/`, destination des liens de cet audit. La vérification globale du ZIP est annoncée par le parent ; cet audit ne revendique pas avoir rejoué tous les contrôles livrés.

**État du produit audité : aucune des huit cartes V2 ni calibration `sustained_blocks_v2` n'est implémentée/jouable dans le HEAD 0.9 observé.** Le chantier parallèle commence par les fondations natives, les sources et les assets. La cible autorisée est désormais la migration complète, pas un arrêt permanent faute de kit. Les travaux en cours du parent ne sont pas des preuves de réception et ne sont pas comptés comme terminés ici.

Décisions de coordination pour la suite :

- Conserver les modules 0.9, leurs scènes, ressources, validateurs et tests historiques ; ajouter un espace V2 distinct.
- Préparer une **scène `MainV2` séparée**, avec un contrôleur V2 et une autorité mécanique commune aux huit programmes. Le catalogue public final expose huit cartes, jamais les 18 entrées legacy sous des noms V2.
- Le parent possède CANON, PRNG, géométrie, nouveau moteur V2, contrôleur et persistance V2 ; un agent UI pourra posséder les nouveaux composants de présentation sans modifier ces autorités.
- La version produit prévue est **`1.0.0-V2` après validation de l'intégration**. Ni la présence de JSON ni une capture de maquette ne justifient de déclarer cette version reçue.
- Ce worker modifie uniquement `docs/V2_MIGRATION_AUDIT.md` : aucun code runtime, import, export, test complet, branche ou commit. L'exemple générique de branche/prompts du kit n'est pas une instruction supérieure aux consignes du dépôt et au périmètre utilisateur.

## 2. Inventaire de la 0.9 et points de raccordement

L'arbre audité contient **43 scripts `.gd` produit**, **36 fichiers `.gd` de tests/helpers**, trois scènes produit et 18 ressources scénario. Ces quantités décrivent le HEAD de départ, pas les fichiers V2 que d'autres workers peuvent ajouter ensuite. Il n'y a pas de section autoload dans `project.godot` : `main.gd` construit explicitement ses services.

| Responsabilité actuelle | Source et comportement observé | Raccordement V2 prévu, sans modifier les contrats legacy |
|---|---|---|
| Point d'entrée et orchestration | [Main.tscn](../scenes/app/Main.tscn), [main.gd](../scripts/core/main.gd) : états `HOME/TEST/PAUSED/COUNTDOWN/TRAINING/RESULTS/REST`, moteurs actif/préparation, flags calibration/routine, sauvegarde avant relance | `MainV2` possède chargement, séance/phases, résultats et CAL ; il ne transforme pas `start_practice()` en simple alias EXxx vers Cxx/Txx. Garder `Main.tscn` pour la compatibilité et ses tests. |
| Horloge | [session_clock.gd](../scripts/core/session_clock.gd) : accumulation monotone en µs, pause/reprise ; le moteur reçoit des secondes flottantes | Introduire les temps actifs entiers et la séquence totale V2 ; préserver l'horloge legacy et séparer UTC/date locale des calculs mécaniques. |
| Souris/caméra | [aim_camera.gd](../scripts/input/aim_camera.gd), `_input()`/`apply_profile()` dans `main.gd` : `screen_relative`, gain sans delta, pitch ±89°, yaw déroulé ; accumulation configurable, défaut true | Nouveau chemin V2 à gain effectif unique, accumulation false, commandes motion/press/release/focus ordonnées. Le contrôleur V2 transmet la pose intermédiaire au clic. |
| Trace du regard | [aim_timeline.gd](../scripts/input/aim_timeline.gd) : anneau 32 768 poses, tableaux float64, maintien de dernière pose, overflow signalé | Ajouter identité de commande, séquence et timestamps reçus/logiques ; une trace de poses seule ne fournit ni journal des boutons ni marqueurs de rendu. |
| Définitions et registre | [scenario_definition.gd](../scripts/training/scenario_definition.gd), [scenario_catalog.gd](../scripts/training/scenario_catalog.gd), [content/scenarios](../content/scenarios) : ressources plates, révisions et empreintes JSON | Nouveau registre de définitions V2 validées, `program_id/difficulty/phases`, champs fermés, hash CANON. Conserver `find()/find_lifecycle()/find_practice()/resolve()` et les anciennes empreintes. |
| Simulation | [scenario_engine.gd](../scripts/training/scenario_engine.gd) : une définition par séance, RNG Godot, slots dictionnaires, `start()/advance_to()/shoot()/result()`, intégration midpoint 240 Hz | Moteur V2 commun : manifeste, phases, générations, programmes de mouvement immuables, fenêtres exogènes, rendu admissible, contact borné et PV. Les anciens `shoot()` et `result()` ne satisfont pas seuls ce contrat. |
| Géométrie | [aim_geometry.gd](../scripts/training/aim_geometry.gd) : directions, projection tangente, frustum et rayon/sphère ; vecteurs Godot | Autorité V2 scalaire binary64 et convention yaw positive-droite. Garder les signes, tolérances et calculs legacy pour leurs historiques. |
| Rythmes 0.9 | [tracking_rhythm.gd](../scripts/training/tracking_rhythm.gd) : programmes seedés de vitesse signée qui remappent le temps des anciennes trajectoires | Porter les modèles du compilateur livré ; ne pas assimiler `TrackingRhythm` à `reactive_axis`, à l'ellipse métrique ou aux sinusoïdes V2. |
| Rendu des cibles | [target_pool.gd](../scripts/training/target_pool.gd) : six sphères réutilisées, `sync(engine,time_s)`, même géométrie que le moteur, matériau éclairé corail | Pool V2 dimensionné avant départ, identité slot/génération séparée du nœud, cibles non éclairées sans ombres, feedback/PV visuels et marqueur utile de rendu. |
| Arène et cosmétiques | [Arena.tscn](../scenes/training/Arena.tscn), [arena_presentation.gd](../scripts/presentation/arena_presentation.gd), viewmodel/arme/viseur/countdown dans [scripts/presentation](../scripts/presentation) | Nouvelle scène/arène V2 selon le thème ; cosmétiques alimentés par snapshots/événements et jamais par un second RNG mécanique. Les viewmodels existants sont dans un monde séparé. |
| Catalogue UI | [dashboard.gd](../scripts/ui/dashboard.gd), [training_browser.gd](../scripts/ui/training_browser.gd), [scenario_copy.gd](../scripts/ui/scenario_copy.gd) : catalogue legacy et signal `training_requested(scenario_id,duration_s)` | Composants V2 dédiés : signal programme/niveau, durée fixe 60 s, huit cartes, aucune variante cachée ni durée libre. La compatibilité historique ne réintroduit pas les cartes retirées dans le catalogue public. |
| Aperçu | [scenario_preview.gd](../scripts/ui/scenario_preview.gd), [exercise_preview_popup.gd](../scripts/ui/exercise_preview_popup.gd) : démo via moteur legacy, cible/bot illustratifs | L'aperçu V2 interroge le même modèle V2 que le jeu, sans score humain ni écritures ; l'HTML reste documentation et ne devient pas le runtime de l'application. |
| HUD, pause, résultats | [training_hud.gd](../scripts/ui/training_hud.gd), [training_pause.gd](../scripts/ui/training_pause.gd), [session_panel.gd](../scripts/ui/session_panel.gd) : chrono, scores legacy, repos et bilans progressifs | UI V2 affiche phase/niveau, préavis sans gel, mesures par phase, censures et qualité ; boutons reliés à de vrais états. Le contrôleur demeure propriétaire du gain, du score et des commits. |
| Conversion et calibration | [sensitivity_service.gd](../scripts/sensitivity/sensitivity_service.gd), [game_profile_service.gd](../scripts/sensitivity/game_profile_service.gd), [calibration_service.gd](../scripts/sensitivity/calibration_service.gd), [adaptive_sensitivity_service.gd](../scripts/sensitivity/adaptive_sensitivity_service.gd), [progressive_calibration_service.gd](../scripts/sensitivity/progressive_calibration_service.gd) | Réutiliser les conversions documentées via adaptateurs explicites ; ajouter CAL V2, ses tâches dédiées, plans/gains/epochs et calculateur. Conserver les services/protocoles publiés pour lecture et tests. |
| Routine | [training_routine_service.gd](../scripts/training/training_routine_service.gd) : M01/T10/S02 successifs, 45 ou 60 s par activité | Les phases internes d'EXxx sont contiguës ; elles ne sont pas les trois essais avec résultats/repos de cette routine. Les routines V2 assemblent des programmes complets autorisés. |
| Score et progression | [scoring_service.gd](../scripts/statistics/scoring_service.gd), [progress_service.gd](../scripts/statistics/progress_service.gd), [performance_insights.gd](../scripts/statistics/performance_insights.gd), [progress_board.gd](../scripts/ui/progress_board.gd), [score_chart.gd](../scripts/ui/score_chart.gd) | Ajouter un calculateur et validateur V2, clés par programme/niveau/phase et conditions ; le lecteur historique route vers `ScoringService` uniquement pour ses schémas legacy. Ne pas lui faire accepter artificiellement les rapports V2. |
| Stockage | [local_store.gd](../scripts/persistence/local_store.gd), [calibration_revision_archive.gd](../scripts/persistence/calibration_revision_archive.gd) : JSON schéma 1, sessions immuables, backups, checkpoints séparés, archives octet pour octet, exports CSV/JSON | Stockage V2 sous un sous-espace nouveau de la même racine utilisateur ; adaptateur de lecture legacy, commits rapport puis checkpoint, plan/manifeste/traces immuables, restauration du gain après crash. Ne pas détourner `save_session()`/`read_json()` legacy. |
| Distribution et validation | [export_presets.cfg](../export_presets.cfg), [tools](../tools), [TEST_PLAN.md](TEST_PLAN.md) : export Windows/PCK, wrappers versionnés, tests et captures | Vérifier que `MainV2`, ressources runtime, polices/notices et assets locaux entrent dans le pack ; conservation des tests 0.9 puis nouvelles preuves V2. Import, export et lancement Windows restent trois résultats distincts. |

### Préservation de l'autorité et séparation des espaces

Au contrôle final des chemins, les archives `docs/reference/v2/`, les fontes `assets/fonts/v2/` et des fichiers de travail `scripts/v2/` sont présents grâce aux travaux parallèles. Les signatures suivantes ont été observées ; leur présence ne constitue pas une revue complète du portage ni un résultat de test. En particulier, un fichier de service CAL en construction n'est pas un parcours CAL natif intégré.

| Espace / source nouveau | Raccordement concret et propriétaire |
|---|---|
| [v2_canonical.gd](../scripts/v2/v2_canonical.gd), classe `V2Canonical` | Parent : `encode()`, `semantic_sha256()` et représentations de gain binary64 ; consommés par registre, plans, rapports et persistance V2. |
| [v2_random.gd](../scripts/v2/v2_random.gd), classe `V2Random` | Parent : xorshift, `stream_seed()/public_seed()`, shuffle et tirages bornés ; aucun accès direct depuis les widgets. |
| [v2_geometry.gd](../scripts/v2/v2_geometry.gd), classe `V2Geometry` | Parent : `direction_deg()`, hitscan scalaire, séparation, frustum et placements ; conversion vers le rendu à la frontière de présentation. |
| [v2_motion.gd](../scripts/v2/v2_motion.gd), classe `V2Motion` | Portage parallèle : `compile_reactive()/build()/sample()/velocity_bound_deg_s()` ; moteur/aperçu/CAL partagent cette autorité. Parité complète à établir. |
| [v2_calibration_service.gd](../scripts/v2/v2_calibration_service.gd), classe `V2CalibrationService` | Portage parallèle : protocole, gains/grille et decks en construction ; orchestration/validation/décision/transaction devront être raccordées au contrôleur, sans modifier les anciens services. |
| `scripts/v2/` : moteur, contrôleur, score, stockage et registre à compléter | Parent : espace de classes V2 distinct ; dispatch explicite des anciens formats vers les services legacy. Le choix final de filenames appartient à ce propriétaire. |
| `MainV2` et nouveaux composants UI/scènes | Cible d'intégration séparée de `scenes/app/Main.tscn` ; fichiers UI V2 disjoints à affecter à l'agent UI, avec frontières d'API définies par le parent. |
| `res://content/v2/` et `assets/fonts/v2/` | Destination runtime des JSON nécessaires et fontes/notices ; les chemins de catalogue/protocole du service CAL pointent déjà vers `content/v2`. Les archives documentaires restent source de référence. |

Le preset actuel exclut `docs/*`, `tests/*` et `tools/*` de l'export : une lecture runtime directe de `docs/reference/v2/donnees/` ne suffit donc pas à livrer les données. Préparer des copies runtime contrôlées dans `content/v2` (catalogue, protocole, constantes et thème nécessaires), conserver leurs révisions/hashes et vérifier les références effectives du pack. Cette préparation est une dépendance d'intégration, pas une modification réalisée par le worker documentaire.

`main.gd` raccorde les signaux dans `_ready()`, applique le profil dans `apply_profile()`, prépare via `prepare_training()`, démarre via `begin_training()`, finalise et sauvegarde via `finish_training()`, puis actualise l'historique/export. Ce sont les responsabilités à reproduire dans le contrôleur V2, avec des types et états V2, plutôt que des fonctions à modifier en place. Le changement de `run/main_scene` appartient à l'intégration validée du parent.

Le parent définit les interfaces mécaniques ; l'UI séparée consomme des définitions validées, snapshots de séance, rapports et états CAL. Elle émet les intentions sélection/lancement/pause/reprise/export/application/annulation. Elle ne génère pas de trajectoire, n'écrit pas directement un checkpoint, ne recalcule pas un score depuis du texte affiché et ne change pas la sensibilité dans son callback de widget. Les nouveaux fichiers UI/scènes/assets peuvent ainsi être affectés sans chevauchement avec le moteur/contrôleur/persistance.

Le registre V2 et ses identifiants EX/CAL restent distincts de `ScenarioCatalog`. Les rapports portent format, mécanique, score, rendu et protocole séparément. Un nom contenant « V2 » ne constitue pas à lui seul une version de schéma. Le code 0.9 a déjà un **score version 2** ; celui-ci n'est ni `click_v3`, ni le catalogue V2, ni le protocole CAL V2.

## 3. Quantités et carte de migration du catalogue

### Catalogue legacy réellement présent

Les 18 IDs chargés par `ScenarioCatalog.DEFINITIONS` sont : **C01, C02, C03, C04, C05, C07, D01, D02, T01, T02, T03, T04, T05, T09, S01, S02, M01, T10**. Cela donne neuf clics, sept suivis et deux switching ; les switching 0.9 sont encore des clics one-shot, donc onze activités clic/transitions au sens de la décision D30.

Les fichiers `.tres` sont **13 r3, deux r4 (D02/S02) et trois r5 (C03/M01/T10)**. Le catalogue construit ensuite **18 r6 temporelles** ; les pratiques 0.9 réemploient onze de ces r6 et ajoutent **sept r7 de suivi**. Les trois couches adressables par `resolve()` représentent donc **43 définitions mécaniques distinctes : 18 + 18 + 7**, et non 43 cartes publiques. La calibration progressive neuve utilise le protocole 6 ; les protocoles 4/5 choisissent leurs définitions d'origine via `protocol_definition_for()`.

S'ajoutent, hors du registre de pratique, **cinq définitions r2** dans `CalibrationRevisionArchive` et **cinq tables de paramètres r1** dans `LocalStore.LEGACY_CALIBRATION_PARAMETERS`, pour reconnaître les checkpoints historiques. Leur présence n'est pas un nouveau catalogue public ni une preuve du nombre de séances utilisateur. Aucun historique personnel réel n'a été recensé ici ; il ne faut pas annoncer un nombre de fichiers migrés.

### Catalogue V2 vérifié dans les données

Extraction indépendante du bloc JSON `atlas-data` de l'HTML initial, comparée au [catalogue livré](reference/v2/donnees/catalogue.v2.json) : **24 configurations**, **54 définitions de phase**, et les définitions de phases des **24 configurations sont exactement égales** à celles du JSON. L'Atlas ne fournit pas 54 cartes : huit programmes × trois niveaux, avec **18 phases pour un niveau**, puis 18 × trois = 54. CAL utilise des tâches dédiées hors de ces 24 configurations.

Chaque programme dure 60 s actives. Les niveaux `novice/standard/advanced` sont résolus avant départ, sans multiplicateur de difficulté implicite ou adaptation à la réussite.

| Carte V2 et références legacy | Phases exactes du programme | Cibles et diamètres complets N / S / A observés | Différence à implémenter |
|---|---|---|---|
| EX01 Acquisition ← C01/C02/C04/M01 | `micro` [0,20), `general` [20,40), `amplitude` [40,60) | Une cible ; micro 1,8 / 1,2 / 0,8° ; général/amplitude 3,2 / 2,4 / 1,6° | Annules sphériques, transitions et sac équilibré ; trois scores C séparés, aucun shrink universel. |
| EX02 Multicibles ← C03/C05 | `grid` [0,20), `precision` [20,60) | Trois cibles sur neuf nœuds, 4,8 / 4,0 / 3,2° ; puis six cibles, 1,8 / 1,2 / 0,8° | La C03 r5 auditable est un scatter six cibles, pas cette grille. Remplacement d'un seul slot avec séparation de toutes les vivantes ; deux scores C. |
| EX03 Temporisées ← D01 | `fixed_window` [0,30), `shrinking_window` [30,60) | Une cible au plus ; départ 3,2 / 2,4 / 1,8°, fin de shrink 1,92 / 1,44 / 1,08° | Dix opportunités de 3 s par phase ; onset 0,65–1,15 s dans chaque slot ; fenêtres 1,4 / 1,1 / 0,8 s. Hit/expiration n'avancent pas le calendrier ; deux scores P. |
| EX04 Clic mobile ← D02 | `linear` [0,20), `evasive` [20,40), `arcs` [40,60) | Quatre cibles ; 2,8 / 2,0 / 1,4° dans les trois phases | Réflexion instantanée, réactif compilé, arcs en chambres ; remplacement du seul slot touché ; trois scores C. |
| EX05 Suivi fluide ← T01/T02/T04 | `horizontal` [0,20), `vertical` [20,40), `ellipse` [40,60) | Une cible ; 3,6 / 2,6 / 1,8° | Sinusoïdes et ellipse à vitesse angulaire normalisée ; pas d'expiration ou shrink d'âge ; trois scores T et indice de contact. |
| EX06 Suivi réactif ← T05 | `reactive` [0,60) | Une cible ; 3,4 / 2,6 / 1,8° | `reactive_axis` non périodique, préemption de bord et réarmement ; diagnostic spontané distinct du bord. Une ancienne alternance r7 ne devient pas le nouveau modèle. |
| EX07 Contrôle 3D ← T10 | `depth` [0,60) | Une cible ; diamètre de référence à 4 m 3,6 / 2,6 / 1,8° | `depth_sines`, trois phases initiales indépendantes, distance 3–5 m, rayon physique constant, pas de compensation écran/shrink d'âge ; un score T. |
| EX08 Transitions ← S01/S02 | `static` [0,20), `mobile` [20,40), `evasive` [40,60) | Quatre cibles ; 3,4 / 2,6 / 1,8° ; PV 30 / 40 / 50, identiques entre les trois phases d'un niveau | Maintien 100 PV/s, dégâts partiels persistants, destruction puis remplacement ; trois scores S et travail utile sur 60 s. |

Les trois entrées restantes sont des **retraits explicites** : C07 (clic vertical spécialisé), T03 (suivi diagonal) et T09 (Far Small). Elles restent lisibles dans l'historique ; aucune équivalence exacte ni aucun transfert de record vers EX01/EX05/EX06 n'est déclaré. Les huit regroupements ci-dessus couvrent les quinze autres IDs, pas une conversion automatique de leurs scores.

### EX08 mobile : confirmation d'une valeur de l'Atlas

Les trois niveaux ont bien `motion.kind = "linear_reflect"` **avec** `reflection = "symmetric_cubic_smoothstep_velocity"`. Le nom du kind ne signifie donc pas un demi-tour instantané : EX04 linéaire utilise, lui, `instantaneous_velocity_sign_change`. La spécification §6.4, le JSON, l'Atlas et `Motion.sample()` concordent sur cette distinction ; aucune contradiction n'a été constatée sur ce point.

Pour EX08 mobile, les valeurs vérifiées sont : vitesses yaw **6 / 9 / 14°/s**, durée de virage **0,24 s**, retraits de bord **0,45 / 0,675 / 1,05°**, périodes **14,8466666667 / 9,9577777778 / 6,4657142857 s**, accélérations maximales yaw **75 / 112,5 / 175°/s²**. Bornes yaw ±22°, couloirs pitch −9/−3/3/9°. Porter ensemble le discriminant `reflection`, l'état initial de cycle, les segments et les contraintes de respawn ; remplacer ce modèle par le sinus legacy serait une divergence réelle.

## 4. Changements mécaniques et compatibilité

### 4.1 Géométrie, taille et signes

L'œil reste à `(0,1.6,0)` m et le joueur immobile. V2 impose la direction `(cos(pitch)sin(yaw), sin(pitch), -cos(pitch)cos(yaw))` : **yaw positif vers la droite**. Aujourd'hui `AimCamera` soustrait `dx × gain` et `AimGeometry.direction()` emploie un X négatif pour yaw positif. Ces deux choix legacy sont cohérents entre eux. **Ne changer ni la géométrie ni l'input des historiques** : le nouveau modèle V2 doit convertir explicitement sa pose vers la rotation Godot de rendu et tester les quatre directions. Un adaptateur de lecture peut identifier la convention historique ; il ne réécrit pas les traces sauvegardées.

Le diamètre angulaire est complet ; à distance `d`, le rayon est `d × sin(D/2)`, pas `d × tan(D/2)`. V2 emploie généralement 4 m ; EX07 conserve `size.world_radius_m` pendant la variation 3–5 m. Les `.tres` legacy ont différentes distances, et T10 r7 combine perspective et shrink de cycle : ce n'est pas EX07.

Le FOV de référence V2 est **103° horizontal à 16:9**, soit **70,5328004329° vertical dans le catalogue**. Le thème stocke la conversion avec davantage de décimales. La 0.9 utilise le FOV vertical du profil, défaut 75°. Ne pas reporter 103 dans un champ vertical ni réimporter la valeur visible arrondie comme autorité. La projection/contour tangents, le frustum de toute la sphère, la garde au sol 0,05 m et les plans near/far doivent être testés avec le viewport réel.

### 4.2 Placement et consommation du hasard

Le RNG Godot seedé et les réserves legacy ne reproduisent pas automatiquement `xorshift32_v1`. Les sous-flux publics dérivent d'un tuple compact de **six chaînes ASCII** ; CAL emploie **huit chaînes** ; le compilateur de mouvement dérive ensuite ses domaines propres. Ces dérivations restent séparées de CANON. Le seed128 de séance reste une chaîne hexadécimale de 32 caractères ; les anciens formats de seed restent interprétés tels qu'ils ont été écrits.

Les placements V2 emploient l'angle solide, les annules et les contraintes avec toutes les cibles vivantes. EX01 général utilise un sac de 12 transitions, quatre de chaque bande, Fisher–Yates non biaisé, rechargé vide seulement. Après 128 candidats, un treillis déterministe choisi par hash s'applique selon le modèle ; aucun relâchement silencieux des contraintes. Une impossibilité produit `spawn_constraint_failure`. Un fallback est observable et invalide CAL selon son protocole.

Les fonctions de référence désormais disponibles sont `exercise_seed()`, `static_layout()`, `rng_child()`, `compile_reactive()`, `sample_reactive()`, `Motion.__init__()/sample()` et `Ellipse`, dans [mouvements_reference.py](reference/v2/outils/mouvements_reference.py), avec le PRNG dans [geometrie_reference.py](reference/v2/outils/geometrie_reference.py). Le constructeur consomme déjà des tirages d'initialisation communs avant certains tirages propres au modèle ; supprimer un tirage jugé inutile déplacerait la suite. L'ordre exact doit être porté depuis le source et comparé aux états/fixtures, **pas reconstruit de mémoire ni déduit seulement du kind**. `sample(t)` doit être pur et ne faire aucun tirage par frame ; aucun sound/feedback ne consomme le sous-flux mécanique.

Les trajectoires V2 ne sont pas des renommages de `horizontal/circle/strafe/waypoints` : ellipse métrique sphérique (table de 4096 cellules), rebonds d'arcs impulsifs autorisés, réactif avec préemption conservant position/vitesse et profondeur à rayon constant ont des contrats différents. Ne pas exiger une accélération finie des rebonds explicitement instantanés ; ne pas généraliser cette exception aux rampes réactives ou à EX08 mobile.

### 4.3 Cycle de vie et phases

Le legacy r6 rétrécit les 18 activités et renouvelle ses suivis autour de dix secondes nominales, avec durées ±15 %. La r7 module en plus la vitesse des sept suivis. V2 retire ce cycle global : clics libres jusqu'au hit, suivi persistant, EX03 seule fenêtre/shrink annoncé, EX07 perspective, EX08 jusqu'à destruction par contact. La liste des variantes supprimées du cahier reste absente du parcours public ; aucune adaptation à la réussite.

Identité obligatoire : séance, phase, slot, génération et target_id. Un nœud du pool ne constitue pas une cible persistante. Une instance a une seule issue terminale : hit/kill, expiration programmée ou censure selon sa mécanique. Un hit/kill remplace uniquement le slot concerné ; les voisines conservent position, trajectoire et dégâts. EX03 attend le prochain créneau après résolution : sa génération est l'indice d'opportunité, indépendant des tirs.

Les changements de phase ne passent pas par un écran résultat ou repos. À la frontière : intégrer l'ancien contact, créditer une destruction exactement au seuil, conserver les partials switching, censurer les restantes, fermer le rapport, créer la nouvelle phase, puis appliquer les fronts à cette nouvelle phase sous réserve de première image. Aucun spawn supplémentaire de l'ancienne phase. À 60 s, finaliser sans nouveau point/spawn. Le préavis HUD deux secondes avant ne gèle ni chrono ni cibles et ne recale pas la caméra.

Un clic exactement à la deadline EX03 est tardif : `[onset,deadline)`. Un kill par intégrale exactement à 20/40/60 s appartient encore à l'ancienne phase. Ces deux cas ont des ordres distincts et doivent rester couverts séparément.

### 4.4 Entrée, état et interruption

La fidélité `screen_relative`, absence de delta et pitch ±89° sont déjà présentes. V2 ajoute `received_pose_hold_v1`, temps monotones entiers, séquence stable, événements de bouton et snapshots immuables. Deux événements `motion → press → motion` au même timestamp doivent employer la pose intermédiaire pour le tir. Le clic reste un front unique sans repeat ; le maintien n'inflige des dégâts que dans la mécanique autorisée.

L'accumulation V2 est désactivée, contrairement au défaut legacy configurable true. Cela n'autorise pas à prétendre disposer de paquets HID/timestamps matériels ni à effacer les deltas lors d'une frame lente. Les types vectoriels de rendu peuvent avoir une précision différente des scalaires GDScript ; les calculs d'autorité binary64 restent séparés de leur conversion visuelle.

La pause de pratique conserve les positions/temps actifs, libère capture/bouton, puis reprend volontairement avec décompte 3 s et armement neuf. La 0.9 reprend directement son `paused_from` : le décompte de reprise et la comparabilité des pauses sont à ajouter dans V2. Le maintien EX08 exige relâchement puis pression au début/reprise ; il continue aux frontières de phase sans relâchement imposé. Focus perdu n'entraîne aucune reprise automatique.

Une interruption d'une tâche notée CAL invalide l'epoch de journée entière ; ce n'est pas la pause reprenable de pratique. Les paramètres figés et conditions observées doivent détecter perte de capture, overflow, discontinuité d'horloge et changements de gain/résolution/profil technique. Une performance faible techniquement valide reste une observation humaine ; absence de mouvement n'est pas à elle seule une panne matérielle.

### 4.5 Apparition, rendu et contact

`TargetPool.sync()` positionne/rend visibles des meshes ; il ne produit pas `first_rendered_frame`, de journal de générations préparées/utiles ou de preuve du viewport/panneau. V2 doit distinguer onset logique, premier rendu moteur utile, proxy temporel, deadline et résolution. Une remplaçante jamais rendue ne reçoit aucun hit ni dégât ; deux clics entre deux images ne doivent pas tuer successivement des générations invisibles.

Le dénominateur reste la durée planifiée entière : 20 s par phase EX05, 60 s EX06/EX07, 24 s par tâche CAL. L'acquisition initiale, le regard hors zone et le culling dû au joueur n'en retirent aucun temps. Le render gate protège le numérateur, sans retimer onset/deadline/exposition. Une défaillance technique peut invalider la mesure, sans devenir une erreur humaine ou raccourcir la fenêtre.

Le [contrat runtime](reference/v2/donnees/runtime.contract.json) fixe :

- Autorité scalaire IEEE754 binary64, epsilon angulaire `1e-9°` ; discriminant `64 × epsilon_binary64 × max(1 m²,b²,abs(c_term),r²)` ; tie d'intersection `1e-9 m`, départagé par identité stable. La tolérance legacy de `ray_sphere_distance()` ne doit pas être substituée à ces valeurs.
- Erreur de silhouette et de projection de point **0,5 px**, dans le viewport effectivement rendu. Ce sont deux contrôles visuels distincts, pas une marge d'agrandissement du collider.
- Tranche initiale de contact au plus **1/240 s**, subdivision selon une borne de vitesse valide sur l'intervalle, bornes inférieure/supérieure et estimation à leur milieu. Le midpoint fixe 240 Hz legacy n'apporte pas cette garantie.
- Largeur maximale d'encadrement **0,0005 de la durée planifiée**, donc **12 ms pour 24 s CAL** ; recherche du premier kill à **0,1 ms**. Inclure la variation de rayon apparent et les frontières d'entrée/bouton/mouvement/rendu/cible.
- Budgets **8192 évaluations de g par tranche initiale**, **4 000 000 par phase**, subdivision et recherche de kill incluses. Au dépassement : `unresolved_integration_error`, CAL refusé et pratique non comparable ; aucun score de secours classable.

`frame_post_draw` demeure un proxy logiciel. **Aucune tolérance de scanout physique ni mesure de latence matérielle n'est fournie par le kit** ; il ne faut pas transformer les 0,5 px, 12 ms ou 0,1 ms ci-dessus en certification du moniteur, de la souris ou de l'affichage humain.

### 4.6 PV et score

S01/S02 sont actuellement des one-shot dans `ScenarioEngine.shoot()`, sans PV. V2 EX08 impose quatre vivantes, maintien 100 PV/s, PV 30/40/50 selon niveau, aucun regen, dégâts partiels persistants jusqu'au kill/clôture. L'idéal de contact par kill est 0,3/0,4/0,5 s. Le surplus sur la cible détruite n'est pas transféré à sa remplaçante avant son premier rendu. À la clôture, toutes les fractions de dégâts des vivantes comptent une fois.

| Famille V2 | Score non arrondi de phase | Règle de comparaison |
|---|---|---|
| C `click_v3` | `1000 × (H/T) × H/max(S,1)` | Précision à l'exposant 1 ; pas d'expiration universelle ni cadence `reference_hits_s`. |
| P `opportunities_v2` | `1000 × (H/O) × H/max(S,1)` | Dix opportunités par phase complète EX03, calendrier indépendant de l'action. |
| T `contact_v2` | `1000 × C/E` | Exposition planifiée entière, contact admissible et bornes conservées. |
| S `switch_work_v3` | `1000 × (K + somme des fractions de dégâts vivantes)/T` | Travail utile complet et partiel, pas hits/s one-shot. |

La 0.9 utilise au contraire une utilité clic `hits_per_s × accuracy²`, normalisée par `reference_hits_s`, ou sa variante expirations `hits/(shots+expired)` au carré ; le suivi conserve son score 1. Garder ces formules et leurs tolérances de relecture JSON pour les anciens fichiers. Le calculateur V2 garde les valeurs non arrondies comme autorité et produit séparément l'affichage.

EX01/02/03/04 n'ont pas de score global mêlant les phases. EX05 peut agréger contact/exposition ; EX08 peut agréger le travail utile sur 60 s. Les autres totaux sont descriptifs. Une phase incomplète/invalide n'est pas classable. Le `rank_key_suffix` doit être complété par gain réel, DPI/source, FOV, viewport, rendu/driver, versions et hashes ; aucun record legacy ne traverse ce changement de tâche.

## 5. Rendu natif et interface à réaliser

Les dernières décisions D23/D29 et `Arena.tscn` montrent une arène claire éclairée, cible corail per-pixel, une source directionnelle **avec ombres**, mur à z = −12 m, MSAA 4× et décor périphérique. Le premier choix « pas d'ombres dynamiques » de D02 ne décrit plus cette 0.9.

V2 conserve Godot/Compatibility mais change le profil visuel : pièce sombre fixe, mur de référence z = −18 m, sol 80 × 80 m, cibles unshaded turquoise `#42D9CB` ou alternative `#FFB454`, sans ombres de cible, bloom, blur, secousse, reflets d'environnement ni trails mesurés. Les ressources de [interface.theme.json](reference/v2/donnees/interface.theme.json) font autorité pour palette, polices, dimensions et layout. **Ombres présentes en 0.9 contre cibles sans ombres en V2 est une différence confirmée**, pas un état moteur déjà corrigé.

Le profil initial proposé est `reference_gl_v2`, Compatibility/OpenGL3, rendu 100 %, MSAA 4× ; le rapport enregistre renderer **et driver réellement démarrés**. Le fallback ne doit pas cacher une différence d'image dans CAL. Le projet ne change pas opportunément renderer/résolution/MSAA entre candidats. Dépendances Python/Node, Atlas HTML et outils graphiques restent côté développement ; le joueur reçoit l'application native et ses ressources locales.

Périmètre concret de l'agent UI séparé :

1. Catalogue EX01–EX08, niveau avant départ, aperçu et durée fixe ; pas de 18 cartes legacy ni valeurs de paramètres factices.
2. Préparation/chargement/countdown, HUD et préavis, pause/reprise, commandes qui respectent focus/capture/armement.
3. Résultats par phase avec vraies unités, statut de complétude/qualité et records du nouveau contexte ; historique ancien identifié comme tel.
4. Écrans CAL de préflight, parcours express, planning de deux jours, maintien du gain, repos, statuts et application/undo ; toutes les actions sont celles du contrôleur.
5. Navigation clavier, textes de statut en plus des couleurs, tailles/layout adaptatifs et profil visuel figé pendant CAL ; polices et licences embarquées.
6. Captures issues du runtime réel aux résolutions prévues ; les PNG/SVG du kit guident la composition mais leurs valeurs d'exemple ne deviennent pas des résultats joueur.

L'agent UI peut avancer sur les composants et états explicites pendant le portage mécanique. Une carte n'est cependant activée/publicable qu'une fois son programme, ses trois niveaux et ses preuves concordants. L'aperçu et le gameplay doivent partager les définitions/modèles V2 et la caméra correcte ; un dessin ressemblant à l'Atlas ne valide pas une vitesse, un rendu utile ou un clic.

## 6. CAL V2 : protocole disponible, intégration restante

### Contrat désormais fourni

Le protocole [calibration_v2_protocol.json](reference/v2/donnees/calibration_v2_protocol.json) est **`sustained_blocks_v2`**, révision `2026-10-12-v2.0`. Il remplace le parcours public progressif 0.9 de cinq activités × cinq sensibilités, 25 essais de 45/60 s et utilités par bloc. Les anciens services sont conservés ; leur conclusion n'est pas convertie en résultat du protocole soutenu.

La grille multiplicative cm/360 emploie un ratio par défaut 1,25 (exploration large 1,5), bornes techniques 5–150 cm, départ/gain effectif exact conservé et representabilité résolue avant mesure. Pas de candidats effectifs dupliqués, interpolation parabolique ou recommandation hors grille. Les snapshots conservent bits binary64 et texte decimal17 du gain réellement appliqué, source DPI, conditions et objectif figé. Objectifs : polyvalent, acquisition, tracking ; leurs poids sont livrés et ne sont pas ajustés aux résultats.

| Tâche dédiée | Contrat principal et utilité |
|---|---|
| `CAL_CLICK_R2` | 24 s, 16 slots de 1,5 s, onset 100 000–250 000 µs inclusifs, fenêtre 1,2 s ; premier front résout l'opportunité, prématuré ou miss = zéro. Utilité moyenne `(1 − tau/1,20)` seulement si ce premier tir réussit. Les pressions supplémentaires/tardives restent des diagnostics. |
| `CAL_SMOOTH_R2` | 24 s, sinus yaw d'amplitude 14°, paramètres par niveau ; contact sans bouton, utilité contact/24, acquisition initiale incluse. |
| `CAL_REACTIVE_R2` | 24 s, même `reactive_axis` et même version de compilateur qu'EX06 ; les hashes du modèle par niveau sont livrés. Contact/24 ; aucune seconde interprétation du mouvement pour CAL. |
| `CAL_SWITCH_R2` | 24 s, 12 slots de 2 s, fenêtre 1,7 s, trois positions statiques/priorités équilibrées ; PV 15/20/30 à 100 PV/s. Maintien entre slots autorisé ; pas de règle de clic prématuré copiée depuis CLICK. Utilité moyenne `(1,70 − tau)/(1,70 − PV/100)` bornée 0–1 seulement si destruction. |

Chaque période maintient **le même gain pendant 192 s (3 min 12)** : 60 s d'acclimatation, puis quatre décomptes de 3 s, quatre tâches de 24 s et quatre récupérations de 6 s. L'express est une permutation seedée de deux/trois gains, avec repos inter-périodes de 30 s. Pour trois gains : 696 s avec préflight ; confirmation : quatre périodes par jour, repos de 60 s, **1008 s par jour**, **2016 s sur deux jours**. L'ensemble d'exemple express trois gains + confirmation est **2712 s minimum programmé**, hors attentes/reprises.

Confirmation A/B : jour 1 ABBA ou BAAB figé avant les scores, jour 2 ordre inverse. Ordre des tâches jour 1 CLICK/SMOOTH/SWITCH/REACTIVE, inverse jour 2. Les jours ont des dates locales distinctes, départs espacés de 12–168 h ; la première confirmation attend au moins 12 h après l'express. Le candidat/gain n'entre pas dans les seeds des défis appariés ; les défis de confirmation sont nouveaux et l'express n'est pas ajouté à la confirmation.

L'unité d'observation est le composite de journée issu de deux contrastes appariés, pas les frames/cibles/tâches supposées indépendantes. La conclusion est descriptive, sans intervalle de confiance inventé, probabilité d'optimum ou affirmation d'équivalence statistique/adaptation longue.

### Validité, statuts et transaction

La priorité du calculateur fourni est : **`unstable_conditions`, `incomplete`, `exploratory_only`, `repeated_regression`, `repeated_improvement`, `mixed_tradeoff`, `close_observed`, `undetermined`**. Porter `explore()` et `compare()` de [calibration_v2_reference.py](reference/v2/outils/calibration_v2_reference.py), ses seuils non arrondis, gardes brutes CLICK/SWITCH et cas plancher/plafond. Les huit statuts sont couverts par les fixtures livrées ; ils ne sont pas encore des résultats du moteur Godot.

Les constantes techniques CAL sont explicites : FPS moyen ≥55, p99 ≤25 ms, maximum ≤100 ms, écart relatif médian FPS entre appariés ≤0,10, quantile nearest-rank. Une utilité moyenne ≤0,10 ou ≥0,95 rend la tâche non informative. Ni fatigue déclarée seule ni performance médiocre valide ne permettent de sélectionner un meilleur essai.

L'epoch accepté est le **premier techniquement valide et complet**, jamais le meilleur score. Pause notée, perte de focus/capture ou incident invalidant entraîne une nouvelle epoch de journée entière, nouveaux défis partagés, au plus deux tentatives planifiées par rôle. Les cellules/paires seules ne sont pas rejouées pour améliorer une conclusion. Attentes réelles, jours/rôles et causes restent enregistrés.

Le plan doit être sauvegardé avant mesure avec nouvelles identités, conditions réelles, gains actualisés et ressources chargées. Le plan d'exemple fourni annonce `is_example=true`, `contains_real_player_results=false`, **`engine_executable=false`** ; son rapport indique **`runtime_ready=false`**, avec 44 cellules notées et 52 decks. Le rendre exécutable exige l'intégration réelle des manifestes, la validation input/rendu et le remplacement du snapshot illustratif ; enlever un drapeau ne suffit pas.

Porter notamment `candidate_grid()`, `verify_gains()`, `make_deck()`, `validate_plan()`, `explore()` et `compare()` avec leurs invariants. Les mutations négatives recalculées avec un hash valable montrent qu'une empreinte correcte ne valide ni gain/candidat, ni durée, ni ordre/rest, ni snapshot. Le schéma du catalogue n'est pas un schéma CAL universel : les contrôles sémantiques CAL sont dans ce calculateur et ses fixtures.

Le gain temporaire reste constant dans la période et les repos ; deux périodes adjacentes au même gain ne rétablissent pas la baseline. Fin/abandon/exception/redémarrage restaurent le profil initial. L'application du résultat est volontaire, sauvegardée transactionnellement et annulable ; par défaut, hors amélioration répétée, conserver le réglage initial. L'UI n'écrit jamais le gain temporaire dans le profil durable en cours de comparaison.

## 7. Sources : absences initiales levées et dépendances granulaires

Avec les seules deux pièces jointes initiales, l'Atlas permettait l'inventaire public mais ne livrait pas tous les contrats de portage : protocole CAL séparé, schéma fermé, ordre complet des tirages de générateur, CANON/fixtures et constantes runtime. **Le ZIP lève ces absences de source.** Le tableau suivant indique les fichiers présents à porter, et les dépendances restant à prouver ; il ne constitue pas une demande de renvoi du kit.

| Source archivée à utiliser | Ce qu'elle débloque | Dépendance native / réception restante |
|---|---|---|
| [catalogue.v2.json](reference/v2/donnees/catalogue.v2.json) + [catalogue.schema.json](reference/v2/schemas/catalogue.schema.json) | 24 configurations/54 phases, structure et discriminants | Registre GDScript strict, validation sémantique, chargement immutable avant départ ; [valider_catalogue.py](reference/v2/outils/valider_catalogue.py) sert de référence, pas de dépendance du joueur. |
| [runtime.contract.json](reference/v2/donnees/runtime.contract.json) | Tolérances de hitscan/projection, render gate et budgets contact | Implémentation moteur et preuves R01–R10 ; aucune constante de scanout physique à inventer. |
| [geometrie_reference.py](reference/v2/outils/geometrie_reference.py) | Directions, sphère/projection, gain et xorshift32/sous-seeds | Parité binary64/scalaires, signe souris V2, frustum et comparaison des contours réels. |
| [mouvements_reference.py](reference/v2/outils/mouvements_reference.py) + [atlas.etats.json](reference/v2/donnees/atlas.etats.json) | Générateurs, consommation RNG et états/trajectoires compilés | Portage fidèle des modèles et spawners conditionnés aux vivantes ; l'illustration initiale ne teste pas toute suite future de hits. |
| [empreintes_reference.py](reference/v2/outils/empreintes_reference.py) + [empreintes.fixtures.json](reference/v2/donnees/empreintes.fixtures.json) | AIM-CANON-1 et vecteurs positifs | Portage de `encode()/semantic_sha256()/strict_loads()`, cas négatifs et règles d'exclusion explicites des objets autoempreintés. |
| [calibration_v2_protocol.json](reference/v2/donnees/calibration_v2_protocol.json) | Grille, tâches, ordre/jours, seuils, qualité et statuts | Service CAL native, préflight et profils/gains effectifs, pas de réemploi du score public. |
| [calibration_v2_plan_example.json](reference/v2/donnees/calibration_v2_plan_example.json) | Exemple de plan, decks et liens de stimuli résolus | Construction d'un plan réel, conditions réelles et commit préalable ; l'exemple n'est pas prêt à être joué. |
| [calibration_v2_comparison_examples.json](reference/v2/donnees/calibration_v2_comparison_examples.json) + [calibration_v2_plan_negative_fixtures.json](reference/v2/donnees/calibration_v2_plan_negative_fixtures.json) | Cas de décision et huit mutations de plan valablement rehashées | Parité native des statuts et refus sémantiques ; `validate_plan()` ne se remplace pas par comparaison du hash seul. |
| [calibration_v2_reference.py](reference/v2/outils/calibration_v2_reference.py) | Construction/vérification des gains/decks/plans, exploration/comparaison | CAL dans le moteur, gestion des journées/epochs et transactions/crash ; la simulation Python du bruit n'est pas une source de hasard runtime. |
| [interface.theme.json](reference/v2/donnees/interface.theme.json), [visuels](reference/v2/visuels), [fonts](reference/v2/assets/fonts) | Tokens natifs, planches/vues/UI, DejaVu et licence | Composants natifs réellement branchés, projection du gameplay, ressources/préchauffage et export complet. |
| [rapports](reference/v2/rapports), [SHA256SUMS.txt](reference/v2/SHA256SUMS.txt), [référence utilisateur](reference/v2/references/EXERCICES_ET_CALIBRATION.md) | Provenance et preuves déclarées du kit | Lecture des limites de chaque preuve ; conservation des octets source, nouveaux rapports moteur/Windows distincts. |

Le kit n'est pas censé livrer un jeu Godot terminé. Ne sont pas établis par sa fourniture : le code runtime intégré, les rapports du nouveau build natif, le comportement d'un exécutable Windows hors dépôt, les counts matériels/latence physique, l'écoute audio et une étude de joueurs. Ce sont des tâches de livraison/réception ; ils ne bloquent plus la définition des huit cartes et de CAL.

CANON concerne l'empreinte sémantique, distincte du SHA-256 des octets archivés : nombres binary64, −0 normalisé, chaînes UTF-8 exactes, clés triées par octets, longueurs U32 big-endian, booléens distincts des nombres. Refuser non-finis, doublons de clés et entiers hors ±(2^53−1) selon le contrat d'échange. Aucune normalisation Unicode implicite ni sérialisation JSON « assez précise » ne remplace les fixtures. Les noms/formats effectivement produits par la 0.9 restent inchangés.

## 8. Persistance, historique et export : intégration concrète

Le projet conserve le dossier utilisateur **`AIM_LOCAL`** et `LocalStore` utilise **`user://aim_local`** à l'intérieur. Préserver exactement cette racine, les préférences et les fichiers existants : `profile.json`, `sessions/`, `calibrations/`, `archives/`, `calibration_checkpoint.json`, `guided_calibration_checkpoint.json`, `progressive_calibration_checkpoint.json` et les exports. Les noms d'un nouvel espace V2 sous cette racine seront définis par le parent ; ils ne doivent pas entrer en collision avec ces fichiers.

Le lecteur historique reconnaît les formats réellement publiés, dont les protocoles 4/5/6 et les anciennes variantes conservées par les validateurs. Garder interprétation de gain/signe/FOV, difficulté, score, empreinte, arrondis, schéma 1 et archives brutes. Aucun ancien rapport ne reçoit rétroactivement `first_rendered_frame`, manifeste, borne de contact, PV, traces ou score V2 inventés. Des informations absentes sont déclarées absentes. Un fichier inconnu/incohérent est conservé, pas écrasé par un schéma supposé plus récent.

Le backend V2 doit accepter ses propres objets validés ; `LocalStore.read_json()` exige aujourd'hui `schema_version == 1`, et `save_session()` appelle `ScoringService.validate_result()`. Les forcer à accepter des plans EX/CAL casserait la séparation des formats. L'historique commun peut agréger des **présentations** de rapports après dispatch de schéma, mais les records et tendances demeurent dans leurs contextes exacts.

Le graphe V2 minimal relie définition → manifeste → conditions → rapports de phase → rapport de séance ; CAL ajoute protocole → plan → jour/rôle/epoch → cellules → checkpoint → décision. Conditions réelles incluent gain, provenance DPI, FOV, viewport/résolution, renderer/driver, OS/build, versions et profils de présentation figés. Journaux input et rendu ont une origine monotone commune ; date civile est une métadonnée séparée.

Écrire/relire/vérifier le temporaire dans le même répertoire, fermer les handles et publier avec identifiant de transaction. Finaliser le rapport de cellule avant d'annoncer la cellule dans le checkpoint ; reprise idempotente par ID, sans double compte. Conserver le checkpoint précédent valide, tester les pannes entre étapes, maintenir en mémoire un résultat non sauvegardé et empêcher une relance destructive. Un rename réussi n'est pas une garantie contre coupure matérielle sur Windows.

L'export V2 fournit rapport JSON et résumé lisible avec unités/limites, et optionnellement manifeste/traces. Le CSV legacy n'est ni réordonné ni réinterprété. Le pack Windows inclut tous les assets runtime, polices/notices et ressources référencées ; `MainV2` et son registre doivent fonctionner sans accès au checkout ni Python/Node. Le ZIP 0.9 existant ne constitue pas une livraison 1.0.0-V2.

## 9. Confirmations, divergences et actions

| Observation confrontée aux références | Statut | Action |
|---|---|---|
| App 0.9.0 et Godot 4.7.2 épinglé ; commit décrit dans le cahier différent du HEAD observé | Version confirmée par fichiers ; provenance de commit divergente | Conserver les deux provenances, enregistrer le commit/build réellement livré après intégration. |
| Deux attachments identiques aux fichiers du kit ; 24 configurations/54 phases concordantes dans Atlas/JSON | Confirmé par extraction/égalité de contenu | Porter les valeurs livrées, conserver les sources exactes ; ne pas demander à nouveau les fichiers désormais présents. |
| EX08 `linear_reflect` mobile avec reflection smoothstep | Confirmé, aucune contradiction observée | Utiliser le discriminant complet et les périodes/états initiaux ; ne pas signaler un faux défaut de source. |
| Docs d'étapes anciennes : 16 exercices, pas d'ombres ; code 0.9 : 18 entrées, lumière avec ombres | Décalage documentaire observé | Utiliser l'inventaire/version D28–D30, puis définir le nouveau profil visuel V2. |
| Yaw legacy positif-gauche / input négatif, V2 positif-droite | Changement confirmé de convention logique | Nouvelle géométrie/input V2 ; aucune modification des conventions/empreintes legacy. |
| FOV legacy 75° vertical et mur −12 m ; V2 103° horizontal à 16:9 et mur −18 m | Changement confirmé de conditions | Nouvelle scène/caméra/profile V2, clés séparées et mesures de projection. |
| Shrink/expiration universels et rythme r7 legacy ; persistantes/fenêtres spécifiques V2 | Incompatibilité mécanique confirmée | Types/états de cycle de vie distincts ; rejouer anciens protocoles sur anciennes définitions. |
| S01/S02 one-shot contre EX08 maintien/PV ; score précision² contre click_v3 précision¹ | Incompatibilité confirmée, pas un simple changement d'UI | Nouveau moteur/calculateur et records ; conserver anciennes formules et données. |
| `visible=true`/240 Hz midpoint ne fournissent ni render gate ni encadrement du contact | Fonctionnalités V2 manquantes dans le baseline | Lot 2 avant activation des programmes/PV/CAL ; porter les budgets runtime exacts. |
| Plan CAL d'exemple hashé et stimuli résolus mais runtime non prêt | Limite explicitement déclarée par le kit | Créer et sauvegarder un plan réel, porter le validateur sémantique et exécuter les fixtures natives. |
| Source complète fournie, mais scanout/hardware/Windows/humains non réceptionnés | Limites de preuve, pas absence de paramètres de catalogue | Achever les lots natifs ; réception séparée Windows et pilote, sans inventer précision ou dates de résultat. |

## 10. Lots et portes de passage — correspondance au chapitre 16

Les dépendances respectent le [chapitre 16](reference/v2/AIM_LOCAL_SPECIFICATIONS_V2.md#chapitre-16). Des composants UI peuvent se préparer en parallèle sur contrats stables ; leur activation mesurée dépend du cœur et du catalogue. Les étapes ne promettent aucune date machine/physique.

| Lot du cahier | Travail concret pour ce checkout | Prérequis et preuve avant passage | État de l'audit |
|---|---|---|---|
| 0 — Inventaire | Baseline/version, registre legacy et historique, capture, scènes, exports, carte d'extension ; préserver Main/Geom/Input historiques | Cet audit, sources disponibles, propriétaires disjoints et risques explicités | Inventaire documentaire réalisé ; aucune nouvelle preuve de fonctionnement 0.9. |
| 1 — Unités et données | Parent : registre/types V2, JSON strict/schéma/sémantique, CANON, xorshift/sous-flux, géométrie positive-droite et gains | Parité fixtures hash/gain/projection/PRNG et refus de mutations invalides ; ressources complètes avant start | Fondations et assets en préparation ; réception native non attestée ici. |
| 2 — Cœur de séance | Parent : horloge/états V2, input ordonné, bouton/capture, génération, hitscan, marqueurs utiles, intégration bornée et transactions de fin | Lot 1 ; R01–R10, événements auditables, budgets/tangence, render gate, pause/reprise et aucune double issue | À implémenter et valider ; aucune carte V2 jouable au baseline. |
| 3 — Catalogue complet | Parent : huit programmes/24 configurations/54 phases, modèles compilés, spawners avec vivantes, fenêtres EX03, PV EX08, score par phase | Lots 1–2 ; équivalence aux références et tests par niveau, frontières/remplacements, R11–R12 | Kit débloqué ; portage complet et preuves à réaliser. |
| 4 — Présentation | Agent UI disjoint : nouveaux composants/scènes, thème/polices, arène, silhouettes, navigation, aperçu partagé, HUD/résultats réels | API/snapshots du parent ; captures/projections ≤0,5 px et navigation aux résolutions prévues ; ni anciennes mécaniques sous carte EX ni faux scores | Prêt à être affecté sur nouveaux fichiers ; activation finale après cœur/catalogue. |
| 5 — CAL | Nouvelle grille/préflight/tâches, plans/decks/jours/epochs, gain soutenu, conditions, critères et huit statuts, UI/application/undo | Cœur/contact/mouvements/persistance et présentation stables ; huit statuts, huit mutations négatives, R13–R16, crash/restauration du gain | Source complète ; aucun parcours CAL V2 reçu au baseline. |
| 6 — Migration et export | Parent : adaptateur historique, espace V2, commits/reprise, export MainV2 et ressources, conformité locale | Conservation de formats/octets/protocoles et anciennes suites ; nouvelles pannes contrôlées ; lancement Windows hors dépôt sans outils développeur, réseau coupé | Intégration à faire ; disponibilité d'une machine native à réception reste à établir. |
| 7 — Pilote | Usages réels des niveaux/phases et parcours CAL ; documenter faisabilité, fatigue/attentes et limites | Build intégré reçu ; rapport humain, révision explicite des paramètres/hashes si nécessaire | Non exécuté ; aucune conclusion humaine ou scientifique revendiquée. |

La version `1.0.0-V2` est la cible après l'intégration validée ; garder une distinction entre version de build, état des gates et validation native/humaine. L'absence d'un essai Windows/humain ne doit pas devenir une fausse assertion « tout reçu », ni une impossibilité permanente de porter les paramètres désormais fournis.

## 11. Couverture des tests et preuves restant à obtenir

**Travail exécuté par cet audit :** lectures des sources, inventaire statique, vérification du HEAD/version déclarée, égalité octet pour octet cahier/Atlas entre attachments et kit, extraction des 24 configurations/54 phases et égalité des définitions Atlas/catalogue. Ce sont des contrôles documentaires/données, pas des essais moteur. Aucun import, export, suite Godot complète, lancement Windows ou pilote humain n'a été exécuté par ce worker. Aucun compte d'assertions réussies ou date de réception n'est inventé.

**Couverture legacy présente, examinée sans exécution :** [tools/test.sh](../tools/test.sh) lance 13 entrées de runner, dont [run_tests.gd](../tests/run_tests.gd), qui compose plusieurs suites. Elles couvrent math souris/lifecycle, UI, import de sensibilité, calibrations/blocs, archives/checkpoints, fidélité des seeds/pause, records, présentation et aperçus. Les entrées séparées comprennent [geometry_regression_tests.gd](../tests/geometry_regression_tests.gd), [adaptive_calibration_tests.gd](../tests/adaptive_calibration_tests.gd), [pattern_variation_tests.gd](../tests/pattern_variation_tests.gd), [storage_roundtrip_tests.gd](../tests/storage_roundtrip_tests.gd), [progressive_calibration_tests.gd](../tests/progressive_calibration_tests.gd), [exercise_070_tests.gd](../tests/exercise_070_tests.gd), [lifecycle_tests.gd](../tests/lifecycle_tests.gd), [tracking_rhythm_tests.gd](../tests/tracking_rhythm_tests.gd), [presentation_080_tests.gd](../tests/presentation_080_tests.gd) et [temporal_ui_tests.gd](../tests/temporal_ui_tests.gd). La présence de ces fichiers et les résultats anciens consignés dans `TEST_PLAN.md` ne prouvent pas leur succès après la migration. Les conserver et les rejouer sous responsabilité d'intégration.

**Preuves livrées par le kit :** rapports de structure/mouvements/Atlas/CAL et simulations de référence ; `calibration_v2_checks.json` annonce des fixtures et huit refus de plan, mais `runtime_ready=false`. Les exemples et les 140 000 comparaisons synthétiques décrites par le cahier ne sont ni des mesures joueur ni des tests de ce nouveau build. Les outils de référence peuvent générer/réécrire leurs rapports ; cet audit ne les a pas lancés sur les sources archivées.

**Tests natifs V2 encore à fournir :**

- Parité CANON, seeds/draws, gains réellement représentables, géométrie positive-droite, clipping et schéma/contraintes fermées ; aucune mutation des anciennes empreintes.
- R01–R10 : ordre motion/clic, mêmes traces et marqueurs aux FPS simulés, première image/deadline, dénominateur intact, kill frontière, gap brut 10 ms, tangence/budgets, clic/maintien et remplaçantes invisibles.
- R11–R12 : séquences arbitraires de remplacement avec toutes les vivantes et hasard cosmétique isolé ; chaque niveau/phase, EX03 calendrier et EX08 PV/partials sans double crédit.
- R13–R16 et CAL : qualité/conditions, faible performance conservée, prématuré CLICK, maintien SWITCH, huit décisions et huit mutations rehashées, plans réels, journées/epochs et restauration du gain après exceptions/crash.
- Écritures V2, rapport/checkpoint idempotents, pannes à chaque frontière de commit, données legacy intactes et export local ; UI réellement raccordée et silhouettes du viewport dans les tolérances.
- Import/build/export propres à l'intégration, ressources locales complètes, exécution native Windows hors checkout, essais physiques souris/focus/polling/latence, écoute audio et pilote humain. Les essais Linux/headless et les captures logicielles restent des preuves distinctes.

**Statut final de cet audit : inventaire et plan de migration documentés ; sources complètes disponibles ; aucune implémentation V2 jouable, CAL native ni réception Windows/humaine certifiée par ce document.**
