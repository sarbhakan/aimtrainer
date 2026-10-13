# AIM/LOCAL V2 — Exercices, exécution et calibration

**Révision documentaire : 12 octobre 2026. Version d’application : 1.0.0.**

Ce guide décrit les données V2 importées et les modules natifs présents dans le dépôt. Il accompagne le [cahier V2 original](reference/v2/AIM_LOCAL_SPECIFICATIONS_V2.md), conservé sans modification, et le [plan de réception](TEST_PLAN_V2.md). La [documentation 0.9](EXERCICES_ET_CALIBRATION.markdown) reste historique.

**Le point d’entrée public est le moteur V2 natif.** Les 81 empreintes du kit et les cinq imports originaux sont conservés. La recette couvre séparément catalogue, mouvements, événements, scores, tâches CAL, scheduler, stockage, progression et contrôleur réel ; les commandes, résultats et limites sont dans le [plan de réception](TEST_PLAN_V2.md). Les replays et bilans synthétiques servent uniquement à vérifier le logiciel. Ils ne démontrent ni une performance humaine, ni une réception physique de la souris, ni un lancement Windows natif.

## 1. Ce qui change depuis 0.9

| Sujet | Historique 0.9 | V2 / 1.0.0 |
|---|---|---|
| Catalogue | 18 exercices, suivis r7 et clics/transitions r6 | EX01 à EX08 ; 24 configurations et 54 phases résolues |
| Durée publique | Choix de durées et entraînement composite séparé | Chaque carte dure exactement 60 s de temps actif |
| Vie des cibles | Expirations et shrink génériques | TTL seulement pour EX03 ; shrink seulement dans `shrinking_window` |
| Suivi | Cycles temporaires avec réacquisition | Identité persistante pendant la phase ; mouvements propres à chaque programme |
| Transitions | Mécaniques historiques conservées dans leurs versions | Quatre cibles avec PV, maintien à 100 PV/s, conservation des dégâts partiels |
| Score de clic | Score temporel V2 historique, pénalité comprenant les expirations | `click_v3`, débit multiplié une fois par la précision des fronts de tir |
| Scores composites | Rapports historiques dans leurs contextes | C/P séparés ; seuls les indices T/S prévus par le catalogue sont agrégés |
| Calibration | Protocole 6 : cinq activités et cinq sensibilités successives | `sustained_blocks_v2`, quatre tâches dédiées et confirmation sur deux journées |
| Présentation | Precision Lab clair et cibles corail | Thème V2 sombre, cibles turquoise/ambre, sphères non éclairées et repères documentaires séparés |
| Données | Espace historique `user://aim_local` | Nouveau sous-espace `user://aim_local/v2`, versions et empreintes séparées |

Les anciens résultats ne sont pas réinterprétés avec les nouveaux scores. L’ancienne documentation, les fichiers historiques et les ZIP 0.9 restent conservés jusqu’à réception des nouveaux éléments.

## 2. Autorité des données et architecture

### 2.1 Fichiers importés

Les cinq fichiers ci-dessous sont copiés **octet pour octet** depuis le kit original. Ils ne sont ni reconstruits depuis l’Atlas, ni corrigés par un multiplicateur de difficulté.

| Fichier embarqué | Autorité |
|---|---|
| [`content/v2/catalogue.v2.json`](../content/v2/catalogue.v2.json) | Programmes, phases et paramètres résolus |
| [`content/v2/interface.theme.json`](../content/v2/interface.theme.json) | Palette, typographie, arène, HUD, feedback, audio |
| [`content/v2/runtime.contract.json`](../content/v2/runtime.contract.json) | Convention d’exécution et budgets numériques |
| [`content/v2/calibration_v2_protocol.json`](../content/v2/calibration_v2_protocol.json) | Tâches, plans, conditions et règles de décision CAL |
| [`content/v2/empreintes.fixtures.json`](../content/v2/empreintes.fixtures.json) | Vecteurs AIM-CANON-1 originaux |

Le catalogue a neuf clés de premier niveau : `schema_version`, `catalogue_revision`, `design_status`, `configuration_count`, `public_program_count`, `laboratory_extensions_enabled`, `sensitivity_calibration_uses_separate_tasks`, `randomization`, `programs`. Sa révision est `2026-10-12-v2.0` et son SHA-256 de fichier est `b72277ca6ac33b93aa38ac73092c529f2152c2ab88199fa0fcaea3ee93154781`.

Le [manifeste d’import](../content/v2/atlas_source_manifest.json) conserve les SHA du fichier HTML, de son bloc JSON brut, des cinq copies et du manifeste `SHA256SUMS.txt`, ainsi que les comptages. Les empreintes JSON documentaires de l’extraction sont explicitement **distinctes d’AIM-CANON-1**. Les positions, états et opportunités illustratives de l’Atlas restent documentaires ; seules ses définitions sont comparées au catalogue original, en mémoire.

Le propriétaire du schéma est le kit : [`schemas/catalogue.schema.json`](reference/v2/schemas/catalogue.schema.json), SHA-256 `211563525acb4c23dada3351386cb84f2b6f59bb6761ea7b0f8bee82186743e6`, avec 14 définitions nommées. L’importeur vérifie puis utilise le validateur stdlib fourni [`outils/valider_catalogue.py`](reference/v2/outils/valider_catalogue.py). Les données et le code de référence sont contrôlés avant cet usage ; aucun JavaScript de l’Atlas n’est exécuté et aucune URL n’est chargée.

### 2.2 Modules natifs

| Module | Responsabilité actuelle |
|---|---|
| [`V2Catalog`](../scripts/v2/v2_catalog.gd) | Garde SHA des octets originaux, copies indépendantes, schéma fourni embarqué et contrôles sémantiques des programmes |
| [`V2Canonical`](../scripts/v2/v2_canonical.gd) | Encodage AIM-CANON-1 et empreintes sémantiques |
| [`V2Random`](../scripts/v2/v2_random.gd) | PRNG et dérivation des sous-flux |
| [`V2Geometry`](../scripts/v2/v2_geometry.gd) | Directions angulaires, séparation et rayon/sphère |
| [`V2Motion`](../scripts/v2/v2_motion.gd) | Compilation et évaluation analytique des mouvements |
| [`V2Spawner`](../scripts/v2/v2_spawner.gd) | Instances par slot/génération, contraintes et remplacement |
| [`V2Contact`](../scripts/v2/v2_contact.gd) | Bornes et estimation du temps de contact |
| [`V2SessionEngine`](../scripts/v2/v2_session_engine.gd) | Horloge active, entrées reçues, phases, hits, dégâts, rapports |
| [`V2Scores`](../scripts/v2/v2_scores.gd) | Formules de phase, agrégats et clés de comparaison |
| [`V2Arena`](../scripts/v2/v2_arena.gd), [`V2Preview`](../scripts/v2/v2_preview.gd) | Rendu des sphères et aperçu non mesuré |
| [`V2AppController`](../scripts/v2/v2_app_controller.gd) | Profil, capture, countdown, pause, dessin et parcours UI/CAL |
| [`V2Store`](../scripts/v2/v2_store.gd) | Profil, rapports immuables, état CAL et lecture historique |
| [`V2CalibrationService`](../scripts/v2/v2_calibration_service.gd) | Gains, decks, plans, conditions, epochs et décision |
| [`V2CalibrationTask`](../scripts/v2/v2_calibration_task.gd) | Exécution des quatre tâches CAL à partir de decks vérifiés |

API du catalogue : `load_catalog() -> Dictionary`, `programs() -> Array`, `find(program_id, difficulty) -> Dictionary`, `validate_program(config) -> Dictionary`. Les 24 dictionnaires d’exercice gardent leurs champs originaux et `find()` renvoie une copie profonde. Un résultat de validation contient `ok`, `error`, `code`, `path` et, s’il est valide, `definition_sha256 = V2Canonical.semantic_sha256(config)`.

La garde des octets protège cette édition fixe du catalogue. Le validateur natif applique le sous-ensemble du schéma original annoncé et des contraintes sémantiques ; les nouveaux mots-clés et références externes sont refusés. Le contrôle d’accélération de l’ellipse utilise 8 192 échantillons des dérivées exactes : il ne constitue pas un certificat continu de son maximum. Les contrôles complets du validateur Python fourni restent dans la chaîne d’import. Tout appel de runtime acceptant un dictionnaire arbitraire doit le valider avant d’accéder à ses champs ; la couverture de ce branchement fait partie de la réception.

## 3. Les 24 configurations et leurs 54 phases

Chaque programme possède les trois identités `<EXxx>/novice`, `<EXxx>/standard` et `<EXxx>/advanced`. Cela représente huit configurations par niveau, 24 au total. Les 18 lignes de phase ci-dessous sont chacune résolues dans les trois niveaux : **54 phases**. N/S/A désignent Novice/Standard/Avancé. Les nombres angulaires sont des **diamètres complets**, pas des rayons.

| Programme / phase | Fenêtre active | Cibles | Diamètre N / S / A en degrés | Modèle | Score |
|---|---|---:|---|---|---|
| EX01 `micro` | `[0,20)` s | 1 | 1,8 / 1,2 / 0,8 | `static` | C |
| EX01 `general` | `[20,40)` s | 1 | 3,2 / 2,4 / 1,6 | `static` | C |
| EX01 `amplitude` | `[40,60)` s | 1 | 3,2 / 2,4 / 1,6 | `static` | C |
| EX02 `grid` | `[0,20)` s | 3 | 4,8 / 4,0 / 3,2 | `static` | C |
| EX02 `precision` | `[20,60)` s | 6 | 1,8 / 1,2 / 0,8 | `static` | C |
| EX03 `fixed_window` | `[0,30)` s | ≤1 | 3,2 / 2,4 / 1,8 | `static` | P |
| EX03 `shrinking_window` | `[30,60)` s | ≤1 | Début 3,2 / 2,4 / 1,8 ; fin 1,92 / 1,44 / 1,08 | `static` | P |
| EX04 `linear` | `[0,20)` s | 4 | 2,8 / 2,0 / 1,4 | `linear_reflect` instantané | C |
| EX04 `evasive` | `[20,40)` s | 4 | 2,8 / 2,0 / 1,4 | `reactive_lanes` | C |
| EX04 `arcs` | `[40,60)` s | 4 | 2,8 / 2,0 / 1,4 | `angular_bounce` | C |
| EX05 `horizontal` | `[0,20)` s | 1 | 3,6 / 2,6 / 1,8 | `sinusoid_axis`, yaw | T |
| EX05 `vertical` | `[20,40)` s | 1 | 3,6 / 2,6 / 1,8 | `sinusoid_axis`, pitch | T |
| EX05 `ellipse` | `[40,60)` s | 1 | 3,6 / 2,6 / 1,8 | `angular_ellipse` | T |
| EX06 `reactive` | `[0,60)` s | 1 | 3,4 / 2,6 / 1,8 | `reactive_axis` | T |
| EX07 `depth` | `[0,60)` s | 1 | 3,6 / 2,6 / 1,8 à 4 m | `depth_sines` | T |
| EX08 `static` | `[0,20)` s | 4 | 3,4 / 2,6 / 1,8 | `static` | S |
| EX08 `mobile` | `[20,40)` s | 4 | 3,4 / 2,6 / 1,8 | `linear_reflect` lissé | S |
| EX08 `evasive` | `[40,60)` s | 4 | 3,4 / 2,6 / 1,8 | `reactive_lanes` | S |

Toutes les distances de référence sont de 4 m. Seule EX07 varie réellement entre 3 et 5 m. Les tableaux donnent les valeurs prescrites ou identifient explicitement les approximations ; les coefficients dérivés complets restent dans le JSON original.

### 3.1 EX01 — Acquisition

Une cible immobile reste jusqu’au hit ou à la fermeture de phase. Un miss ne déplace pas la cible et ne relance pas sa vie. Le remplacement est logique à l’instant du hit ; son admissibilité au tir attend sa propre première image visible.

| Phase | Yaw / pitch des centres | Transition depuis le centre précédent |
|---|---|---|
| `micro` | ±6° / ±4° | 2–6° |
| `general` | ±22° / ±12° | Sac de bandes 5–12°, 12–22°, 22–32° |
| `amplitude` | ±32° / ±12° | 20–38° |

Le sac général contient quatre occurrences de chaque bande, soit douze naissances, mélangées sans biais et rechargées seulement lorsqu’il est vide. Le tirage radial est uniforme en cosinus de distance angulaire, avec azimut uniforme, puis rejet hors enveloppe. L’ancre initiale est `(0°,0°)` ; les suivantes sont les centres précédents du même slot, indépendamment du viseur. Les trois scores C restent séparés.

### 3.2 EX02 — Multicibles

La grille possède neuf nœuds : yaw −10/0/+10°, pitch −7/0/+7°. Trois nœuds sont actifs. Après hit, les deux autres cibles restent intactes et le nœud remplacé est tiré parmi les nœuds libres en excluant celui tout juste touché.

La précision répartie place six cibles dans yaw ±22°, pitch ±12°. La marge entre silhouettes est 0,75° ; la séparation minimale des centres égaux vaut 2,55° / 1,95° / 1,55° selon niveau. Le remplacement reste à au moins 3° du centre précédent. À 20 s, les cibles restantes de grille sont censurées, puis la phase de précision commence sans temps ajouté. Une moyenne des deux scores C n’est pas un benchmark prévu.

### 3.3 EX03 — Temporisées

Chaque phase contient **dix créneaux de 3 s**. Pour `j=0..9`, `onset_j = 3j + delay_j`, avec `delay_j` dans `[0,65;1,15]` s. Les TTL N/S/A sont **1,4 / 1,1 / 0,8 s**. Même la dernière fenêtre la plus longue finit à 29,55 s dans sa phase de 30 s.

Les positions et les dates sont préconstruites ; un hit ne modifie pas le prochain onset. Un miss laisse la fenêtre ouverte. Un hit clôt l’opportunité ; un front de tir exactement à la deadline est trop tard, car la fenêtre est `[onset,deadline)`. Les tirs dans l’arène vide restent dans le dénominateur des fronts de tir.

La première phase garde son diamètre. La seconde interpole **le diamètre angulaire**, linéairement de 100 % à 60 % sur sa fenêtre, puis recalcule le rayon physique. Pas de shrink ailleurs dans le catalogue. Les issues exclusives sont `hit`, `expired`, `censored_phase`, `censored_technical`. Une absence technique de dessin ne doit pas devenir un échec humain.

### 3.4 EX04 — Clic mobile

Quatre cibles, une par couloir ou chambre, restent actives jusqu’au hit ou à la clôture. Leur diamètre est constant dans les trois phases d’un niveau.

| Paramètre | N | S | A |
|---|---:|---:|---:|
| Linéaire : vitesse yaw, °/s | 6 | 10 | 14 |
| Évasif : norme yaw, °/s | 5,95–7 | 10,2–12 | 17–20 |
| Évasif : plateau après rampe, s | 0,8–1,4 | 0,5–1,1 | 0,3–0,8 |
| Évasif : rampe nominale, s | 0,18 | 0,14 | 0,10 |
| Évasif : cap d’accélération yaw, °/s² | 150 | 300 | 650 |
| Arcs : hauteur au-dessus du plancher, ° | 6 | 9 | 12 |
| Arcs : durée de vol, s | 1,1 | 0,9 | 0,75 |
| Arcs : vitesse yaw, °/s | 5 | 8 | 12 |

Le linéaire utilise quatre couloirs à pitch −9/−3/+3/+9° et yaw ±20°. Sa réflexion inverse instantanément la vitesse ; aucune limite finie d’accélération n’est prétendue. Le remplacement est à au moins 4° du centre détruit dans son couloir.

L’évasif utilise yaw ±22°, seuils de demi-tour ±19°, les mêmes couloirs et une oscillation verticale d’amplitude 1,2° et période 4 s. Les décisions spontanées inversent le signe avec probabilité 0,7 ; les 30 % restantes gardent le signe et tirent une nouvelle norme. Le plateau commence à la fin de la rampe, pas au début de la décision.

Les chambres des arcs sont `[-22,-14]`, `[-10,-2]`, `[2,10]`, `[14,22]` en yaw, avec plancher pitch −8°. Le mouvement vertical est une parabole **angulaire** : `pitch(a) = -8 + (4h/F)a - (4h/F²)a²`. L’âge initial est uniforme dans le vol ; le repos suivant vaut 0,05–0,18 s, tandis que yaw continue. L’inversion à l’atterrissage a probabilité 0,5 et le bord impose la direction entrante lors d’une égalité. Le remplacement minimal vaut 3° ; le porter arbitrairement à 4° rendrait certains placements impossibles.

### 3.5 EX05 — Suivi fluide

Une cible invincible persiste pendant chaque phase, sans tir nécessaire, expiration ni réacquisition périodique. La sinusoïde utilise `A sin(ωt+φ)` avec phase initiale uniforme ; vitesse et accélération maximales valent `Aω` et `Aω²`.

| Paramètre | N | S | A |
|---|---:|---:|---:|
| Horizontal : amplitude, ° | 18 | 18 | 18 |
| Horizontal : vitesse maximale, °/s | 12 | 16 | 20 |
| Horizontal : accélération maximale, °/s² | 8 | ≈14,222222 | ≈22,222222 |
| Vertical : amplitude, ° | 14 | 14 | 14 |
| Vertical : vitesse maximale, °/s | 10 | 14 | 18 |
| Vertical : accélération maximale, °/s² | ≈7,142857 | 14 | ≈23,142857 |
| Ellipse : vitesse d’arc, °/s | 10 | 14 | 18 |

L’ellipse suit yaw `16 cos(q)` et pitch `10 sin(q)`. La phase initiale est uniforme en **longueur d’arc sphérique**, et non en `q`. La table utilise 4 096 cellules, la quadrature de Simpson et une inversion encadrée ; tolérance d’arc 10⁻9 rad, au plus 16 itérations. Le cap de validation du vecteur accélération est 70°/s² pour les presets, contrôlé numériquement.

À une frontière annoncée, la cible peut passer à un état initial différent de la nouvelle trajectoire. L’acquisition de cette nouvelle phase appartient à son dénominateur ; elle ne constitue pas une pause exclue. EX05 conserve trois scores T et l’indice pondéré par le temps du programme.

### 3.6 EX06 — Suivi réactif

Une cible conserve son identité pendant 60 s, à pitch 0 et yaw ±24°. Les seuils de bord sont ±21°. Les vitesses initiales sont déjà signées et non nulles ; la trajectoire ne part pas systématiquement de l’arrêt.

| Paramètre | N | S | A |
|---|---|---|---|
| Norme yaw, °/s | 12–18 | 18–28 | 26–38 |
| Plateau après rampe, s | U[0,65;1,30] | 70 % U[0,70;1,20] + 30 % U[0,28;0,45] | 60 % U[0,45;0,90] + 40 % U[0,20;0,35] |
| Rampe nominale, s | 0,18 | 0,14 | 0,10 |
| Cap d’accélération yaw, °/s² | 350 | 700 | 1 200 |

La rampe de vitesse utilise `S(u)=3u²−2u³` et `τ=max(τ_nominal,1,5×|v1−v0|/a_max)`. L’intégrale conserve les coefficients d’origine lors d’une préemption. Le bord est prioritaire, y compris dans une rampe ou à `t=0` ; le retour vise la dernière norme de plateau tirée. Le contrôle n’est réarmé qu’après retour vers l’intérieur avec vitesse entrante. Les événements compilés sont évalués sans RNG par image.

Le moteur public EX06 construit ses diagnostics à partir des zéros de vitesse effectifs du tape compilé, avec découpage des segments et de la fenêtre de 250 ms à l’inversion suivante. Une acquisition stable exige 50 ms continus dans des intervalles de contact **certifiés à l’intérieur** ; sa latence part du début de l’intervalle admissible. Sans donnée admissible, le rapport garde `null`. La fusion de trous de 20 ms sert uniquement au diagnostic de fragmentation : elle ne fabrique ni contact brut, ni acquisition stable, ni score. Les résultats des événements spontanés et de bord doivent rester distingués dans la réception.

### 3.7 EX07 — Contrôle 3D

Yaw et pitch suivent respectivement `20 sin(ω_h t+φ_h)` et `10 sin(ω_p t+φ_p)`. La distance vaut `4 + sin(ω_d t+φ_d)` m. Les trois phases initiales sont uniformes et indépendantes.

| Paramètre | N | S | A |
|---|---:|---:|---:|
| `ω_h`, rad/s | 0,45 | 0,60 | 0,84 |
| `ω_p`, rad/s | 0,6375 | 0,85 | 1,19 |
| `ω_d`, rad/s | 0,375 | 0,50 | 0,70 |
| Vitesse radiale maximale, m/s | 0,375 | 0,50 | 0,70 |
| Accélération radiale maximale, m/s² | 0,140625 | 0,25 | 0,49 |

Le rayon physique reste `r = 4 sin(D_reference/2)` m. Le diamètre apparent vaut `2 asin(r/d(t))` : la même sphère paraît plus grande à 3 m et plus petite à 5 m. Aucun changement de taille écran, vieillissement ou respawn ne compense cette perspective.

### 3.8 EX08 — Transitions

Les quatre cibles ont **30 / 40 / 50 PV** selon niveau, identiques entre les trois phases. Le rayon maintenu inflige **100 PV/s** de contact utile : temps idéal de destruction **0,30 / 0,40 / 0,50 s**. Un clic isolé ne donne pas une élimination instantanée ; les dégâts partiels restent jusqu’au kill ou à la clôture, sans régénération.

| Paramètre | N | S | A |
|---|---:|---:|---:|
| Mobile : vitesse yaw, °/s | 6 | 9 | 14 |
| Mobile : durée de demi-tour, s | 0,24 | 0,24 | 0,24 |
| Retrait au début de demi-tour, ° | 0,45 | 0,675 | 1,05 |
| Accélération maximale mobile, °/s² | 75 | 112,5 | 175 |
| Évasif : norme yaw, °/s | 8,5–10 | 13,6–16 | 20,4–24 |
| Évasif : plateau, s | 0,8–1,3 | 0,45–1,0 | 0,30–0,75 |
| Évasif : rampe nominale, s | 0,18 | 0,14 | 0,10 |
| Évasif : cap d’accélération yaw, °/s² | 200 | 400 | 800 |

La phase mobile garde `motion.kind="linear_reflect"` et précise `reflection="symmetric_cubic_smoothstep_velocity"`. C’est le modificateur qui impose les demi-tours lissés, contrairement au linéaire d’EX04. Son retrait vaut `δ=5vτ/16`, son accélération maximale `3v/τ` ; la phase initiale est tirée dans le cycle complet. Les quatre couloirs sont les mêmes que pour le clic mobile, dans yaw ±22°.

L’évasif utilise yaw ±24°, seuils ±21° et oscillation verticale d’amplitude 0,9°, période 4 s. Aux fermetures à 20/40/60 s, les fractions de dégâts de **toutes** les cibles vivantes sont créditées. Une destruction exactement à la frontière appartient à l’ancienne phase et ne crée pas de remplaçante de cette phase. Un maintien déjà armé peut continuer dans la phase suivante ; les dégâts n’entrent jamais dans une génération qui n’a pas encore sa propre image admissible.

## 4. Géométrie, temps et rendu

### 4.1 Une sphère commune au rendu et à la collision

L’œil est à `(0;1,6;0)` m ; avant `−Z`, droite `+X`, haut `+Y`, roulis nul. Le joueur reste immobile. Une cible de diamètre angulaire complet `D` et distance de centre `d` a rayon `r=d sin(D/2)` ; les fonctions trigonométriques reçoivent des radians.

Les enveloppes concernent les **centres**, puis la totalité de la sphère doit tenir dans le frustum et garder au moins 0,05 m de marge au sol. Le mur à `z=−18 m` est une référence visuelle, pas un plan de placement. Le FOV de référence est 103° horizontal à 16:9, soit 70,53280043291679° vertical. Aucun scaling d’interface ne change la hitbox ou le gain.

### 4.2 Frontières de phase

Le décompte initial est non mesuré. Le temps actif traverse les phases sans gel, fondu ou recentrage ; un préavis HUD est prévu deux secondes avant la frontière.

À une frontière : intégrer le contact ancien, appliquer le kill atteignant son seuil à cet instant, fermer les épisodes de contact, créditer les partials S, censurer les autres instances, fermer le rapport, ouvrir la nouvelle phase, puis router le front de tir exactement à cette date vers cette nouvelle phase. À 60 s, aucun nouveau tir ou spawn ne rapporte de point. La deadline d’une opportunité reste exclusive.

### 4.3 Pose reçue et première image

`received_pose_hold_v1` utilise les événements reçus et leur séquence ; deux événements au même timestamp gardent leur ordre d’arrivée. Le gain est appliqué une seule fois à `screen_relative`, sans delta d’image, lissage ou accélération ajoutée. La capture V2 utilise `Input.use_accumulated_input=false`. La dernière pose est maintenue entre événements, puis l’intégration est scindée à chaque nouvelle pose et événement mécanique.

`RenderingServer.frame_post_draw` fournit au moteur les identités préparées et celles considérées comme dessinées dans le viewport utile. Le moteur conserve une première confirmation de dessin (`first_render_ack_s`) et une première visibilité admissible (`first_rendered_s`). Une cible préparée alors que le joueur regarde ailleurs ne devient pas automatiquement une panne technique ; une opportunité jamais dessinée doit être censurée techniquement. Le hit et le contact utile nécessitent la marque admissible de la génération courante.

Ces marques sont des **proxies moteur**, pas des timestamps physiques de scanout. Elles ne repoussent ni onset ni deadline. En suivi, elles protègent uniquement le numérateur : l’exposition reste toute la durée programmée, même lors de l’acquisition initiale ou d’un regard ailleurs.

### 4.4 Contact borné

`V2Contact` traite des tranches d’au plus `1/240 s`, subdivise les passages proches du bord utile avec une borne de variation angulaire, et retourne `lower_s`, `upper_s`, `estimate_s`. Une file de priorité contrôle la largeur ambiguë cumulée, au lieu d’accepter indépendamment une limite par feuille. L’estimation de score reste le milieu des bornes brutes. Les intervalles certifiés servent aux diagnostics exigeant du contact continu ; ils ne sont pas obtenus par fusion des trous. Les passages sont scindés aux poses, apparitions, deadlines, kills et frontières ; les budgets sont **8 192 évaluations par tranche** et **4 000 000 par phase**.

La largeur visée du contrat est au plus **0,0005 × durée active**, soit 10 ms pour 20 s ou 30 ms pour 60 s. La recherche de kill du moteur utilise une tolérance temporelle de 0,0001 s. Un budget épuisé ou une ambiguïté persistante non résolue invalide explicitement le passage ; la QA vérifie la largeur cumulée, les tangences et le contact utilisé par les partials. Un score de test headless reste une mesure logicielle diagnostique ; sans données réelles de rendu, il ne prouve pas la qualité de présentation ni le comportement matériel.

## 5. Scores et comparaison

`H` est le nombre de hits valides, `S` celui des fronts de tir, `T` la durée nominale de phase, `O` les opportunités, `C` le contact admissible, `E` l’exposition programmée, `K` les kills, `p_i` les fractions de dégâts finales des cibles vivantes.

| Famille / version | Score de phase |
|---|---|
| C — `click_v3` | `1000 × (H/T) × H/max(S,1)` |
| P — `opportunities_v2` | `1000 × (H/O) × H/max(S,1)`, avec O=10 pour une phase EX03 complète |
| T — `contact_v2` | `1000 × C/E`, avec E=20 s pour EX05 et E=60 s pour EX06/EX07 |
| S — `switch_work_v3` | `1000 × (K + Σp_i)/T` |

Un passage incomplet ou invalidé garde ses mesures descriptives et n’a pas de score classable. Un suivi complet sans contact vaut zéro sur son exposition entière. EX01/02/03/04 ne publient pas de score global mélangeant leurs phases. EX05 publie `1000×ΣC/60` ; EX06 et EX07 ont une phase unique ; EX08 publie `1000×Σ(K+Σp_i)/60` avec ses trois résultats de phase.

L’affichage peut arrondir un score, mais le calcul, les décisions et les empreintes gardent les valeurs non arrondies. La clé de comparaison inclut définition, révision, programme, difficulté, phase si applicable, gain et conditions d’entrée/rendu. Le `rank_key_suffix` original ne suffit pas seul. Le moteur exige une séance complète, sans invalidation ni pause et avec `render_quality.valid` pour `rank_eligible` ; la réception vérifie ce lien. Un résultat headless sans frametimes peut rester diagnostique tout en étant exclu des records.

## 6. Hasard, manifests et reproductibilité

Le PRNG est **xorshift32**, avec masquage 32 bits après les opérations 13/17/5. Une sous-graine nulle devient `0x6D2B79F5`. L’uniforme flottant vaut `(uint32+0,5)/2^32` ; les entiers sont tirés par rejet, les permutations par Fisher–Yates sans biais modulo.

Une séance publique possède une graine hexadécimale de **32 caractères**. Les sous-flux sont dérivés par SHA-256 du JSON compact de six chaînes ASCII : `[catalogue_revision, session_seed_hex, program_id, difficulty, phase_id, stream_name]`. Le nom suit `domain/slot/generation/purpose`. Layout, timing, motion, diagnostic et cosmetic restent séparés ; un effet ne consomme pas le flux d’une trajectoire.

Les distributions rectangulaires sont uniformes en angle solide, les anneaux uniformes en cosinus de distance angulaire. Les candidats doivent respecter enveloppe, sphère complète, sol, silhouettes voisines et transition depuis le centre précédent. Après au plus **128 candidats**, le fallback examine une grille angulaire de pas **0,25°**, choisit par hash parmi les candidats valides et n’assouplit aucune contrainte. Une recherche impossible invalide la séance.

Le manifeste conserve slot, génération, onset/deadline, ancre, choix initial, sous-graine et empreinte du mouvement compilé. Le compilateur reste **`motion_reference_v2.0`**. Un remplacement dépend du hit/kill et des voisins vivants : une configuration et une graine ne suffisent pas à reconstruire toute une histoire sans entrées et marques de rendu.

Le contrôleur courant utilise `retain_input_trace=false`. Le rapport porte alors `trace_retention="light_no_exact_input_replay"` et `pose_event_count` : il garde le manifeste et le nombre de poses, mais n’annonce pas un replay exact des entrées. La QA peut activer la trace complète `received_pose_trace`, limitée à 1 000 000 poses ; la file en attente est limitée à 65 536 événements. Un débordement invalide plutôt que supprimer des mouvements. L’audit des tâches CAL est un contrat distinct du mode léger de pratique.

## 7. Calibration soutenue V2

### 7.1 Portée et état de l’intégration

Le protocole original est `sustained_blocks_v2`, révision `2026-10-12-v2.0`. Il estime la **performance au gain testé après une prise en main courte et fixe**. Il ne calcule pas un optimum continu et ne démontre pas une adaptation durable.

Le service natif produit les gains, decks et plans ; il valide conditions, dates, epochs et décisions. Le moteur de tâche exécute les quatre decks dédiés. Le contrôleur branche maintenant préparation, décompte, mesures, pauses de récupération, journées, interruptions, application consentie et annulation. Le calendrier utilise les dates locales et leurs décalages UTC réels ; les entrées et durées actives reposent sur l’horloge monotone.

`V2CalibrationRunner` sauvegarde le plan avant l’application d’un gain temporaire. Une attente volontaire devant « Je suis prêt » prolonge le calendrier réel sans consommer le décompte ni la fenêtre mesurée. Le gain reste celui du bloc pendant cette attente, les récupérations et deux périodes adjacentes identiques. Une nouvelle comparaison archive le plan précédent au lieu de remplacer ses rapports.

La revue du préflight peut proposer un niveau voisin, uniquement avant les mesures d’express. Le choix explicite lance une validation de 24 secondes au gain initial, conserve cet audit non comparatif, génère un nouveau plan et refait la familiarisation de 60 secondes. Chaque changement ajoute donc au moins 84 secondes ; au plus deux changements sont autorisés par geste. Les difficultés ne sont plus modifiables dans la confirmation.

Les traces CAL sont obligatoires : poses binary64, fronts de tir, marques de rendu et intervalles de frame sont encodés en little-endian, compressés en Zstd lorsque cela réduit leur taille, puis accompagnés de leurs nombres d’enregistrements et empreintes SHA-256. Le rapport complet est sauvegardé avant sa référence dans une cellule. Les huit mébioctets constituent une limite explicite : un audit qui ne peut pas être conservé n’autorise pas une comparaison partielle. Les marqueurs `frame_post_draw` attestent le traitement applicatif du rendu préparé, pas la présentation physique par l’écran.

L’application d’un candidat confirmé conserve un journal d’intention et de validation, ainsi que le profil initial exact. Le changement n’est pas relu depuis une étiquette arrondie. « Revenir au réglage précédent » restaure les bits du gain initial et sa provenance ; un changement non validé est récupéré sans transformer une intention en application réussie.

### 7.2 Quatre tâches de 24 secondes

| Tâche | Stimulus original | Utilité comparative U |
|---|---|---|
| CLICK — `CAL_CLICK_R2` | 16 créneaux de 1,5 s ; délai 0,10–0,25 s ; fenêtre 1,20 s ; tailles et amplitudes équilibrées | Moyenne de `1−τ/1,20` si le premier tir réussit, sinon 0 |
| SMOOTH — `CAL_SMOOTH_R2` | Sinusoïde yaw ±14° ; cible persistante ; vitesses max N/S/A 12/18/24°/s | `contact_s/24` |
| REACTIVE — `CAL_REACTIVE_R2` | Modèle et générateur exacts d’EX06, limités à 24 s ; même version de compilateur | `contact_s/24` |
| SWITCH — `CAL_SWITCH_R2` | 12 créneaux de 2 s ; trois positions ; priorité équilibrée ; fenêtre 1,70 s ; PV N/S/A 15/20/30 | Moyenne de `clamp((1,70−τ)/(1,70−PV/100),0,1)` si la priorité est détruite, sinon 0 |

CLICK utilise diamètres petits/grands N `1,6/2,8°`, S `1,0/2,0°`, A `0,7/1,4°`, croisés avec deux bandes d’amplitude 4–8° et 18–30°, quatre opportunités par cellule. Le **premier** front consomme l’opportunité : avant sa première image visible il est prématuré, ensuite il est hit ou miss. Les tirs supplémentaires ou tardifs sont diagnostiques et ne changent pas le score. Un maintien ne répète pas les tirs.

SWITCH sépare ses centres d’au moins 10°, montre une priorité par créneau, remet ses PV à l’onset et permet de maintenir le bouton entre les créneaux. Avant l’onset, les positions restent neutres et la future priorité n’est pas révélée ; après kill ou deadline, aucun travail supplémentaire n’entre dans cette opportunité. SMOOTH/REACTIVE gardent leur acquisition initiale dans le dénominateur et n’exigent pas de bouton.

### 7.3 Decks et empreintes

Les stimuli sont précompilés avant le premier rendu mesuré. Les périodes appariées partagent les decks exigés par le plan, indépendamment de la sensibilité ; les nouveaux epochs ont les nouveaux decks prescrits. Le tuple CAL possède **huit chaînes** : `[revision, plan_seed, phase, day_role, pair, epoch, task, domain]`. Il reste distinct du tuple public à six chaînes et des sous-flux internes du compilateur.

Plans, snapshots de conditions, gains réellement appliqués, decks et rapports se relient par AIM-CANON-1. Un hash cohérent ne prouve pas une validité sémantique : les [plans négatifs du kit](reference/v2/donnees/calibration_v2_plan_negative_fixtures.json) recalculent leurs empreintes après mutation. Les [exemples de plan](reference/v2/donnees/calibration_v2_plan_example.json) et [comparaisons synthétiques](reference/v2/donnees/calibration_v2_comparison_examples.json) sont des fixtures de développement, jamais des données du joueur. Le plan d’exemple n’est pas un plan de runtime prêt à mesurer.

### 7.4 Gains et durée

La grille est multiplicative en cm/360 : ratio par défaut 1,25, exploration large 1,5, bornes techniques 5–150 cm. La référence conserve son gain réellement appliqué ; les candidats sont résolus et distingués après quantification avant mesure. Aucun candidat dupliqué, interpolation parabolique ou conseil hors grille n’est ajouté.

Une période de **192 s au même gain** comprend 60 s de prise en main — 15 s par tâche — puis quatre blocs `3 s de décompte + 24 s notées + 6 s de récupération`. Les gains restent constants pendant ces éléments et le repos inter-période ; deux périodes voisines de même gain ne restaurent pas brièvement la référence.

| Parcours | Durée programmée minimale |
|---|---:|
| Express, trois gains | 696 s = 11 min 36 s |
| Express, deux gains aux bornes | 474 s = 7 min 54 s |
| Confirmation, une journée de quatre périodes | 1 008 s = 16 min 48 s |
| Confirmation, deux journées | 2 016 s = 33 min 36 s |
| Express à trois gains puis confirmation | 2 712 s = 45 min 12 s sur trois séances |

Ces durées incluent le préflight prévu et les repos programmés ; elles ne comprennent pas toutes les attentes, interruptions et reprises réelles, qui doivent être enregistrées séparément.

### 7.5 Ordres, conditions et reprises

L’express utilise une permutation seedée des gains distincts, figée avant les scores. La confirmation utilise ABBA ou BAAB au premier jour, puis l’ordre opposé au second. Ordre des tâches : CLICK/SMOOTH/SWITCH/REACTIVE au premier jour et à l’express ; REACTIVE/SWITCH/SMOOTH/CLICK au second.

Les deux journées acceptées ont des dates locales distinctes, avec **12–168 h** entre débuts ; la première confirmation attend au moins 12 h après la fin d’express. Un epoch accepté est le **premier complet et techniquement valide**, jamais le meilleur score. Deux tentatives au maximum sont prévues par rôle de journée ; une reprise rejoue toute cette journée et ses quatre périodes avec les nouveaux decks partagés prescrits, sans sélectionner des cellules selon la performance.

Pause pendant une tâche notée, perte de focus/capture, overflow, mauvaise empreinte, changement de conditions, fallback de spawn ou erreur d’intégration invalident l’epoch concerné. Une interruption imprévue supérieure à 900 s demande un nouvel epoch complet. Le gain de référence doit être restauré en fin, abandon, exception et redémarrage du processus.

La qualité exige moyenne ≥55 FPS, p99 d’intervalle ≤25 ms, maximum ≤100 ms et différence relative des FPS médians appariés ≤10 %. Le quantile CAL du protocole est le nearest-rank, défini dans le fichier original. Une absence de mouvement n’est pas, à elle seule, une panne matérielle. Une tâche moyenne ≤0,10 ou ≥0,95 est non informative pour la décision ; la question de fatigue facultative ne transforme pas seule une séance humaine en donnée techniquement invalide.

### 7.6 Comparaison et application

Les pondérations du composite sont : polyvalent `0,25/0,25/0,25/0,25`, acquisition `0,45/0,15/0,15/0,25`, suivi `0,15/0,30/0,35/0,20`, dans l’ordre CLICK/SMOOTH/REACTIVE/SWITCH. L’express choisit un challenger non référence parmi les résultats complets ; une égalité dans 0,25 point de pourcentage privilégie la plus faible distance logarithmique au réglage initial, puis l’ID stable.

La confirmation utilise **ses propres données**, sans ajouter les scores d’express. La marge primaire est 2 points de pourcentage ; le garde-fou par tâche vaut 5 points. Les compteurs de réussite restent contrôlés : 64 opportunités CLICK et 48 SWITCH par gain en confirmation, pertes admises respectivement de 3 et 4 réussites. Les comparaisons utilisent les valeurs non arrondies, avec la tolérance numérique prescrite de 10⁻9 point de pourcentage.

Les huit statuts, dans leur ordre de priorité, sont `unstable_conditions`, `incomplete`, `exploratory_only`, `repeated_regression`, `repeated_improvement`, `mixed_tradeoff`, `close_observed`, `undetermined`. Une amélioration répétée exige les marges journalières, toutes les paires positives et les garde-fous ; des conditions instables ou une tâche non informative ne deviennent pas une recommandation malgré un meilleur composite.

L’action par défaut conserve le réglage initial, sauf proposition explicitement acceptée après amélioration répétée. Le contrôleur enregistre une intention d’application, archive le plan, sauvegarde le profil candidat puis inscrit le commit. Un échec du commit restaure les bits du profil initial ; une intention non terminée est récupérée au démarrage. L’annulation enregistre sa propre intention et son commit, restaure les bits initiaux et conserve les rapports. L’interface ne peut appliquer qu’un candidat confirmé dont l’empreinte correspond exactement au bilan courant.

## 8. Interface, données et limites de preuve

Le thème V2 fournit une palette sombre, texte clair, turquoise `#42D9CB` et alternative ambre `#FFB454`. Les sphères restent non éclairées ; ombre, bloom, flou et repères de trajectoire ne doivent pas changer la lisibilité de la zone mesurée. Les annotations des planches, anneaux d’amplitude, numéros de slot et exemples de résultats ne sont pas des contrôles ou scores de gameplay.

Le contrôleur utilise le profil exact et le namespace V2. `V2Store` sépare enveloppe de stockage, payload, versions et hash AIM-CANON-1, conserve rapports immuables et remplace profil/état avec protection de sauvegarde. Le profil historique peut être lu pour importer les réglages compatibles ; les rapports historiques restent en lecture séparée. Fichier incohérent, conflit ou sauvegarde refusée doivent être visibles et préserver la donnée d’origine.

`project.godot` annonce 1.0.0 et pointe vers `MainV2.tscn`. `tools/export_windows.sh` importe, teste, exporte le PE x86-64 avec PCK embarqué et exécute les smokes historiques et V2 dans ce pack hors du checkout. `tools/v2_visual_smoke.sh` capture la scène native ; le packager refuse des sources modifiées après capture. Les archives `AimLocal-1.0.0-windows-x64.zip` et `AimLocal-1.0.0-visuels.zip` sont accompagnées de SHA-256. Le [plan de réception](TEST_PLAN_V2.md) consigne les exécutions réelles : un pack ouvert par Godot Linux ne vaut pas un lancement Windows, et des horloges CAL simulées ne remplacent pas deux journées humaines.

Les références Python, l’Atlas, les bots et les tests natifs décrivent des comportements logiciels. Ils ne certifient ni polling USB, scanout, raw input Windows, performance GPU, confort humain ni transfert à un FPS. Les [essais restants](TEST_PLAN_V2.md) doivent garder leur résultat réel, leur configuration et leur portée ; aucune démonstration synthétique n’est une mesure utilisateur.
