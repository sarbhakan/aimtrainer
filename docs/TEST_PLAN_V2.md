# AIM/LOCAL V2 — Plan de réception et preuves

**Version : 1.0.0. Recette logicielle cloud Linux ; recette matérielle Windows distincte.**

Ce plan accompagne le [guide V2](EXERCICES_ET_CALIBRATION_V2.markdown) et le [cahier original](reference/v2/AIM_LOCAL_SPECIFICATIONS_V2.md). Le [plan historique](TEST_PLAN.md) reste conservé. Une ligne décrit soit une preuve réellement observée, soit un contrôle à effectuer ; aucun résultat attendu n’est présenté comme réussi.

## 1. Import et références originales

| Contrôle exécuté | Résultat réel | Portée |
|---|---|---|
| `python3 -B tools/import_v2_atlas.py --kit docs/reference/v2 --output-dir content/v2 --check` | Réussi : 81 SHA-256, 24 configurations, 54 définitions de phase | Intégrité du kit et des imports, accord Atlas/catalogue/thème/états documentaires |
| `python3 -B tests/v2_atlas_import_tests.py --kit docs/reference/v2` | **94 tests, 0 échec** | Extraction HTML/JSON, mutations de contrats, pin du manifeste, sources altérées, outputs périmés ; écritures exclusivement dans des dossiers temporaires |
| `bash tools/godot.sh --headless --check-only --script res://tests/v2_catalog_tests.gd` | Réussi lors de la préparation du catalogue ; les exécutions finales compilent aussi les changements suivants | Analyse du script et de ses dépendances directes |
| `bash tools/godot.sh --headless --script res://tests/v2_catalog_tests.gd` | **494 assertions, 0 échec** ; marqueur `V2 CATALOGUE : 494 assertions, 0 échecs.` | 24 variantes, 54 phases, types/valeurs/champs fermés, garde des octets, schéma original, mutations et empreintes natives |

Le catalogue chargé garde les neuf clés originales et la révision `2026-10-12-v2.0`. Les cinq JSON importés sont identiques aux sources. Le schéma reste celui du kit, avec 14 définitions nommées ; les assertions ne valident pas un moteur JSON Schema général. Le checksum du manifeste est épinglé, donc une source et un `SHA256SUMS.txt` simultanément modifiés sont refusés.

Ces contrôles d’import ne suffisent pas à réceptionner l’application. Les suites natives, le contrôleur réel, les captures et le pack sont vérifiés séparément ci-dessous. Les commandes et journaux de la recette finale sont conservés sous [`validation/v2`](validation/v2/README.md). Une souris réelle et un pilote humain ne sont pas simulés par ces tests.

## 2. Suites natives exécutées

| Suite ou contrôle | Couverture | Résultat logiciel |
|---|---|---|
| [`v2_foundation_tests.gd`](../tests/v2_foundation_tests.gd) | AIM-CANON-1, PRNG, géométrie, fixture originale `empreintes.fixtures.json` | 73 assertions, 0 échec |
| [`v2_motion_tests.gd`](../tests/v2_motion_tests.gd) | Oracle original, niveaux, phases, tapes réactifs, égalités mur/atterrissage | 5 468 829 assertions, 0 échec ; 233 040 échantillons, 722 états et 153 tapes |
| [`v2_catalog_tests.gd`](../tests/v2_catalog_tests.gd) | Définitions originales, schéma, hashes et mutations invalides | 494 assertions, 0 échec |
| [`v2_runtime_tests.gd`](../tests/v2_runtime_tests.gd) | 24 programmes, remplacement, EX03, HP/partials, profondeur et budget d’intégration | 424 assertions, 0 échec |
| [`v2_event_tests.gd`](../tests/v2_event_tests.gd) | Ordre des entrées, fronts au même timestamp, regard ailleurs, trace QA et framing 60/144/240 FPS | 24 assertions, 0 échec ; flux 8 kHz synthétique ≠ polling USB |
| [`v2_store_tests.gd`](../tests/v2_store_tests.gd) | Profil, historique, état CAL, crash, JSON strict et refus d’écrasement | 169 assertions, 0 échec |
| [`v2_calibration_tests.gd`](../tests/v2_calibration_tests.gd) | Gains, comparaisons, plans négatifs réempreintés, conditions, epochs, dates, préflight | 37 751 assertions, 0 échec ; 14 grilles et 28 decks natifs |
| [`v2_calibration_task_tests.gd`](../tests/v2_calibration_task_tests.gd) | Decks d’oracle, premier front CLICK, priorité SWITCH, contact, deadlines et rendu | 12 196 assertions, 0 échec ; 36 cas d’oracle et 106 exécutions natives |
| [`v2_ui_tests.gd`](../tests/v2_ui_tests.gd) | Navigation, profil exact, écrans CAL, résultats, HUD et dimensions | Headless : 192 assertions ; avec captures : 246 assertions ; 0 échec, ne remplace pas le contrôleur réel |
| [`v2_app_flow_tests.gd`](../tests/v2_app_flow_tests.gd) | MainV2, signaux UI, countdown, profils, abandon, pause et reçus de rendu | Headless : 253 assertions, 0 échec, 2 routes d’entrée non exécutées ; Xorg : 282 assertions, 0 échec, ces routes exécutées |
| [`v2_calibration_runner_tests.gd`](../tests/v2_calibration_runner_tests.gd) | Journées complètes, calendrier, checkpoints, niveaux, références d’audit, crash et types fermés | 491 assertions, 0 échec ; 150,94 s sur l’exécution ciblée |
| [`v2_progress_tests.gd`](../tests/v2_progress_tests.gd) | Rapports recalculés, empreintes, contexts, records et médianes admissibles | 635 assertions, 0 échec |
| [`v2_cal_flow_tests.gd`](../tests/v2_cal_flow_tests.gd) | Vrai contrôleur CAL, UI, tâches, profil, rapports et horloges contrôlées | 15 103 assertions, 0 échec dans la recette complète ; aucune horloge humaine mesurée |
| `tools/test.sh` | 26 runners GDScript, compilation préalable, marqueurs positifs et rejet des erreurs ; puis import Python | Journal général de la recette finale ; les 13 runners historiques restent conservés |
| Références originales du kit | Catalogue, mouvements, CAL et Atlas dans leurs périmètres documentaires | Catalogue : 47 cas négatifs et 4 positifs ; mouvement : 2 025 700 contrôles ; Atlas : 213 115 contrôles ; CAL : calculateur/scheduler de référence |

Les noms des suites indiquent leur emplacement réel. Leur présence et les rapports fournis par le kit ne sont pas des résultats d’exécution nouveaux. Une suite interrompue, zéro test, un log ancien ou un code Godot nul accompagné d’erreurs ne sont pas une réussite.

## 3. Matrice mécanique des 24 variantes

Les 24 configurations et 54 phases sont exercées par les suites catalogue, mouvement et runtime. Les captures couvrent toutes les phases Standard et un échantillon de chaque programme Novice/Avancé. La jouabilité humaine doit encore être évaluée pour chaque niveau ; l’oracle numérique ne mesure pas la fatigue ou la difficulté ressentie.

| Programme | Phases et effectifs attendus | Cas de réception |
|---|---|---|
| EX01 | `micro/general/amplitude`, 20/20/20 s, une cible | Miss sans déplacement ; remplacement logique avec marque propre ; sac 12 bandes équilibrées ; ancre indépendante du viseur ; scores C séparés |
| EX02 | `grid/precision`, 20/40 s, trois puis six cibles | Neuf nœuds uniques ; seuls slot et nœud touchés changent ; exclusion du nœud précédent ; silhouettes et voisinage conservés ; censure à 20 s |
| EX03 | `fixed_window/shrinking_window`, 30/30 s, dix fenêtres chacune | Dates précompilées ; tirs dans le vide comptés ; deadline exclusive ; hit non recompté expired ; 100→60 % du diamètre dans la seule phase shrink |
| EX04 | `linear/evasive/arcs`, 20/20/20 s, quatre cibles | Impulsion linéaire explicite ; bord réactif à l’intérieur d’une rampe ; quatre chambres ; âge initial en vol ; yaw pendant repos ; égalité mur/atterrissage |
| EX05 | `horizontal/vertical/ellipse`, 20/20/20 s, une cible | Persistance, acquisition dans l’exposition ; pics de vitesse des sinus ; vitesse d’arc sphérique ; conservation du diamètre et absence de respawn |
| EX06 | `reactive`, 60 s, une cible | Vitesse initiale non nulle ; mélange réel des plateaux ; événements spontanés/bord ; zeros de vitesse du tape ; réacquisition certifiée et censure des fenêtres |
| EX07 | `depth`, 60 s, une cible | Même rayon à 3/4/5 m ; phases indépendantes ; diamètre apparent correct ; aucune compensation écran ou réinitialisation |
| EX08 | `static/mobile/evasive`, 20/20/20 s, quatre cibles | PV 30/40/50 selon niveau, constants entre phases ; 100 PV/s ; maintien armé ; partials de toutes les cibles ; aucune propagation d’overkill |

Chaque variante garde 60 s actives, le nombre exact de phases et les paramètres du JSON original. L’interface ne doit pas recréer les 18 cartes historiques par des sous-variantes cachées.

## 4. Entrées, rendu, contact et scores

| ID | Action / fixture | Critère | Preuve à conserver |
|---|---|---|---|
| IN-01 | Recevoir mouvement/clic/mouvement au même timestamp | Le clic utilise la pose intermédiaire ; chaque événement est appliqué une fois, dans son ordre de réception | Trace synthétique et rapport de suite |
| IN-02 | Rejouer la même trace opt-in avec framing 60/144/240 FPS | Mesures compatibles avec les bornes publiées ; aucune RNG par image ni multiplication du mouvement par `delta` | Logs, traces et bornes numériques |
| IN-03 | Déclencher overflow et timestamps non monotones | Invalidation explicite, aucun mouvement silencieusement perdu | Cause du rapport |
| IN-04 | Pratique en mode léger | `pose_event_count` présent, `trace_retention="light_no_exact_input_replay"` ; pas de promesse de replay exact | Rapport original sauvegardé |
| RD-01 | Tirer sur un spawn ou une remplaçante avant sa première image admissible | Pas de hit, front conservé dans les mesures appropriées | Identité/génération et marques de rendu |
| RD-02 | EX03 préparée mais hors champ par choix du joueur, puis opportunité jamais dessinée | Le premier cas reste une expiration logique ; le second est technique, sans échec humain fabriqué | Ack préparé, visibilité, disposition finale |
| RD-03 | Retarder la première image d’un suivi | Seul le numérateur de contact est bloqué ; exposition complète de 20/60 s | Rapport de phase et dénominateur |
| RD-04 | Changer le viewport ou perdre le rendu utile pendant la mesure | Incident technique visible ; comportement de classement conforme à la qualité et aux conditions | Rapport et capture/log |
| CT-01 | Contact pleinement intérieur, extérieur et tangent | Bornes cohérentes, estimateur brut au milieu ; pas de score issu d’un contact fusionné | `contact_lower_s`, `contact_upper_s`, estimateur |
| CT-02 | Racine ou contact ambigu persistant dans plusieurs feuilles | File de priorité et budget global de largeur ; invalidation explicite si le contrat ne peut être tenu | Nombre d’évaluations, largeur cumulée et cause |
| CT-03 | Consommer les budgets 8 192/tranche ou 4 000 000/phase | `unresolved_integration_error` ; pas de score classable malgré un moteur encore dessiné | Log et rapport invalidé |
| CT-04 | Kill exactement à 20/40/60 s ; tir exactement à deadline/60 s | Kill ancien conservé sans spawn ancien ; deadline exclusive ; aucun point ajouté à 60 s | Chronologie des événements |
| CT-05 | EX06 : inversion extraite d’un segment tronqué, nouvelle inversion avant 250 ms | Date issue du zéro de vitesse effectif ; fenêtre censurée à la suivante | Tape et `reversal_observations` |
| CT-06 | EX06 : trous de 20 ms et séquences voisines du seuil 50 ms | Stable seulement sur contact certifié continu ; fusion diagnostique sans effet sur score ; latence absente = `null` | Intervalles certifiés, métriques et score brut |
| SC-01 | Fixtures C/P/T/S avec zéro tir, zéro contact et partials | Formules/version/units exactes ; absence de score pour passage incomplet/invalide | Valeurs non arrondies et attendus indépendants |
| SC-02 | Fermer EX01/02/03/04 puis EX05/06/07/08 | Pas d’agrégat C/P non prévu ; agrégats T/S conformes et phases conservées | Rapport complet |
| SC-03 | Pause de pratique puis reprise avec décompte 3 s | Horloge active préservée ; reprise explicite ; `rank_eligible=false` pour une séance interrompue | Temps actif, pauses, rapport |
| SC-04 | Passage complet sans frametimes réels ou avec qualité invalide | Score logiciel éventuellement diagnostique ; absence de preuve matérielle ; classement conditionné par la qualité | `render_quality` et `rank_eligible` |
| DF-01 | Passer un dictionnaire arbitraire à un point d’entrée runtime | Validation avant accès aux champs ; champ requis, type bool/nombre ou variante incorrecte refusé proprement | Test du moteur/contrôleur, pas seulement `V2Catalog` |

Les cas logiciels de cette matrice sont exercés par `v2_foundation_tests`, `v2_runtime_tests`, `v2_event_tests`, `v2_motion_tests`, `v2_progress_tests` et `v2_app_flow_tests`. Les résultats complets sont dans le journal général. La matrice ne transforme pas une assertion synthétique en essai à la souris, capteur 8 kHz ou scanout physique.

## 5. Calibration : conditions de publication du parcours

Le contrôleur appelle maintenant le runner et les tâches natives. Les garde-fous sont testés à plusieurs niveaux : calculateur, moteur de tâche, scheduler persistant puis parcours réel du contrôleur avec horloges et entrées synthétiques. Les journées accélérées de QA sont marquées comme telles ; leur recevabilité logicielle n’est pas une mesure humaine.

| ID | Contrôle | Acceptation | État de réception |
|---|---|---|---|
| CAL-01 | Grille des gains et préflight | Référence exacte, gains distincts après quantification, bornes 5–150 cm et difficultés figées | Service, runner, CAL flow ; vérifié logiciel |
| CAL-02 | Decks fournis et decks natifs | Stimuli/paramètres/trajectoires conformes à l’oracle vérifié ; provenance réelle ; aucune fixture synthétique traitée comme résultat utilisateur | Service, motion, tasks ; vérifié logiciel |
| CAL-03 | CLICK : premier front avant visibilité, miss, maintien, front tardif | Une seule issue comparative ; prématuré consomme ; extra/late diagnostiques ; onset immuable | Tasks et CAL flow ; vérifié logiciel |
| CAL-04 | SWITCH : onset, priorité, kill/deadline et maintien | PV remis à l’onset ; dégâts après première image ; neutralité hors fenêtre ; travail utile sur priorité uniquement | Tasks et CAL flow ; vérifié logiciel |
| CAL-05 | SMOOTH/REACTIVE et contact | Exposition 24 s ; acquisition incluse ; même compilateur réactif public ; audit CAL conservé | Tasks, motion et CAL flow ; vérifié logiciel |
| CAL-06 | Période de 192 s | Gain constant pendant prise en main, décomptes, scores, récupérations et repos prévu | Runner et CAL flow ; temps synthétique |
| CAL-07 | Express puis ABBA/BAAB | Ordres figés avant scores ; jour 2 opposé ; decks réellement appariés ; express exclu du calcul de confirmation | Service, runner, CAL flow ; vérifié logiciel |
| CAL-08 | Dates locales et fenêtres horaires | Jours distincts ; 12–168 h ; première confirmation ≥12 h après express ; refus des dates incohérentes | Service, runner, CAL flow ; dates contrôlées |
| CAL-09 | Pause/focus/capture/overflow/longue attente | Unité de reprise = journée complète ; epoch valide accepté en premier ; aucun choix au meilleur score | Tasks, runner, app flow, CAL flow ; interruptions synthétiques |
| CAL-10 | Conditions et frametimes | Seuils du protocole, quantile nearest-rank, écart médian apparié et snapshots vérifiés | Service et tasks ; frametimes synthétiques, matériel non réceptionné |
| CAL-11 | Plans altérés puis légalement réempreintés | Rejet sémantique malgré hash cohérent ; gain, durée, tâches, slots, conditions et liens contrôlés | Service et runner ; 8 plans négatifs réempreintés |
| CAL-12 | Huit statuts et garde-fous bruts | Marges 2/5 pp, réussite CLICK/SWITCH, tâches non informatives, priorité des statuts et valeurs non arrondies | Service ; 11 fixtures de comparaison et 8 statuts |
| CAL-13 | Appliquer / annuler | Consentement explicite, profil exact, rollback en échec d’écriture, état et bilan cohérents | CAL flow : candidat réellement confirmé, refus d’un candidat altéré, consentement UI, archive/commit, reprise et annulation exactes ; store/runner : pannes synthétiques |
| CAL-14 | Fin, abort, exception, fermeture et redémarrage | Restauration du gain de référence sans dépendre d’un processus resté vivant | Store, runner et CAL flow ; crash/interruption synthétiques |
| CAL-15 | UI → contrôleur → runner → tâche → stockage → bilan | Aucun hook vide ; vrai parcours de mesure ; résultats persistés et décision accessibles sans commande de développement | CAL flow ; 57 tâches mesurées et 95 familiarisations natives synthétiques |

Les budgets 11 min 36 s / 16 min 48 s par jour / 45 min 12 s total sont programmés, hors reprises et attentes réelles. L’interface et les rapports doivent expliquer cette différence. Une durée accélérée de QA ou un bot ne constitue pas une séance humaine recevable.

## 6. Données, historique et interface

| Contrôle | Acceptation | Statut |
|---|---|---|
| Profil V2 et import historique | Gain hex/binary64 exact ; aucun résultat 0.9 transformé ; données historiques inchangées | Store, UI, app flow et suites historiques |
| Rapports et records | Payload et empreinte vérifiés ; rapport immuable ; contexte/version/difficulté cohérents ; pas de record en cas d’échec de sauvegarde | Store, progress et app flow |
| Profil/checkpoint après panne | Remplacement protégé ; backup/reprise cohérente ; fichier inconnu/corrompu préservé et signalé | Store et runner |
| État CAL relié aux rapports | IDs, epoch, condition snapshot et application exacts ; refus des liens manquants ou contradictoires | Store, runner, CAL flow |
| Fichiers stricts | Doublons, non-finis, mauvais types, surrogates, UTF-8/BOM et entiers hors plage traités selon le format annoncé | Store et foundation |
| Huit cartes et trois niveaux | Navigation clavier/souris ; aucun sous-mode historique ajouté ; changements de paramètres hors séance seulement | UI, app flow et galerie native |
| Aperçu | Non mesuré, même famille de mouvement ; pas d’entrée ou score synthétique sauvegardé comme humain | App flow et galerie native ; moteur public partagé |
| HUD / feedback / couleurs | Temps et phase lisibles ; marqueurs HP/priorité séparés de la sphère utile ; thème et FOV indépendants du scaling UI | UI, galerie ; pixels sRGB et projections contrôlés |
| Dimensions et focus | Vérifier 800×450, 1280×720 et 1920×1080 ; aucune action inaccessible ; perte de focus et reprise explicites | UI, app flow, galerie ; matériel Windows non réceptionné |
| Diagnostics EX06 | `null` affiché comme absence de donnée ; origine des événements et censure visibles sans inventer une latence | Runtime, progress et HUD |

## 7. Export, diffusion et matériel

| Étape | Preuve exigée | Résultat actuellement enregistré ici |
|---|---|---|
| Point d’entrée/version | `project.godot` indique 1.0.0 et `MainV2.tscn`, avec contrôleur final complet | Vérifié dans la scène source et le PCK ; runner CAL effectivement instancié |
| Import et suites générales | Logs actuels, assertions de chaque suite, absence d’erreurs malgré exit code nul | 26 runners et 94 tests Python terminés sans échec ; démarrage après import froid, 162 empreintes source inchangées |
| Export Windows x86-64 | PE/MZ, architecture 0x8664, PCK embarqué, ressources/fonts/licences V2 présentes | Vérifié ; export release et pack contrôlés sous Linux |
| Pack lancé hors checkout | Aucun accès dépendant de `res://docs`, Python, Node, Godot Editor ou fichiers locaux oubliés | V2 : 94 assertions, 0 échec ; smokes historiques répétés trois fois sans erreur après isolation audio du fixture QA |
| Nouveau ZIP Windows | `AimLocal-1.0.0-windows-x64.zip` et SHA correspondante, contenu et README embarqué cohérents | CRC, SHA-256, PE, PCK et notices contrôlés ; copié dans `downloads/` |
| Nouvelle galerie | `AimLocal-1.0.0-visuels.zip` et SHA ; captures réelles de la V2 identifiées, pas des concepts présentés comme captures | 70 captures, 536 assertions ; archive et sommes vérifiées |
| Remplacement des anciens ZIP | Vérifier les nouveaux fichiers avant retrait des 0.9 ; conserver la documentation historique | Dernières archives seulement dans `downloads/` ; documents, scénarios et historique Git conservés |
| Lancement natif Windows | Extraire tout le ZIP sur Windows 10/11 x86-64 sans outils de développement installés ; jouer chaque programme et le parcours CAL | À effectuer |
| Souris et scaling | Counts reçus, capture/focus, inversion, cm/360 mesuré à la règle, scaling 100/125/150/200 %, plein écran/fenêtre | À effectuer sur matériel |
| Polling élevé | Souris 1/2/4/8 kHz, réception et pertes sous charge ; distinguer USB/HID, regroupement OS et réception applicative | À effectuer sur matériel |
| Présentation et performances | GPU, driver, résolution, fréquence écran, VSync, frametimes et latence mesurée selon un protocole annoncé | À effectuer sur matériel |
| Pilote humain | Playabilité des tailles/vitesses, fatigue, compréhension des scores, répétabilité et portée de la recommandation | À effectuer ; aucun résultat humain fourni ici |

Un pack ouvert par le moteur Linux établit une disponibilité de ressources, pas un lancement Windows. Des tests headless sans frametimes réels ne certifient pas les seuils de présentation. Des mesures humaines et la précision physique du gain restent des preuves séparées des tests numériques.

## 8. Enregistrer la preuve et clôturer

Pour chaque résultat à renseigner, conserver : révision du code, commande et exit code, log complet de cette exécution, compte réel de tests/assertions, renderer/OS/version moteur, hashes des ressources et paramètres pertinents. Pour le matériel, ajouter souris/polling, GPU/driver, écran/scaling et protocole physique. Pour CAL, conserver plan, conditions, epochs acceptés et invalidés, données brutes, waits et gain exact.

Commandes ciblées reproductibles déjà utilisées :

```bash
python3 -B tools/import_v2_atlas.py --kit docs/reference/v2 --output-dir content/v2 --check
python3 -B tests/v2_atlas_import_tests.py --kit docs/reference/v2
bash tools/godot.sh --headless --script res://tests/v2_catalog_tests.gd
```

Pour une autre suite native, utiliser son chemin réel avec le wrapper, puis renseigner son log. L’import partagé, la suite générale, les captures et l’export sont coordonnés par le propriétaire de l’intégration ; leur résultat n’est pas déduit des commandes ciblées ci-dessus.

La réception 1.0.0 exige les parcours publics terminés, des tests actuels sans erreurs non expliquées, un nouveau pack vérifié, les références conservées et des limites de matériel/humain explicitement annoncées. La seule mise à jour du README ou des liens de téléchargement ne clôture pas cette réception.
