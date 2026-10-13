# AIM/LOCAL — Exercices, mesures et détermination de la sensibilité

**Version décrite :** application 0.9.0, Godot 4.7.2 et GDScript.

**Référence du code :** commit `68b111699409972e7799994969ef5e90983c7277`.

**Rédaction :** 12 octobre 2026, Europe/Paris.

**Nature :** description de l’implémentation existante, pas cahier des charges de fonctionnalités futures.

Ce document explique ce que le joueur fait, ce que le logiciel mesure et comment les modules produisent ces résultats. Il couvre les **18 exercices effectivement disponibles**, la routine en trois étapes et la calibration publique en **25 essais**. Les 55 exercices envisagés dans [SPECIFICATION.md](SPECIFICATION.md) ne sont pas tous implémentés.

« Meilleure sensibilité » désigne ici **le réglage retenu par la recherche progressive à partir des performances observées**. Le programme fournit une valeur précise, réellement testée, à appliquer. Il ne démontre pas que cette valeur est un optimum universel, indépendant du jour, de la fatigue, de l’exercice ou du FPS utilisé ensuite. La différence entre ces deux affirmations est détaillée dans la partie calibration.

## Sommaire

1. [Architecture et vocabulaire](#architecture)
2. [Règles communes des exercices](#regles)
3. [Catalogue détaillé des 18 exercices](#catalogue)
4. [Trajectoires et variations de vitesse](#trajectoires)
5. [Mesures et formules de score](#mesures)
6. [Recherche progressive de sensibilité](#calibration)
7. [Sauvegarde, reprise et application](#sauvegarde)
8. [Conversions entre jeux](#conversion)
9. [Suivi de progression](#progression)
10. [Tests, limites et maintenance](#maintenance)

<a id="architecture"></a>

## 1. Architecture et vocabulaire

### 1.1 Une définition, un moteur et plusieurs présentations

Un exercice n’est pas une scène indépendante avec son propre calcul de score. Il est décrit par des données puis exécuté par un moteur commun :

```text
content/scenarios/*.tres
        ↓
ScenarioDefinition : paramètres et validation
        ↓
ScenarioCatalog : difficulté historique ou difficulté courante
        ↓
ScenarioEngine : apparitions, mouvement, collisions, mesures
        ├── TargetPool : sphères rendues dans l’arène
        ├── ScenarioPreview : démonstration du même exercice
        └── result() : rapport de séance
                    ↓
             ScoringService
                    ↓
             LocalStore / ProgressService
```

La calibration ajoute `ProgressiveCalibrationService`, qui choisit **le prochain réglage de souris**, pas une nouvelle physique de cible. `main.gd` orchestre préparation, séance, pause, résultat, sauvegarde et passage suivant.

| Fichier | Responsabilité et principaux points d’entrée |
|---|---|
| [scenario_definition.gd](../scripts/training/scenario_definition.gd) | Resource typée ; `validate()`, `fingerprint()`, `fits_view()` |
| [scenario_catalog.gd](../scripts/training/scenario_catalog.gd) | `find()`, `find_lifecycle()`, `find_practice()`, `resolve()` |
| [scenario_engine.gd](../scripts/training/scenario_engine.gd) | `start()`, `spawn_target()`, `target_geometry()`, `advance_to()`, `shoot()`, `result()` |
| [tracking_rhythm.gd](../scripts/training/tracking_rhythm.gd) | Construction des programmes de vitesse et intégrales analytiques |
| [aim_geometry.gd](../scripts/training/aim_geometry.gd) | Directions, erreur angulaire, intersection rayon/sphère et projection |
| [target_pool.gd](../scripts/training/target_pool.gd) | Mise à jour des six instances de sphères au maximum |
| [aim_camera.gd](../scripts/input/aim_camera.gd) | Conversion des counts souris en rotation, sans facteur de temps |
| [aim_timeline.gd](../scripts/input/aim_timeline.gd) | Historique circulaire horodaté des angles pour les mesures |
| [session_clock.gd](../scripts/core/session_clock.gd) | Temps actif monotone, hors pause |
| [scoring_service.gd](../scripts/statistics/scoring_service.gd) | Utilité, score, validation et clé de comparaison |
| [progressive_calibration_service.gd](../scripts/sensitivity/progressive_calibration_service.gd) | Choix adaptatif de cinq sensibilités par activité et recommandation |
| [sensitivity_service.gd](../scripts/sensitivity/sensitivity_service.gd) | DPI, cm/360°, degrés/count et sensibilité numérique |
| [game_profile_service.gd](../scripts/sensitivity/game_profile_service.gd) | Import d’un réglage de jeu et provenance du coefficient |
| [local_store.gd](../scripts/persistence/local_store.gd) | Rapports, checkpoints, bilans, archives et exports |
| [progress_service.gd](../scripts/statistics/progress_service.gd) | Regroupement des séances réellement comparables |
| [main.gd](../scripts/core/main.gd) | Contrôleur des états et transactions entre modules |
| [scenario_copy.gd](../scripts/ui/scenario_copy.gd) | Titres et consignes publiques, séparés des ressources historiques |
| [scenario_preview.gd](../scripts/ui/scenario_preview.gd) | Moteur de démonstration séparé, sans résultats ajoutés à l’historique |

### 1.2 Les unités à ne pas confondre

- **DPI déclarés :** résolution choisie dans le logiciel de la souris ; AIM/LOCAL ne la détecte ni ne la modifie matériellement.
- **Count :** unité de déplacement reçue via un événement souris. Ce n’est pas une mesure de centimètres faite par l’application.
- **Degrés/count :** rotation de caméra produite par un count.
- **cm/360° :** déplacement physique théorique nécessaire pour un tour complet, calculé avec les DPI déclarés.
- **Diamètre angulaire :** taille apparente d’une cible, en degrés, pas diamètre de son mesh en mètres.
- **Distance :** profondeur en mètres depuis l’origine de visée ; elle sert aussi à construire le rayon physique de la sphère.
- **Cadence de mouvement :** progression dans la trajectoire ; les rampes et virages peuvent rendre la vitesse réelle inférieure à cette cadence.
- **Utilité :** performance non arrondie utilisée par la calibration. Le score affiché en est une transformation.

### 1.3 Les trois générations de définitions

Les fichiers `.tres` sont des **références historiques**, pas directement la totalité des règles courantes.

| Accès | Définition retournée | Utilisation |
|---|---|---|
| `ScenarioCatalog.find(id)` | Base r3, r4 ou r5 selon l’exercice | Historique et calibration protocole 4 |
| `find_lifecycle(id)` | Variante r6 de la 0.8, avec durée de vie | Historique et calibration protocole 5 |
| `find_practice(id)` | Clic/transitions r6 ; suivi r7 | Pratique actuelle et calibration protocole 6 |
| `resolve(id, fingerprint)` | Génération correspondant à l’empreinte | Lecture d’un rapport sans changer sa difficulté |

`lifecycle_definitions()` duplique et met en cache les bases. `practice_definitions()` conserve les onze variantes de clic/transitions et duplique seulement les sept suivis pour ajouter le rythme r7. `ScenarioEngine.start()` duplique ensuite la définition reçue pour la séance.

Cette séparation évite qu’un ancien parcours interrompu reprenne avec des cibles plus rapides ou un score différent. Certaines instructions contenues dans les `.tres` décrivent donc intentionnellement l’ancienne version : la consigne courante provient de `ScenarioCopy`.

<a id="regles"></a>

## 2. Règles communes des exercices

### 2.1 Position du joueur et durée d’une séance

La caméra est placée à **1,6 m de hauteur**. Le joueur tourne la caméra mais ne se déplace pas dans l’arène. Les exercices ne simulent pas le déplacement d’un personnage, les dégâts, l’ADS ou une trajectoire balistique de balle.

La pratique autonome propose 15, 30 ou 60 secondes. La calibration et la routine utilisent 45 ou 60 secondes. Le moteur accepte techniquement une durée positive jusqu’à 120 secondes ; cette limite interne n’est pas la liste des choix visibles.

La préparation affiche **3, 2, 1**, avec retour sonore, puis GO. Un moteur distinct montre les cibles à âge zéro. Au démarrage mesuré, le moteur de séance reçoit la même définition et la même graine. Les mouvements de préparation ne contribuent pas au score.

Si la caméra a été tournée au point de sortir la zone d’exercice du champ, le départ attend un réalignement volontaire. Il n’y a ni rotation automatique de caméra, ni suppression de counts souris pour forcer la bonne orientation.

### 2.2 Fidélité du mouvement de souris

Le contrôleur lit `InputEventMouseMotion.screen_relative`. `AimCamera.apply_mouse_counts()` applique :

```text
yaw -= déplacement_horizontal_counts × degrés_par_count
pitch -= déplacement_vertical_counts × degrés_par_count × signe_vertical
```

Le pitch est borné à −89°/+89°. Le yaw interne peut continuer au-delà d’un tour ; la rotation affichée est repliée. Aucun multiplicateur de delta temporel, lissage ou accélération n’est ajouté à la souris.

La préférence d’accumulation d’input est transmise à Godot. Les événements reçus peuvent déjà être regroupés par le moteur ou le système. Leur horodatage est celui de la réception applicative, pas celui de chaque paquet HID natif. La stabilité d’un replay logiciel ne constitue donc pas une certification matérielle à 8 000 Hz.

### 2.3 Taille visible et hitbox

Pour une cible de diamètre angulaire `diametre_deg`, située à `distance_m` :

```text
rayon_m = distance_m × sin(diametre_deg / 2)
```

Le sinus est évalué après conversion en radians. Le centre est la direction de cible multipliée par sa distance, translatée à l’origine caméra dans le rendu.

`target_geometry()` fournit direction, distance, diamètre, centre relatif et rayon. Le rendu, les impacts, le suivi et les aperçus utilisent cette même géométrie. Une taille affichée ne doit pas être augmentée indépendamment de la hitbox pour embellir une démonstration.

Les enveloppes sont validées pour rester au-dessus du sol, devant le plan proche et dans le champ nominal. Il s’agit d’une simulation géométrique analytique, pas d’un objet déplacé par un moteur de rigid-body ou une force physique.

### 2.4 Apparitions aléatoires mais reproductibles

Chaque pratique ou relance reçoit une nouvelle graine, enregistrée dans son rapport. Avec la même définition, la même graine et les mêmes actions aux mêmes instants, les apparitions sont reproductibles.

Dans les dispositions usuelles, le moteur propose des angles aléatoires, vérifie la transition et la séparation avec les autres cibles, puis accepte une proposition. Il borne les essais à 128 : une impossibilité de placement n’entraîne pas une boucle infinie.

Les multicibles statiques r6 utilisent `scatter_spawn_angles_deg()` : jusqu’à 128 propositions, puis une réserve de huit positions validée par la définition. Cette réserve est un secours lorsque les propositions libres sont refusées ; ce n’est pas la grille normale de C03.

Une séparation entre centres d’au moins `maximum_angular_diameter_deg() × 1,7` est utilisée dans les contrôles de chevauchement concernés. Les contraintes de transition et de réserve sont également prises en compte.

**Nuance importante :** la graine ne suffit pas à rejouer une séance humaine exacte, car les fichiers sauvegardent des mesures agrégées, pas toute la timeline d’input. Pour les exercices de clic, les touches et expirations changent aussi l’ordre des remplacements et des tirages RNG. Deux sensibilités avec la même graine commencent dans les mêmes conditions, mais ne garantissent pas les mêmes positions à chaque seconde si les joueurs touchent des cibles différentes.

### 2.5 Durée de vie et réduction de taille

À chaque apparition, le moteur tire une durée entre **85 % et 115 %** de la durée nominale de l’exercice. Il enregistre `born_s`, `lifetime_s` et `expires_s`.

```text
fraction_age = clamp((temps_actif − born_s) / lifetime_s, 0, 1)
facteur_taille = 1 + (ratio_final − 1) × fraction_age
diametre_courant = diametre_de_base_courant × facteur_taille
```

Le rétrécissement est linéaire dans le temps actif. Le diamètre de base peut lui-même dépendre de la perspective dans T10. Le ratio final est calculé depuis le plus petit diamètre de base déclaré :

```text
clic/transitions : clamp(1,5° / diametre_minimal, 0,35, 0,75)
suivi           : clamp(0,55° / diametre_minimal, 0,65, 0,85)
```

Ces valeurs ne garantissent pas un diamètre final universel de 1,5° ou 0,55° : les bornes du ratio priment. Par exemple, C05 reste un exercice avancé avec une taille finale de 0,525° ; C03 termine à 1,68°.

À l’échéance, la cible disparaît avec une **taille encore positive**, puis une nouvelle apparition la remplace immédiatement. Elle n’attend pas d’être touchée et ne se réduit pas jusqu’à un point nul impossible à viser.

Les échéances de plusieurs cibles sont traitées globalement par ordre chronologique, puis par indice en cas d’égalité. Cela maintient le même ordre de tirages RNG lorsqu’un saut de temps remplace plusieurs cibles.

- En clic/transitions, une expiration est un oubli qui pénalise le score.
- En suivi, le remplacement programmé impose une nouvelle acquisition ; il n’est pas un tir raté.
- Pendant une pause, le temps actif, le mouvement et le vieillissement sont suspendus.
- Une pause de **mouvement** prévue par le rythme de suivi n’est pas une pause de séance : la cible continue à vieillir et rétrécir.

### 2.6 Traitement d’un tir

`ScenarioEngine.shoot()` refuse les tirs en pause, après fin ou dans la famille `tracking`. Pour le clic :

1. Avancer la simulation à l’instant du tir, expirations comprises.
2. Refuser un tir après la fin de séance.
3. Ajouter un tir réel à `shots`.
4. Tester le rayon de visée contre chaque sphère courante.
5. Choisir la sphère intersectée la plus proche en profondeur.
6. Enregistrer erreur, tentative et, si impact, touche et acquisition.
7. Remplacer seulement la cible touchée.

Un clic exactement à l’échéance ne peut pas toucher rétroactivement la cible disparue. Un seul tir ne détruit pas toutes les sphères éventuellement alignées. Il n’y a pas de déplacement physique d’une balle ni de retard de trajet à compenser.

Les armes, sons, flashs, recul du viewmodel et hitmarker sont des retours de présentation. Ils ne modifient ni la caméra de visée ni la hitbox. Le tir sonore continu du suivi est facultatif et n’ajoute pas de points.

<a id="catalogue"></a>

## 3. Catalogue détaillé des 18 exercices

### 3.1 Tableau de référence des pratiques courantes

Les angles H/V ci-dessous sont les **demi-enveloppes déclarées**, pas systématiquement l’amplitude réelle du mouvement. Les suivis périodiques utilisent 90 % de leur enveloppe active ; S02 et D02 ont leurs propres facteurs décrits dans leurs fiches.

Le diamètre est celui de base avant vieillissement ; la durée est celle d’une **apparition**, pas celle de l’ensemble de la séance. `Réf.` est la cadence de normalisation du score de clic, en touches/s, et non une condition de réussite imposée au joueur.

| ID | Nom public | Famille | Rév. | Cibles | Diamètre de base | Distance | H/V | Vie nominale | Réf. |
|---|---|---|---:|---:|---|---|---|---|---|
| C01 | Cible unique | Clic | 6 | 1 | 3,2° | 4,5 m | ±14° / ±8° | 3 s | 2 |
| C02 | Micro-précision | Clic | 6 | 1 | 2,5° | 3 m | ±6° / ±4° | 3 s | 1,6 |
| C03 | Multicibles | Clic | 6 | 6 | 4,8° | 4 m | ±22° / ±13° | 4 s | 3 |
| C04 | Grands mouvements | Clic | 6 | 1 | 3,2° | 5 m | ±30° / ±12° | 3 s | 1,8 |
| C05 | Précision avancée | Clic | 6 | 6 | 0,7° | 7 m | ±16° / ±9° | 6 s | 2,4 |
| C07 | Visée verticale | Clic | 6 | 1 | 3° | 3 m | ±3° / ±20° | 3 s | 2 |
| D01 | Réflexes | Clic | 6 | 1 | Tiré entre 3° et 3,8° | 4 m | ±16° / ±9° | 1 s | 2 |
| D02 | Cible mobile | Clic | 6 | 1 | 3° | 3,5 m | ±16° / ±6° | 3 s | 1,8 |
| M01 | Flicks mixtes | Clic | 6 | 1 | Tiré entre 2,5° et 4,2° | 4 m | ±28° / ±12° | 3 s | 2 |
| S01 | De cible en cible | Switching | 6 | 4 | 3,4° | 4,5 m | ±24° / ±10° | 4 s | 2,8 |
| S02 | Transitions mobiles | Switching | 6 | 4 | 3,2° | Tirée entre 3,5 et 5,5 m | ±22° / ±12° | 5 s | 2,4 |
| T01 | Suivi horizontal | Suivi | 7 | 1 | 4° | 4 m | ±16° / ±2° | 10 s | — |
| T02 | Suivi vertical | Suivi | 7 | 1 | 3,6° | 3,5 m | ±2° / ±16° | 10 s | — |
| T03 | Suivi diagonal | Suivi | 7 | 1 | 3,4° | 4,5 m | ±16° / ±10° | 10 s | — |
| T04 | Suivi circulaire | Suivi | 7 | 1 | 3,4° | 5 m | ±15° / ±11° | 10 s | — |
| T05 | Suivi réactif | Suivi | 7 | 1 | 3,6° | 3 m | ±16° / ±2° | 10 s | — |
| T09 | Suivi avancé | Suivi | 7 | 1 | 0,9° | 8 m | ±8° / ±2° | 10 s | — |
| T10 | Suivi varié | Suivi | 7 | 1 | Perspective : 4° à 4 m avant vieillissement | 3 à 5 m | ±20° / ±12° | 10 s | — |

Sources : [ressources d’exercices](../content/scenarios/), valeurs par défaut de `ScenarioDefinition` et transformations de `ScenarioCatalog`. Les fiches suivantes emploient les règles courantes, pas seulement le texte de la ressource de base.

### 3.2 C01 — Cible unique

**Ce qu’il faut faire.** Déplacer le viseur sur une sphère immobile, cliquer, puis rejoindre la suivante. L’exercice travaille l’acquisition générale et la stabilisation avant le tir.

**Déroulement.** Une seule cible est active. Son centre est tiré dans l’enveloppe H/V ; une transition minimale de 4° est demandée par le placement statique. La sphère démarre à 3,2°, rétrécit vers 1,5° et expire après 2,55 à 3,45 s si elle n’est pas touchée. Un raté ne la remplace pas.

**Mesures utiles.** Touches/s, réussite incluant les oublis, tirs ratés, acquisition médiane/P95 et efficacité du trajet. Rechercher une cadence propre plutôt que beaucoup de clics hors cible.

**Implémentation.** [C01.tres](../content/scenarios/C01.tres), `spawn_target_geometry()` pour le placement générique statique, `shoot()` pour l’impact et le remplacement, score V2 normalisé par 2 touches/s.

### 3.3 C02 — Micro-précision

**Ce qu’il faut faire.** Effectuer de petites corrections près du centre, stabiliser la fin du geste puis cliquer. Ce n’est pas un exercice de cibles microscopiques.

**Déroulement.** Une cible de 2,5° dans une zone de ±6°/±4°, avec transition minimale de 3°. Son diamètre final est 1,5° ; durée 2,55–3,45 s. Les positions restent aléatoires dans la zone, pas une série de petits déplacements identiques.

**Mesures utiles.** Réussite, erreur angulaire au tir, temps d’acquisition et utilité non arrondie. Une sensibilité peut produire davantage de touches tout en perdant trop de précision : la formule pénalise ce compromis.

**Implémentation.** [C02.tres](../content/scenarios/C02.tres), même moteur statique que C01, référence 1,6 touche/s. **Première activité de calibration**, pour établir la première zone de réglages prometteurs.

### 3.4 C03 — Multicibles

**Ce qu’il faut faire.** Enchaîner des touches sur les six sphères en choisissant soi-même la prochaine cible. Il faut gérer acquisition, rythme et priorisation des cibles encore actives.

**Déroulement.** Six cibles de 4,8° dans une zone de 44° sur 26° au total. Elles ne sont pas limitées aux neuf nœuds d’une grille. Le placement respecte une transition de 5,5° pour la cible remplacée et la séparation avec les autres sphères. Rétrécissement vers 1,68°, vies indépendantes de 3,4–4,6 s.

Une cible laissée de côté finit par expirer et compte comme oubli. Le moteur remplace les cibles touchées ou expirées, sans remettre toutes les autres à taille initiale.

**Mesures utiles.** Cadence de touches, oublis, tirs ratés et réussite. L’acquisition d’une cible multicible inclut le temps pendant lequel d’autres cibles ont été traitées ; ce n’est pas une mesure pure du temps de réaction visuelle.

**Implémentation.** [C03.tres](../content/scenarios/C03.tres), `scatter_spawn_angles_deg()`, `scatter_candidate_is_safe()` et réserve de secours. Référence de score : 3 touches/s. `layout="grid"` existe dans le moteur, mais **C03 utilise `scatter`**.

### 3.5 C04 — Grands mouvements

**Ce qu’il faut faire.** Exécuter un grand déplacement de visée, freiner sur la cible et cliquer avec contrôle.

**Déroulement.** Une cible statique de 3,2° à 5 m, dans ±30°/±12°. Les positions acceptées doivent être à au moins 20° de la précédente. Le diamètre final reste 1,5° ; vie 2,55–3,45 s. La difficulté principale est le déplacement, pas une sphère minuscule.

**Mesures utiles.** Cadence pondérée par réussite, acquisition et efficacité du trajet. Les mesures ne classent pas directement un raté en « trop loin » ou « pas assez loin » : l’erreur enregistrée n’est pas un diagnostic signé d’overshoot.

**Implémentation.** [C04.tres](../content/scenarios/C04.tres), rejet des propositions trop proches dans `spawn_target_geometry()`, référence 1,8 touche/s. **Deuxième activité de calibration**, à l’intérieur de la zone conservée après C02.

### 3.6 C05 — Précision avancée

**Ce qu’il faut faire.** Toucher six petites sphères en privilégiant le centrage précis et des transitions propres. Cet exercice est avancé et facultatif.

**Déroulement.** Six cibles de 0,7° à 7 m dans ±16°/±9°. Leur vie est plus longue : 5,1–6,9 s. Le ratio final plafonné à 0,75 donne 0,525°, pas 1,5°. Le placement courant passe par le générateur multicible statique avec réserve.

**Mesures utiles.** Réussite, tirs ratés, oublis et erreur au tir. Un faible score doit être interprété avec cette petite taille, et non comparé directement à C03.

**Implémentation.** [C05.tres](../content/scenarios/C05.tres), `active_targets=6`, diamètre petit, référence 2,4 touches/s. L’exercice n’appartient pas aux cinq activités de calibration publique.

### 3.7 C07 — Visée verticale

**Ce qu’il faut faire.** Monter ou descendre le viseur, stabiliser à la bonne hauteur, puis tirer.

**Déroulement.** Une cible de 3° à 3 m, avec ±3° horizontalement et ±20° verticalement. C’est une zone **à dominante verticale**, pas une colonne mathématique à x constant. La transition statique minimale est 10°. Diamètre final 1,5°, vie 2,55–3,45 s.

**Mesures utiles.** Acquisition, réussite, erreur de tir et trajet. La conversion souris est la même sur les deux axes, sauf inversion verticale explicitement choisie.

**Implémentation.** [C07.tres](../content/scenarios/C07.tres), placement statique générique et validation de la silhouette au-dessus du sol. Référence : 2 touches/s.

### 3.8 D01 — Réflexes

**Ce qu’il faut faire.** Repérer la cible qui vient d’apparaître et la toucher avant sa disparition.

**Déroulement.** Diamètre initial tiré entre 3° et 3,8°, à 4 m, transition statique minimale 4,5°. La vie est courte : 0,85–1,15 s. Le ratio courant vaut 0,5, donc la taille finale dépend du diamètre initial : 1,5–1,9°.

**Distinction historique.** La base r4 réduisait le diamètre vers 3°. La variante r6 met `diameter_motion` à `fixed` pour le diamètre de base, puis applique le rétrécissement commun de cycle de vie. Les deux réductions ne sont pas cumulées.

**Mesures utiles.** Touches, expirations et acquisition. L’acquisition comprend perception, décision, mouvement et clic ; elle ne prouve pas un temps de réaction sensoriel isolé.

**Implémentation.** [D01.tres](../content/scenarios/D01.tres), tirage du diamètre, transformation dans `lifecycle_definitions()`, `expire_targets()` et score V2, référence 2 touches/s.

### 3.9 D02 — Cible mobile

**Ce qu’il faut faire.** Rejoindre une sphère dont le déplacement horizontal change de destination puis cliquer au bon instant.

**Déroulement.** Une cible de 3° à 3,5 m, vie 2,55–3,45 s, diamètre final 1,5°. Le mouvement est `reactive`, pas la sinusoïde de T01. Des offsets horizontaux sont préconstruits à partir de la graine et reliés par smoothstep.

Avec une amplitude d’offset de `16° × 0,45 = 7,2°`, l’intervalle entre destinations est `3 × 7,2 / 14 + 0,24`, soit environ 1,783 s. Le centre d’ancrage est lui aussi tiré dans une enveloppe réduite. `turn_duration_s=0,24` participe à cet intervalle ; ce n’est pas une inversion instantanée tous les 240 ms.

**Mesures utiles.** Réussite, cadence et erreur au tir. Le clic utilise la position réelle à cet instant, pas la position d’apparition.

**Implémentation.** [D02.tres](../content/scenarios/D02.tres), `build_reactive_path()`, `reactive_offset_deg()` et `target_direction()`. Paramètre de vitesse de base 14°/s ; référence 1,8 touche/s. Le nouveau `TrackingRhythm` ne s’applique pas à D02, qui appartient au clic.

### 3.10 M01 — Gestes mixtes

**Ce qu’il faut faire.** Alterner petites corrections et grands déplacements, sans connaître d’avance la catégorie suivante.

**Déroulement.** Une seule cible statique, diamètre initial tiré entre 2,5° et 4,2°, à 4 m. À chaque apparition, le moteur choisit une transition courte avec une probabilité de 50 % : 2,5–6°. Sinon, il recherche une transition de 20–44°. Les propositions restent dans ±28°/±12°.

Les petites transitions sont construites autour de la direction précédente, avec angle et orientation tirés. Les grandes sont proposées dans l’enveloppe puis filtrées. Après 128 refus, un secours géométrique par interpolation sphérique construit une transition bornée ; il ne transforme pas l’exercice en alternance imposée petit/grand.

Le facteur de taille final vaut 0,6 : selon le tirage initial, la taille finale va de 1,5° à 2,52°. Vie 2,55–3,45 s.

**Mesures utiles.** Cadence, réussite, acquisition et trajet. Le rapport de séance standard n’expose pas un score séparé par catégorie de transition : `transition_kind` est un état interne de cible.

**Implémentation.** [M01.tres](../content/scenarios/M01.tres), `spawn_pattern="mixed"`, `spawn_mixed_target()`, référence 2 touches/s. Première étape de la routine complète, mais pas activité de calibration.

### 3.11 S01 — Transitions

**Ce qu’il faut faire.** Passer entre quatre cibles statiques et les toucher successivement. Le choix de la prochaine cible appartient au joueur.

**Déroulement.** Quatre cibles de 3,4° à 4,5 m, dans ±24°/±10°. Le générateur statique multicible évite les chevauchements et contrôle une transition minimale de 6° pour une nouvelle apparition. Diamètre final 1,5°, vies 3,4–4,6 s.

**Mesures utiles.** Cadence, réussite et durée entre touches. Pour la famille `switching`, l’acquisition est calculée depuis la touche précédente, contrairement au clic simple où elle part de la naissance de la cible. Le premier intervalle démarre au temps zéro.

**Implémentation.** [S01.tres](../content/scenarios/S01.tres), `scatter_spawn_angles_deg()` et branche `switching` de `shoot()`. Référence 2,8 touches/s. **Troisième activité de calibration**.

### 3.12 S02 — Transitions mobiles

**Ce qu’il faut faire.** Passer entre quatre sphères qui bougent horizontalement, avec des profondeurs différentes.

**Déroulement.** Quatre couloirs à pitches −9°, −3°, +3° et +9°. Chaque apparition tire sa profondeur entre 3,5 et 5,5 m. Le diamètre de base reste 3,2° quelle que soit la profondeur : le rayon physique s’adapte, puis diminue avec le vieillissement.

Le mouvement horizontal combine un ancrage tiré dans ±9,9° et une sinusoïde d’amplitude 9,9°. Le centre peut donc parcourir environ ±19,8° dans l’enveloppe déclarée ±22°. Le paramètre de vitesse vaut 16°/s. Les vies sont de 4,25–5,75 s, diamètre final 1,5°.

**Mesures utiles.** Transitions entre touches, précision, cadence et oublis. L’écart de profondeur ne crée pas un projectile plus lent : les impacts restent immédiats.

**Implémentation.** [S02.tres](../content/scenarios/S02.tres), `layout="lanes"`, tirage de `distance_m`, branche horizontale de `target_direction()` et score V2, référence 2,4 touches/s. Troisième étape de la routine. **Pas de rythme r7** : S02 n’est pas un exercice de suivi.

### 3.13 T01 — Suivi horizontal

**Ce qu’il faut faire.** Garder le viseur sur une cible qui se déplace de gauche à droite, sans devoir tirer.

**Déroulement.** Une cible de 4° à 4 m. Mouvement horizontal centré sur la zone, amplitude ±14,4°, pitch nul. Le programme r7 accélère, freine, s’arrête puis repart dans l’autre sens le long de cette trajectoire.

Cadence basse 5,4°/s, plafond 16,2°/s. Vie 8,5–11,5 s, diamètre final 2,6°. Au remplacement, une phase séparée de l’ancienne position est recherchée, avec secours de phase opposée si nécessaire.

**Mesures utiles.** Fraction et secondes sur cible, erreur moyenne/P95 et réacquisition. Le pourcentage ne dépend pas du nombre de clics.

**Implémentation.** [T01.tres](../content/scenarios/T01.tres), `motion="horizontal"`, `TrackingRhythm`, `integrate_sample()`. **Quatrième activité de calibration**.

### 3.14 T02 — Suivi vertical

**Ce qu’il faut faire.** Accompagner les montées et descentes, les ralentissements et les reprises de la cible.

**Déroulement.** Une cible de 3,6° à 3,5 m, yaw nul et amplitude de pitch ±14,4°. Cadence basse 5,4°/s et plafond 16,2°/s. Le rythme reste sur l’axe vertical ; il ne part pas latéralement pour ajouter artificiellement de la difficulté. Diamètre final 2,34°, vie 8,5–11,5 s.

**Mesures utiles.** Suivi réel dans le temps, erreur angulaire et réacquisition après remplacement ou perte du contact.

**Implémentation.** [T02.tres](../content/scenarios/T02.tres), branche verticale de `target_direction()`, mêmes cycles et intégration que T01. Hors calibration publique.

### 3.15 T03 — Suivi diagonal

**Ce qu’il faut faire.** Coordonner simultanément les deux axes du viseur.

**Déroulement.** Une cible de 3,4° à 4,5 m. Amplitudes yaw/pitch ±14,4°/±9°. Les deux axes emploient la même phase, ce qui forme un aller-retour diagonal cohérent, pas deux sinusoïdes indépendantes.

La phase est normalisée par la norme des deux amplitudes pour ne pas additionner abusivement les vitesses d’axe. Cadence basse 7,2°/s, plafond 21,6°/s, diamètre final 2,21°, vie 8,5–11,5 s.

**Mesures utiles.** Pourcentage sur cible et erreur de suivi. Le code ne fournit pas un diagnostic séparé « horizontal bon, vertical mauvais » : l’erreur courante est angulaire globale.

**Implémentation.** [T03.tres](../content/scenarios/T03.tres), branche diagonale de `target_direction()` et normalisation de l’amplitude.

### 3.16 T04 — Suivi circulaire

**Ce qu’il faut faire.** Garder le viseur sur une cible qui tourne et change de rythme, sans corrections brusques inutiles.

**Déroulement.** Une cible de 3,4° à 5 m. Le mouvement associe un cosinus en yaw et un sinus en pitch, avec amplitudes 13,5° et 9,9°. Il s’agit donc d’une **ellipse dans les coordonnées angulaires**, pas d’un cercle de rayon unique.

Cadence basse 8,1°/s, plafond 24,3°/s. Les arrêts/reprises peuvent inverser le sens de parcours sans saut de position. Diamètre final 2,21°, vie 8,5–11,5 s.

**Mesures utiles.** Temps sur cible, erreur et réacquisition. Le plafond est une borne de vitesse angulaire ; la vitesse instantanée n’est pas constante autour de l’ellipse.

**Implémentation.** [T04.tres](../content/scenarios/T04.tres), branche `circle`, normalisation par la plus grande amplitude et horloge signée r7.

### 3.17 T05 — Suivi réactif

**Ce qu’il faut faire.** Suivre les traversées et reprendre proprement après les demi-tours ou les arrêts.

**Déroulement.** Une cible de 3,6° à 3 m, amplitude horizontale ±14,4°. La forme `strafe` contient des portions de traversée et des virages lissés par segments quadratiques.

La durée de virage de base, 0,16 s, est exprimée dans l’horloge de la trajectoire. Le rythme r7 accélère ou ralentit cette horloge : **ce n’est plus un demi-tour réel fixé à 160 ms dans toutes les circonstances**. Cadence basse 11,7°/s, plafond 35,1°/s ; diamètre final 2,34°, vie 8,5–11,5 s.

**Mesures utiles.** Temps sur cible et réacquisition. Le rapport agrège les pertes de contact ; il ne produit pas une note isolée pour chaque demi-tour.

**Implémentation.** [T05.tres](../content/scenarios/T05.tres), `strafe_offset_deg()`, `motion_time_s()` et `TrackingRhythm`. **Cinquième et dernière activité de calibration** ; son meilleur essai fournit la valeur finale retenue.

### 3.18 T09 — Suivi précis avancé

**Ce qu’il faut faire.** Maintenir des micro-corrections sur une petite cible, sans confondre cette difficulté avec un test pour débutant.

**Déroulement.** Une sphère de 0,9° à 8 m, amplitude horizontale ±7,2°. Cadence basse 2,7°/s, plafond 8,1°/s. Malgré sa vitesse modérée, sa petite taille exige un centrage fin. Diamètre final 0,585°, vie 8,5–11,5 s.

**Mesures utiles.** Temps sur cible et erreur angulaire à taille/difficulté constantes. Un score moindre que T01 ne suffit pas à conclure que la sensibilité est mauvaise.

**Implémentation.** [T09.tres](../content/scenarios/T09.tres), même forme horizontale que T01 mais paramètres avancés. Hors calibration publique.

### 3.19 T10 — Suivi multidirectionnel

**Ce qu’il faut faire.** Suivre une cible qui combine mouvements horizontaux, verticaux, diagonaux et en profondeur.

**Déroulement.** Le générateur stocke des poses `(yaw, pitch, distance)`. Il mélange les quatre catégories de déplacement dans des groupes de quatre, puis choisit des destinations dans l’autre moitié de l’axe concerné, avec une marge centrale. Ce n’est pas une marche aléatoire bruitée à chaque frame.

Les poses restent dans ±20°/±12° et entre 3 et 5 m. Chaque segment est interpolé par smoothstep. Sa durée de base est le maximum de 0,6 s, `1,5 × longueur_angulaire / 18` et `1,5 × déplacement_profondeur / 1,2`. Le facteur 1,5 tient compte du pic de dérivée du smoothstep.

Le rythme r7 parcourt ces segments plus ou moins vite, peut les reprendre en sens inverse, et réfléchit l’horloge au début du parcours. Cadence basse 8,1°/s, plafond angulaire 24,3°/s ; plafond en profondeur 1,62 m/s après modulation.

**Taille et perspective.** Le rayon physique de référence correspond à 4° à 4 m. Avant vieillissement, le diamètre apparent est calculé par `2 × asin(rayon_reference / distance)`, soit environ 3,20° à 5 m et 5,33° à 3 m. Les bornes déclarées 3°/5,5° sont une enveloppe de validation, pas un tirage de diamètre. Le facteur de cycle réduit ensuite ce diamètre jusqu’à 65 % : le rayon physique courant diminue lui aussi. Il serait donc faux d’annoncer un rayon physique constant pendant toute la variante actuelle.

Vie 8,5–11,5 s. La nouvelle cible repart à taille initiale, dans une autre région, avec un parcours et un programme propres.

**Mesures utiles.** Temps sur cible, erreur et réacquisition à travers les variations de profondeur. Aucune métrique ne mesure ici le déplacement du joueur, qui reste immobile.

**Implémentation.** [T10.tres](../content/scenarios/T10.tres), `spawn_waypoint_target()`, `opposite_waypoint_value()`, `waypoint_pose()`, `target_distance_m()` et diamètre `perspective`. Deuxième étape de la routine, hors calibration publique.

### 3.20 Routine complète : M01 → T10 → S02

[TrainingRoutineService](../scripts/training/training_routine_service.gd) construit trois étapes de 45 ou 60 s chacune : gestes mixtes, suivi multidirectionnel et transitions mobiles. Cela représente 135 ou 180 secondes mesurées, auxquelles s’ajoutent préparation et pauses.

Le même réglage de souris est utilisé. Les graines sont renouvelées pour la pratique ; chaque étape possède un rapport et un score propre. Il n’y a **pas de score global** mélangeant cadence de clic et ratio de suivi, ni de recherche de sensibilité cachée dans cette routine.

<a id="trajectoires"></a>

## 4. Trajectoires et variations de vitesse

### 4.1 Formes de base

Pour les suivis périodiques, l’amplitude active vaut 90 % de l’enveloppe déclarée. La phase est :

```text
phase = phase_initiale + vitesse_de_base / amplitude_normalisee × temps_virtuel
```

| Mouvement | Yaw | Pitch | Normalisation |
|---|---|---|---|
| Horizontal | amplitude_H × sin(phase) | 0 | amplitude_H |
| Vertical | 0 | amplitude_V × sin(phase) | amplitude_V |
| Diagonal | amplitude_H × sin(phase) | amplitude_V × sin(phase) | norme des deux amplitudes |
| Cercle/ellipse | amplitude_H × cos(phase) | amplitude_V × sin(phase) | maximum des amplitudes |

Le strafe utilise sa fonction quadratique et périodique dédiée. Les waypoints utilisent une recherche binaire dans les frontières de segments, puis une interpolation des poses.

### 4.2 Programme r7 préconstruit

`TrackingRhythm.build()` utilise un RNG isolé, initialisé avec :

```text
graine_du_rythme = graine_de_seance XOR (identite_de_cible × 104729)
```

Il préconstruit quatre tableaux : `times_s`, `speeds_deg_s`, `distances_deg` et `kinds`. Ils servent ensuite à des lectures sans nouveau tirage RNG.

Un cycle de programme contient :

1. Un signe initial aléatoire et une cadence de croisière.
2. Un maintien de 0,45–0,9 s.
3. Deux bandes, rapide puis lente ou lente puis rapide, dans un ordre tiré.
4. Pour chaque bande : une rampe et un maintien de 0,45–0,9 s.
5. Un freinage vers zéro.
6. Une pause de 0,18–0,35 s.
7. Une reprise avec le signe inverse.

Le générateur répète cette structure jusqu’à couvrir la durée de vie, éventuellement en construisant une fin de programme qui ne sera pas jouée après l’expiration.

Les paramètres courants sont :

```text
cadence_min = 0,45 × vitesse_de_base
cadence_max = 1,35 × vitesse_de_base
acceleration_de_rampe_max = 4 × cadence_max
```

La bande rapide est tirée entre 82 % du plafond et le plafond, sans passer sous le minimum. La bande lente est tirée entre le minimum et `min(1,3 × minimum, plafond)`. La croisière va du minimum à `max(minimum, 0,78 × plafond)`.

Les rampes demandées durent 0,55–0,95 s pour accélérer, 0,2–0,38 s pour freiner vers une autre bande, 0,22–0,38 s pour arrêter et 0,3–0,55 s pour repartir. Leur durée peut être **allongée** pour respecter la pente maximale.

### 4.3 Intégrale analytique et continuité

Pour une rampe de durée `duree_s`, avec `fraction = temps_local / duree_s` :

```text
smoothstep(fraction) = 3 × fraction² − 2 × fraction³
vitesse = vitesse_depart + (vitesse_fin − vitesse_depart) × smoothstep(fraction)

deplacement = deplacement_depart
             + vitesse_depart × temps_local
             + (vitesse_fin − vitesse_depart) × duree_s
               × (fraction³ − 0,5 × fraction⁴)
```

La durée minimale de rampe est `1,5 × abs(vitesse_fin − vitesse_depart) / acceleration_max`. Les positions et vitesses restent continues aux frontières. Le plafond de pente concerne la **cadence signée**, pas l’accélération vectorielle complète d’une cible sur une courbe.

`motion_time_s()` divise le déplacement signé par la vitesse de base. Cette horloge virtuelle alimente les formes de trajectoire. Pour T10, sa valeur absolue réfléchit le parcours à son origine lissée.

Il n’y a pas d’accumulation `position += vitesse × delta_frame` qui changerait de résultat selon le FPS. Une recherche binaire et une formule donnent l’état à l’instant demandé. La cadence basse n’interdit pas une vitesse réelle plus faible dans les virages ou pendant les rampes vers une pause.

<a id="mesures"></a>

## 5. Mesures et formules de score

### 5.1 Clic/transitions : compteurs et score V2

| Mesure | Définition |
|---|---|
| `shots` | Nombre de tirs réellement traités |
| `hits` | Nombre de cibles touchées |
| `misses` | `shots − hits` ; ne comprend pas les expirations |
| `targets_expired` | Nombre de remplacements causés par échéance |
| `failed_actions` | `shots − hits + targets_expired` |
| `accuracy_pct` | `100 × hits / shots`, ou valeur indisponible sans tir |
| `effective_accuracy_pct` | `100 × hits / (shots + expirations)`, indisponible sans tentative ni expiration |
| `hits_per_s` | Touches divisées par la durée active observée |

La **précision des tirs** et la **réussite incluant les oublis** répondent à des questions différentes. Une cible oubliée n’ajoute pas un tir fictif.

Pour les variantes temporelles de clic/transitions :

```text
reussite = touches / max(tirs + expirations, 1)
utilite = touches_par_seconde × reussite²
score_V2 = arrondi(1000 × utilite / cadence_de_reference)
```

Le carré pénalise les comportements où l’on tire très vite sans précision ou où l’on ignore de nombreuses cibles. Une expiration n’enlève pas un nombre fixe de points : elle augmente le dénominateur de réussite et réduit l’utilité.

**Exemple synthétique :** sur C01 pendant 60 s, 90 touches, 100 tirs et 10 expirations donnent 10 tirs ratés, 20 échecs combinés, 90 % de précision des tirs et environ 81,82 % de réussite. La cadence vaut 1,5 touche/s ; l’utilité vaut environ 1,0041 ; le score, normalisé par 2, vaut **502**.

Les scores de clic ne plafonnent pas arbitrairement à 1 000. La référence n’est ni un maximum physiologique ni un classement universel entre exercices.

### 5.2 Suivi : exposition et score V1

Le moteur échantillonne le suivi avec un pas logique de **1/240 s**. À chaque milieu d’intervalle, il lit la pose de caméra interpolée dans `AimTimeline` et la géométrie de cible. Le viseur est sur cible lorsque l’erreur angulaire est inférieure ou égale au demi-diamètre courant.

```text
ratio_sur_cible = temps_sur_cible / max(temps_expose, epsilon)
utilite = ratio_sur_cible
score_suivi = arrondi(1000 × ratio_sur_cible)
```

**Exemple synthétique :** 42 s réellement sur cible sur 60 s d’exposition donnent 70 % et un score de 700. Cliquer ou jouer un son continu ne modifie pas ce ratio.

Lorsqu’un tick traverse une expiration, `integrate_sample()` le scinde : mesurer l’ancienne cible avant l’échéance, remplacer, puis mesurer la nouvelle. Il n’y a pas de trou d’exposition ajouté pour améliorer artificiellement le score.

La formule reste V1 en r7, mais la difficulté et son empreinte changent. Un 700 en suivi r6 et un 700 en suivi r7 ne représentent pas des séances comparables pour établir un record commun.

### 5.3 Mesures complémentaires et interprétation

- **Acquisition médiane/P95 :** temps des touches réussies. Pour le clic, depuis la naissance ; pour switching, depuis la touche précédente. Les expirations ne deviennent pas des temps d’acquisition réussis.
- **Précision au premier tir :** proportion des premières tentatives attribuées à une cible qui réussissent. Un raté est attribué à la cible au centre angulaire le plus proche ; ce n’est pas une lecture de l’intention du joueur.
- **Erreur au tir médiane :** erreur au centre le plus proche, pas une distance signée de dépassement ni une marge au bord de la hitbox.
- **Erreur de suivi moyenne :** erreur angulaire intégrée, pondérée par le temps.
- **Erreur de suivi P95 :** histogramme temporel par cases de 0,1°, avec valeur issue de la borne supérieure de la case ; ce n’est pas une mesure continue à précision infinie.
- **Réacquisition médiane :** délai jusqu’au retour sur cible après perte du contact ou nouvelle apparition. Mesure issue du pas logique, pas horodatage matériel exact.
- **Efficacité du trajet :** pour les cibles statiques, rapport entre erreur initiale utile, diminuée du rayon angulaire courant, et trajet angulaire parcouru depuis l’apparition, borné entre 0 et 1. En multicibles, traiter d’autres cibles entre-temps influence ce rapport.
- **Samples :** les nombres d’échantillons accompagnent plusieurs métriques. Une médiane renvoyée à zéro sans échantillon n’est pas une preuve de réaction instantanée.
- **Performances :** nombre de frames, P95/P99 des frametimes et maximum. Le tampon de frametimes est borné à 4 096 entrées ; le maximum est suivi sur la séance.

Le moteur ne fournit pas de diagnostic médical, de reconnaissance automatique du DPI, de profil cognitif ou de classement « overshoot/undershoot » par axe. Une interprétation manuelle doit tenir compte de ce qui a réellement été enregistré.

### 5.4 Pourquoi utiliser l’utilité plutôt que le score arrondi

`ScoringService.utility()` conserve la performance non arrondie. Deux essais affichant le même score entier peuvent avoir une utilité différente. La calibration compare cette utilité **à l’intérieur de la même activité**, pas une somme de scores de familles différentes.

Les scores V1 historiques de clic utilisaient cadence × précision des tirs², sans la nouvelle pénalité d’expiration. Ils restent lisibles dans leur contexte d’origine ; le logiciel ne réécrit pas les anciennes mesures en V2.

La relecture JSON prévoit une tolérance extrêmement étroite autour d’un demi-point d’arrondi : au plus huit epsilon doubles relatifs, plafonnés à 0,000001 point. Cette protection numérique ne permet pas de modifier librement un score ni de certifier les fichiers locaux contre la triche.

<a id="calibration"></a>

## 6. Recherche progressive de sensibilité

### 6.1 Parcours effectivement exécuté

Le parcours public est `ProgressiveCalibrationService`, **protocole 6** :

```text
C02 : 5 sensibilités → zone retenue
  ↓
C04 : 5 sensibilités dans cette zone → zone affinée
  ↓
S01 : 5 sensibilités → transitions
  ↓
T01 : 5 sensibilités → suivi horizontal variable
  ↓
T05 : 5 sensibilités → suivi réactif variable
  ↓
Meilleur réglage du dernier bloc → Appliquer → Conversion
```

Chaque essai dure 60 s par défaut, ou 45 s au choix. Il y a donc 25 min ou 18 min 45 s **mesurées**, plus les décomptes et au moins trois secondes de repos après les essais utilisables. L’interface estime environ 28 ou 22 min ; lecture des résultats, interruptions et pauses personnelles peuvent rallonger ce temps.

Il n’y a pas cinq répétitions identiques pour chaque sensibilité : il y a **cinq essais à cinq sensibilités distinctes dans chacune des cinq activités**. Le protocole actuel ne fait pas de répétition statistique multiple d’un même réglage dans un bloc.

### 6.2 Point de départ

Le joueur peut conserver son réglage, l’importer d’un jeu ou choisir un point de départ :

| Choix | Distance initiale |
|---|---:|
| Plus lent | 50 cm/360° |
| Équilibré | 35 cm/360° |
| Plus rapide | 25 cm/360° |

Ces presets sont des points de départ, pas le résultat de la calibration. Le DPI reste celui déclaré par le joueur.

Deux modes sont proposés :

- **Réglage connu :** exploration locale initiale de facteurs de vitesse `1/1,2` à `1,2`.
- **Nouveau réglage :** exploration initiale plus large, de `1/1,6` à `1,6`, avec extension conditionnelle au premier bloc.

Les réglages sont toujours bornés entre **5 et 150 cm/360°**, avec DPI positifs jusqu’à 64 000 et FOV vertical de 40° à 110°. Le champ doit aussi contenir les exercices concernés : une valeur de FOV admissible pour le profil ne garantit pas que toute calibration y tienne.

### 6.3 Modèle physique interne

La représentation canonique est la distance `cm_per_360`, associée aux DPI et au FOV du profil :

```text
degres_par_count = 914,4 / (DPI × cm_par_360)
sensibilite_AIM_LOCAL = degres_par_count / 0,022
```

Le facteur 914,4 vient de `360 × 2,54` : degrés d’un tour et conversion pouces/centimètres. Une distance plus petite correspond à une sensibilité plus rapide.

À 800 DPI et 35 cm/360°, la rotation vaut environ 0,03265714°/count et la sensibilité AIM/LOCAL environ 1,48441558. L’affichage à deux décimales ne remplace pas cette valeur canonique par 1,48 pendant les calculs.

### 6.4 Recherche dans l’espace logarithmique

Le moteur conserve la baseline initiale, puis représente chaque vitesse relative par :

```text
position_log = log(cm_baseline / cm_candidat)
facteur_de_vitesse = exp(position_log)
cm_candidat = cm_baseline / exp(position_log)
```

Une position positive accélère, une négative ralentit, zéro correspond au départ. Le DPI ne varie pas.

L’espace logarithmique rend les changements multiplicatifs cohérents. Le milieu de deux positions log correspond à une moyenne **géométrique** des facteurs de vitesse, pas à la moyenne arithmétique de deux sensibilités affichées.

Les limites globales sont `log(cm_baseline / 150)` et `log(cm_baseline / 5)`. La fenêtre initiale, centrée sur zéro, est tronquée si elle rencontre ces limites.

### 6.5 Choix des cinq essais dans une activité

**Essai 1 — référence du bloc.** Tester `center_log`. Au premier bloc, c’est la baseline ; aux suivants, c’est le meilleur réglage conservé du bloc précédent.

**Essai 2 — côté rapide si disponible.** Tester `upper_log`. Si le centre est déjà au bord supérieur et qu’aucun réglage plus rapide n’est disponible, tester le bord inférieur. « Le deuxième est toujours plus rapide » est donc une simplification de l’interface, pas une règle vraie à chaque frontière.

**Essai 3 — réaction au résultat de l’essai 2.**

- Si son utilité dépasse celle du premier, tester le milieu logarithmique entre les deux.
- Sinon, tester l’autre bord : normalement plus lent que la première référence, et non simplement un léger ralentissement du deuxième réglage.
- Si un réglage proposé a déjà été testé ou sort des limites, utiliser la proposition d’intervalle décrite ci-dessous.

**Essai 4 — extension novice éventuelle ou exploration ciblée.** L’extension n’est possible que dans le premier bloc, en mode large, après trois essais : si le meilleur est au bord supérieur, étendre ce bord d’un `initial_span_log`; au bord inférieur, étendre vers le bas. Les bornes globales s’appliquent toujours.

Il ne s’agit pas d’une extension illimitée à chaque essai ou à chaque exercice. Sans cette condition, le moteur cherche un milieu d’intervalle prometteur.

**Essai 5 — compléter autour du meilleur.** Le choix s’appuie sur les intervalles encore non testés, en favorisant les grands espaces proches du meilleur essai courant.

`untested()` refuse un candidat hors fenêtre ou à moins de `1e−9` en position log d’un essai déjà effectué. Si aucune proposition distincte n’est disponible, le service refuse l’avancement plutôt que fabriquer une nouvelle mesure identique.

### 6.6 Comment les intervalles non testés sont choisis

`gap_proposal()` trie les positions des essais déjà réalisés et les deux bords. Pour chaque paire de positions adjacentes :

```text
largeur = borne_droite − borne_gauche
milieu = (borne_droite + borne_gauche) / 2
poids = largeur / (1 + 4 × abs(milieu − position_du_meilleur))
```

Le milieu non testé au poids le plus élevé est proposé. Cela combine couverture d’une zone mal explorée et proximité d’une bonne performance. Ce n’est ni une série prédéfinie identique pour tous les joueurs, ni un tirage au hasard de la sensibilité suivante.

Cette heuristique n’est pas une méthode de preuve d’optimum global : elle ne modélise pas une distribution de bruit, un intervalle de confiance ou une fonction de performance forcément unimodale.

### 6.7 Sélection du meilleur essai

`best_trial()` compare les utilités non arrondies. Une différence inférieure à `1e−10 × max(1, abs(utilite), abs(meilleure_utilite))` est traitée comme une quasi-égalité numérique.

En quasi-égalité, le réglage le plus proche du centre du bloc est privilégié. Si la proximité ne départage pas les essais, l’ordre déjà retenu reste stable. Ce seuil est une tolérance informatique ; il ne signifie pas que la différence est statistiquement significative pour un joueur.

Le protocole ne lit pas directement les erreurs de tir pour conclure « overshoot donc ralentir » : son adaptation est guidée par les **performances des réglages essayés**. Il n’utilise pas de questionnaire de confort.

### 6.8 Resserrer la zone après cinq essais

`close_block()` :

1. Retient la position du meilleur essai.
2. Cherche les positions testées les plus proches en dessous et au-dessus, en restant dans la fenêtre courante.
3. Limite la largeur suivante à au plus **70 %** de la largeur courante en espace logarithmique.
4. Coupe chaque côté à une demi-largeur autour du meilleur, sans dépasser les bords précédents.
5. Stocke le bloc, son meilleur réglage et `moving_range_cm`.
6. Utilise le meilleur comme centre et premier essai de l’activité suivante.

La zone conservée est une **fenêtre de recherche algorithmique**, pas un intervalle de confiance sur une sensibilité vraie. Le pourcentage de contraction s’applique à la largeur logarithmique, pas directement à un nombre de centimètres.

Dans `moving_range_cm`, l’ordre des bords est inversé par rapport aux facteurs de vitesse : le bord rapide correspond au plus petit nombre de cm/360°.

### 6.9 Exemple numérique de décisions

Exemple **purement illustratif**, sans performance réelle de joueur : baseline 35 cm/360°, 800 DPI, exploration large, hors bornes globales.

| Essai | Décision | Facteur de vitesse | Distance |
|---|---|---:|---:|
| 1 | Départ | 1 | 35 cm |
| 2 | Bord rapide | 1,6 | 21,875 cm |
| 3 si 2 meilleur | Milieu logarithmique | racine carrée de 1,6 ≈ 1,26491 | ≈ 27,6699 cm |
| 3 si 2 moins bon ou quasi égal | Bord lent | 0,625 | 56 cm |

Si, après les trois premières mesures, le meilleur reste au bord rapide dans ce premier bloc novice, l’essai 4 peut aller au facteur 2,56, soit 13,671875 cm. Au bord lent, une extension symétrique peut aller à 89,6 cm. Les essais suivants et la zone transmise dépendent ensuite des utilités réellement observées.

Cet exemple ne doit pas être lu comme la suite imposée à chaque utilisateur : modes, limites et résultats peuvent produire des candidats différents.

### 6.10 Conditions constantes et validité d’un essai

Les cinq essais d’une activité partagent la graine `calibration_seed + index_bloc × 7919`. En suivi, les cycles et rythmes sont déterminés par le temps, la graine et l’identité de cible, indépendamment des mouvements de visée. En clic, les remplacements dépendent aussi des touches, comme expliqué dans les règles communes.

`accept()` vérifie notamment :

- Rapport cohérent, terminé, valide, non échauffement et associé au bon `calibration_id`.
- Exercice, graine, révision et empreinte exactement attendus.
- Profil correspondant au candidat, durée, aspect, Godot 4.7.2 et renderer Compatibility.
- Ordre du bloc et de l’essai, si ces indices sont présents.
- Clé de comparaison reconstruite et mesures de performances acceptables.

L’activité minimale exige un input mesuré et un trajet angulaire positif ; le clic exige aussi au moins trois tirs. La calibration exige au moins deux frames observées, un P99 de frametime ≤50 ms et une frame maximale ≤250 ms. Une saturation du tampon d’input invalide la séance.

Ces contrôles ne sont pas une analyse statistique de la qualité d’un échantillon. Ils empêchent surtout qu’une séance interrompue, vide, saccadée ou réalisée dans des conditions incompatibles fasse avancer la recherche.

Pendant la calibration, modifier la sensibilité via le menu de pause est verrouillé. Hors calibration, une modification appliquée redémarre l’essai afin de ne pas mélanger deux réglages dans un seul rapport.

### 6.11 Valeur finale : ce qui est calculé exactement

`recommendation()` attend les 25 essais. La valeur choisie est :

```text
recommended_cm_per_360 = meilleur_cm_du_dernier_bloc
recommended_sensitivity = conversion_AIM_LOCAL(DPI_baseline, recommended_cm_per_360)
```

Le dernier bloc est T05. Les activités précédentes ont influencé les fenêtres de recherche, mais le moteur **ne calcule pas une moyenne pondérée des cinq meilleurs réglages**, ne refait pas tous les exercices avec la valeur finale et ne procède pas à un vote global entre les 25 essais.

Il retourne une valeur réellement mesurée et une autorisation d’application, avec les cinq blocs et le checkpoint. C’est une décision précise et exploitable. Sa qualité dépend néanmoins de l’ordre des activités, du bruit de performance et de la contraction des zones : une mauvaise première mesure peut exclure une zone qui aurait été intéressante plus tard.

### 6.12 Ce qui n’est pas encore implémenté

- Répéter plusieurs fois chaque sensibilité pour estimer sa variabilité.
- Randomiser ou contrebalancer l’ordre des sensibilités et des activités.
- Valider le réglage final à nouveau sur les cinq familles.
- Optimiser simultanément DPI et sensibilité logicielle.
- Détecter automatiquement la fatigue ou interpréter des ratés signés par axe.
- Calculer un optimum statistique global ou une sensibilité parfaite pour tous les jeux.

Ces pistes sont des améliorations possibles, **pas des comportements cachés de la version 0.9**. Le champ historique `goal` ne transforme pas le parcours public en optimisation pondérée différente pour précision ou suivi.

<a id="sauvegarde"></a>

## 7. Sauvegarde, reprise et application

### 7.1 Données persistées

Les données applicatives sont locales, sous `user://aim_local`, soit `%APPDATA%\AIM_LOCAL\aim_local` dans la distribution Windows.

- Les séances sont enregistrées avec identifiant, date UTC, version, empreinte, graine, conditions, mesures et score.
- `progressive_calibration_checkpoint.json` conserve baseline, protocole, aspect, graine de calibration, identifiant, durée, mode d’exploration, empreintes et essais acceptés.
- Les bilans progressifs sont stockés sous `calibrations/progressive-<identifiant>.json`.
- Les anciennes recherches sont archivées sous `archives/` avant un nouveau parcours reconnu.

L’heure UTC enregistrée permet le tri stable des données ; elle est distincte du fuseau de lecture du joueur.

### 7.2 Résultat affiché et avancement durable

Après un essai utilisable, `main.gd` conserve un rapport `pending_trial` et propose la continuation après un minimum de trois secondes. L’affichage du résultat ne suffit pas à affirmer que le parcours a avancé durablement.

À la continuation :

1. Réessayer la sauvegarde de séance si nécessaire.
2. Conserver le checkpoint précédent en mémoire.
3. Appeler `progressive.accept()`.
4. Sauvegarder le nouveau checkpoint.
5. En cas d’échec, restaurer l’état précédent et garder l’essai en mémoire.
6. En cas de succès, libérer l’essai pending et préparer le suivant.

Un refus d’écriture ne doit pas inventer un score accepté ou perdre silencieusement la mesure. L’enregistrement des rapports et bilans utilise des contrôles d’identité et d’idempotence ; le profil et les checkpoints utilisent des remplacements atomiques avec protections de reprise.

### 7.3 Reprendre par reconstruction

`restore()` ne fait pas confiance à des bords de recherche simplement copiés depuis un fichier. Il valide le checkpoint, crée un service de vérification, relance `begin()` dans le bon protocole puis rejoue `accept()` pour chacun des rapports sauvegardés.

La recherche est ainsi reconstruite avec les mêmes règles de sélection, contraction et départage numérique. Le checkpoint reconstruit doit correspondre à celui lu. Une modification d’empreinte, de profil, de graine ou d’ordre empêche une reprise silencieuse.

| Protocole | Difficultés utilisées lors de la reprise |
|---|---|
| 4 | Bases r3/r4/r5 de la 0.7 |
| 5 | Dix-huit variantes temporelles r6 de la 0.8 |
| 6 | Clic/transitions r6 et suivis r7 de la 0.9 |

Un essai interrompu et non accepté doit être rejoué ; le checkpoint n’est pas une sauvegarde du mouvement de caméra au milieu d’une cible. Fichiers corrompus, versions inconnues, archives contradictoires, régressions d’état et changements concurrents sont préservés et signalés, pas écrasés pour débloquer l’interface.

### 7.4 Appliquer reste une action explicite

La recommandation ne remplace pas automatiquement le profil. Le bouton Appliquer récupère la baseline, remplace sa distance par `recommended_cm_per_360`, sauvegarde le profil puis l’utilise.

Pour la calibration progressive, la valeur canonique est conservée sans la quantifier à l’affichage à deux décimales. L’application ne modifie pas le DPI du périphérique, ni les paramètres d’un autre jeu.

### 7.5 Services historiques à ne pas confondre

`CalibrationService` et `AdaptiveSensitivityService` restent présents pour leurs anciens formats et tests. Leurs comparaisons et champs de confort ne décrivent pas le parcours public actuel. Les commandes historiques sont cachées dans l’interface courante ; leur présence dans le dépôt ne signifie pas que le joueur doit encore noter son confort après un micro-exercice.

<a id="conversion"></a>

## 8. Conversions entre jeux

### 8.1 Principe de conversion

Un jeu dont la rotation sans zoom suit un coefficient `yaw_deg` possède :

```text
degres_par_count = sensibilite_jeu × yaw_deg
cm_par_360 = 914,4 / (DPI × sensibilite_jeu × yaw_deg)
sensibilite_destination = 914,4 / (DPI_destination × cm_par_360 × yaw_destination)
```

Le réglage physique, et non le simple nombre affiché dans le jeu, sert de point commun.

| Profil | Coefficient pris en charge | Provenance |
|---|---:|---|
| AIM/LOCAL | 0,022 | Convention de l’application |
| CS2 | 0,022 par défaut | Documentaire ; `m_yaw` personnalisé possible et identifié |
| Valorant | 0,07 | Documentaire, sans zoom |
| Call of Duty / autre jeu | Déduit d’une mesure | Titre/version et distance réelle requis |

Pour un jeu mesuré : `yaw_deg = 914,4 / (DPI_source × sensibilite_source × cm_mesures)`. Le programme ne prétend pas qu’un coefficient universel représente tous les Call of Duty ou toutes leurs options.

### 8.2 DPI source et DPI actuels

Importer un réglage conserve les DPI actuels du profil AIM/LOCAL. Les DPI du jeu source sont stockés séparément dans `reference_game` et servent à calculer sa distance physique.

Exemple : un réglage source à 800 DPI peut être importé pour une souris désormais à 1 600 DPI. La distance cm/360° est conservée, mais la sensibilité numérique de destination doit être adaptée. Copier simplement le nombre source donnerait une rotation différente.

À 800 DPI et 35 cm/360°, les valeurs théoriques sont environ 1,4844 pour AIM/LOCAL/CS2 avec coefficient standard et 0,46653 pour Valorant. Les nombres de sensibilité ou les eDPI de deux jeux à coefficients différents ne sont pas directement comparables.

### 8.3 Limites de l’équivalence

La conversion vise une rotation sans zoom cohérente avec les DPI déclarés. Elle ne garantit pas le même ressenti à FOV différent, la même vitesse de déplacement à l’écran, l’équivalence ADS/scope ou le comportement d’une caméra accélérée par un jeu tiers.

La mesure physique du tour complet reste utile pour vérifier le réglage réel. L’application ne lit ni ne modifie les fichiers ou processus des autres jeux ; elle fournit les valeurs à y saisir manuellement.

<a id="progression"></a>

## 9. Suivi de progression

### 9.1 Comparer des conditions identiques

`ScoringService.comparison_key()` construit une empreinte SHA-256 depuis : difficulté, version de score, durée, DPI, cm/360°, FOV vertical, aspect arrondi au pas 0,0001, accumulation d’input, limite FPS, inversion verticale, version moteur et renderer.

La graine n’est pas dans cette clé : des entraînements renouvelés peuvent contribuer à la même progression. Arme, couleur du viseur et autres préférences cosmétiques ne changent pas directement cette clé mécanique ; leur effet humain éventuel n’est pas isolé causalement par le logiciel.

**Changer de sensibilité change la clé.** Les essais d’une calibration ne sont donc pas agrégés en un record unique comme s’ils avaient tous le même réglage. Le service de calibration les compare explicitement dans son bloc, avec contrôle des candidats.

### 9.2 Indicateurs affichés

`ProgressService.summarize()` trie les rapports comparables par date UTC et identifiant, puis calcule :

- Le record et le score de la dernière séance.
- La médiane des cinq dernières séances comparables, ou du nombre disponible si inférieur.
- Les vingt dernières valeurs pour la courbe et les lignes récentes.
- Une tendance disponible à partir de dix séances.
- La variation de médiane récente par rapport aux cinq premières séances comparables, si leur médiane est positive.

La tendance n’est donc pas automatiquement « cinq dernières contre cinq immédiatement précédentes ». Les rapports interrompus, invalides, d’échauffement, sans activité ou incohérents sont exclus, avec raisons conservées.

Un record n’est annoncé qu’après sauvegarde réussie. Un historique ancien reste stocké, mais n’est pas fusionné avec une difficulté nouvelle. La hausse d’un score comparable est un indicateur de performance dans l’exercice, pas une preuve automatique d’amélioration en match dans un autre jeu.

### 9.3 Exports et mesures brutes

Les exports JSON conservent les rapports. Le CSV conserve ses vingt colonnes historiques et ajoute `misses`, `targets_expired`, `effective_accuracy_pct` et `failed_actions`.

Ces fichiers permettent de distinguer tirs ratés et cibles oubliées, mais ne contiennent pas l’intégralité des événements de souris. Une analyse externe doit respecter version, empreinte et conditions avant de réunir des résultats.

<a id="maintenance"></a>

## 10. Tests, limites et maintenance

### 10.1 Tests qui protègent ces règles

| Domaine | Tests de référence |
|---|---|
| Profil, input, UI et parcours intégrés | [run_tests.gd](../tests/run_tests.gd) et suites appelées |
| Enveloppes, profondeurs et collisions | [geometry_regression_tests.gd](../tests/geometry_regression_tests.gd) |
| Graines et historique | [pattern_variation_tests.gd](../tests/pattern_variation_tests.gd) |
| C03, M01, T10 et routine historiques | [exercise_070_tests.gd](../tests/exercise_070_tests.gd) |
| Expirations, rétrécissement et score V2 | [lifecycle_tests.gd](../tests/lifecycle_tests.gd) |
| Vitesses r7, intégrales, arrêts et replays | [tracking_rhythm_tests.gd](../tests/tracking_rhythm_tests.gd) |
| Décisions et reprise de calibration | [progressive_calibration_tests.gd](../tests/progressive_calibration_tests.gd) et [progressive_calibration_flow_tests.gd](../tests/progressive_calibration_flow_tests.gd) |
| Conservation des scores après JSON | [storage_roundtrip_tests.gd](../tests/storage_roundtrip_tests.gd) |
| Démonstrations représentatives | [preview_containment_tests.gd](../tests/preview_containment_tests.gd), [temporal_ui_tests.gd](../tests/temporal_ui_tests.gd) |
| Rendu et distribution | [visual_smoke.gd](../tests/visual_smoke.gd), [export_smoke.gd](../tests/export_smoke.gd) |

Le jalon 0.9 documenté dans [TEST_PLAN.md](TEST_PLAN.md) a validé 13 suites, 293 764 assertions et 177 captures logicielles. Ce sont des résultats de validation du jalon, pas des joueurs, des minutes humaines ou une preuve d’optimum de sensibilité.

Les tests vérifient notamment des replays à 60/144/240 FPS, les sauts de temps, les frontières de cycle, les bornes de mouvement, les phases de pause, les programmes lus hors ordre et les protocoles 4/5/6. L’export Windows est vérifié par ouverture de son pack sous Linux ; cela n’est pas un lancement natif Windows.

### 10.2 Ce qu’il faut encore réceptionner humainement

- Lisibilité et confort des petites cibles, notamment C05 et T09.
- Sensation des rampes, freinages et reprises pendant plusieurs cycles de chaque suivi.
- Fluidité GPU, scaling Windows, son réellement entendu et comportements des périphériques.
- Rotation physique cm/360° et réception des souris à différents polling rates.
- Stabilité du réglage retenu un autre jour et après repos.
- Transfert éventuel des performances vers les jeux réels.

La fatigue, l’apprentissage pendant le parcours et l’ordre des essais peuvent déplacer le meilleur résultat observé. Une interface claire et des métriques cohérentes ne suppriment pas ces limites expérimentales.

### 10.3 Modifier proprement un exercice

1. Déterminer la compétence visée et les paramètres réellement concernés.
2. Ne pas modifier une définition historique déjà utilisée par un checkpoint reconnu.
3. Ajouter une variante versionnée si taille, durée, distribution, trajectoire ou rythme changent.
4. Vérifier que `fingerprint()` inclut les paramètres mécaniques actifs et une version du modèle.
5. Valider enveloppe, sol, plan proche, séparation et taille jouable minimale.
6. Utiliser la même géométrie pour aperçu, rendu, hitbox et métriques.
7. Tester les cas limites, FPS, graines et reprises avant distribution.
8. Versionner aussi le protocole de calibration si ses difficultés ou règles changent, en conservant les anciens accès.
9. Modifier ce document avec les règles réellement implémentées, pas seulement avec l’intention de conception.

La table du catalogue n’est pas le seul endroit à changer : une nouvelle mécanique doit être reliée à la génération, au scoring si nécessaire, à la lecture des rapports et aux tests. Inversement, changer seulement un titre ou une phrase de `ScenarioCopy` n’impose pas de changer la physique ou les anciennes données.

### 10.4 Résumé opérationnel

Le joueur déclare son DPI et son réglage ou un point de départ. Le moteur commun produit des cibles bornées, temporaires et mesurables. La calibration teste cinq sensibilités par activité, compare des utilités non arrondies et resserre sa zone d’exploration. Elle retient un réglage effectivement testé dans le dernier bloc, le sauvegarde comme recommandation et laisse le joueur l’appliquer puis le convertir.

Le logiciel mesure des performances dans des tâches précises. Pour progresser de façon interprétable, il faut conserver les conditions de comparaison, distinguer les familles et garder les limites du protocole visibles — sans encombrer le HUD avec toute cette documentation technique.
