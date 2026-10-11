# QA indépendante — sensibilité et protocole 2

**11 octobre 2026, Europe/Paris.** Base Git `fa5b289` avec modifications de développement en cours ; observations ponctuelles, à retester après intégration des agents.

Périmètre de l’audit initial : lecture de `GameProfileService`, `SensitivityImport`, du Dashboard, de `Main.import_reference_profile`, du stockage/validateur appelés par ce parcours, du service de calibration et des tests de sensibilité. Seul fichier écrit pendant cet audit : `docs/QA_REVIEW.md`. Les constats et chiffres des sections 1–5 sont **historiques, avant correctifs** ; leur suivi retesté figure en section 6.

Périmètre de correction ensuite autorisé : `scripts/sensitivity/game_profile_service.gd`, `scripts/ui/sensitivity_import.gd`, `tests/sensitivity_import_tests.gd` et ce rapport, exclusivement. Aucun import global Godot, export, branche, worktree, commit ou push n’a été réalisé par cette mission.

## Verdict initial — avant correctifs

La séparation entre état canonique et champs d’affichage corrige bien la perte du coefficient CoD dans le convertisseur. L’application du profil importé à la caméra et au prochain exercice, ainsi que le refus d’écriture, sont couverts par la suite ciblée qui passe.

**Réserves avant validation de la strate :** deux réimports peuvent modifier ou réinterpréter le réglage sans nouvelle saisie ; les DPI d’origine remplacent les DPI actifs sans contrat explicite ; un checkpoint version 1 empêche une nouvelle calibration version 2. Les assertions positives ne couvrent pas ces contre-exemples et ne constituent donc pas un feu vert global.

## 1. Constats prioritaires reproduits

### P1 — DPI du jeu source et DPI actuellement utilisés confondus

Repères : `scripts/sensitivity/game_profile_service.gd:69`, `scripts/ui/sensitivity_import.gd:61`, `scripts/ui/dashboard.gd:281`.

Avec profil actif à **1 600 DPI**, importer VALORANT **0,35 à 800 DPI** retourne un profil actif à **800 DPI**, pas seulement une référence historique à 800. La distance calculée est correcte, mais la rotation appliquée vaut **0,0245°/count** au lieu de **0,01225°/count** si la souris reste à 1 600 DPI. Le service ne change évidemment pas le DPI matériel.

Le risque est conditionnel au contrat produit : cela fonctionne si le joueur utilise désormais réellement 800 DPI, mais pas s’il importe un ancien réglage en conservant ses DPI courants. Le formulaire dit « DPI dans ce jeu », alors que le champ « DPI de votre souris » désigne le réglage actif.

**Intégration attendue :** distinguer DPI source et DPI actuels, conserver la distance physique et calculer la sensibilité locale avec les DPI actuels ; ou demander explicitement une confirmation de changement du DPI déclaré. Tester la conversion sortante avec DPI destination distincts, sans la confondre avec ce problème d’import.

### P1 — Réimport CS2 personnalisé : le formulaire reconstruit avec le mauvais yaw

Repères : `scripts/ui/sensitivity_import.gd:66`, `scripts/ui/sensitivity_import.gd:68`, `scripts/ui/sensitivity_import.gd:77`.

Profil source : CS2 **2,0 / 800 DPI / m_yaw 0,0165**, distance **34,636363636364 cm**. Après `bind_profile`, le formulaire conserve `m_yaw = 0,0165`, mais préremplit la sensibilité source avec **1,5**, car il la reconstruit avec le yaw par défaut **0,022**. Le brouillon sans aucune modification devient **46,181818181818 cm** : +33,3 % de distance, soit une rotation 25 % plus lente si appliquée.

La sensibilité AIM/LOCAL 1,5 est correcte pour le profil initial ; c’est son utilisation comme **sensibilité CS2 source** avec le yaw personnalisé qui est incorrecte. Le même chemin par défaut existe lors de la sélection du jeu.

**Intégration attendue :** reconstruire la valeur source avec son coefficient effectivement sélectionné ou restaurer les champs source d’origine. Ajouter un test UI « importer → rouvrir → appliquer sans éditer » avec `m_yaw` personnalisé, et non seulement un test de service.

### P1 — Réimport CoD : mesure historique remplacée par distance active

Repères : `scripts/ui/sensitivity_import.gd:65`, `scripts/ui/sensitivity_import.gd:68`, `scripts/sensitivity/game_profile_service.gd:57`.

Référence mesurée : **Modern Warfare III (2023), 800 DPI, sensibilité 5,0, 34,123456 cm**, coefficient dérivé **0,006699204207217**. Modifier ensuite la distance AIM/LOCAL à **40 cm** conserve légitimement la référence historique. En rouvrant le formulaire, la mesure préremplie devient pourtant **40 cm**, tandis que la sensibilité source reste **5,0**. Le brouillon invente alors un **nouveau coefficient 0,005715**, étiqueté `user_measurement`, sans nouvelle mesure dans le jeu.

La conversion avec le coefficient d’origine donnerait **4,265432** pour 40 cm ; accepter ce nouveau brouillon ramène artificiellement l’équivalent source à **5,0**. Aucune constante CoD générique n’est introduite, mais la provenance d’une mesure utilisateur est néanmoins réinterprétée.

Autre variante reproduite : rouvrir directement la mesure **34,123456 cm** la réduit à **34,12 cm** via le SpinBox de pas 0,01 ; le brouillon change alors légèrement le coefficient même sans éditer. Cette réduction concerne le formulaire de **réimport**, pas `current_distance_cm` qui conserve sa précision.

**Intégration attendue :** décider si le formulaire représente le réglage source historique ou une nouvelle saisie. Ne pas associer une ancienne sensibilité source à une distance locale nouvellement calibrée. Conserver la mesure exacte lors d’une réouverture sans changement et ne recalculer sa provenance qu’après une nouvelle saisie explicite.

### P1 — Ancien checkpoint conservé, mais nouvelle calibration bloquée

Repères : `scripts/sensitivity/calibration_service.gd:120`, `scripts/core/main.gd:377`, `scripts/persistence/local_store.gd:100`.

Un checkpoint JSON de schéma 1 et **protocole 1** est correctement refusé par `restore`. Mais `load_checkpoint()` retourne alors `{}` ; `Main.start_calibration()` ne l’archive pas. Ensuite `save_checkpoint()` refuse de remplacer ce même fichier existant puisque son protocole est incompatible.

Reproduction isolée : après « nouvelle calibration », **`is_calibrating = false`**, écran HOME, message **« Checkpoint existant incohérent conservé ; sauvegarde refusée. »** La consigne « démarrez une nouvelle comparaison » ne fonctionne donc pas pour cette migration.

**Intégration attendue :** archiver explicitement un ancien protocole reconnu et bien formé avant de démarrer le nouveau ; conserver le refus de remplacement pour les fichiers réellement corrompus ou inconnus. Ne pas supprimer silencieusement les données. Cette observation porte sur la persistance, pas sur la présentation SessionPanel en cours.

## 2. Points solides et limites de couverture

- **Précision canonique :** `Dashboard.current_distance_cm` alimente `read_profile` et les conversions, indépendamment des chiffres visibles. Vingt appels de `sync_sensitivity` n’ont pas changé la distance exacte testée. L’écriture JSON conserve la précision dans la suite existante.
- **Coefficient CoD exact :** `destination_yaw_deg` conserve le coefficient ; `set_conversion_yaw` remplit le SpinBox sans relire sa valeur arrondie. Avec un coefficient **0,000000000958893**, le champ affiche zéro mais l’état reste non nul et la conversion retourne **99 999,999999999985**, conformément à la valeur source 100 000 à la précision flottante près. Le calcul est corrigé ; l’affichage « 0 » mérite une notation scientifique ou une explication pour ne pas induire une modification accidentelle.
- **DPI destination distincts :** la référence CoD 5,0 à 800 DPI devient **2,5 à 1 600 DPI** dans le convertisseur. Ce parcours passe ; il n’annule pas la réserve sur les DPI actifs lors de l’import.
- **Application :** la suite vérifie l’import VALORANT, la rotation immédiate **0,0245°/count**, la sauvegarde/relecture et le prochain C03. `Main` sauvegarde avant `bind_profile`/`apply_profile` ; l’import est ignoré hors HOME. Le prochain exercice utilise `home.read_profile`, pas le défaut.
- **Refus d’écriture :** test complémentaire sur fichier de profil à schéma 999 : dictionnaire UI, rotation caméra et octets du fichier inchangés ; message de refus visible. Pas de succès annoncé après ce refus.
- **Types invalides :** `validate_reference` rejette les références non dictionnaires et les mutations testées : `game_id` entier, titre entier, DPI chaîne, sensibilité booléenne, yaw NaN, distance infinie, confiance tableau, CoD étiqueté `documented`.
- **CoD :** `default_yaw` n’a pas de valeur CoD ; le service exige un titre non vide et une distance mesurée, avec confiance `user_measurement`. Cela ne certifie ni la mesure physique ni le build/mode : « titre et version » reste un champ libre non vide, pas une validation automatique de version. Ne pas annoncer une certification par l’éditeur.

**Durcissement supplémentaire à tester, non exécuté :** `Main.import_reference_profile` suppose que `reference_game` existe. Or `SensitivityService.validate_profile` accepte légitimement un profil local sans référence. Un appel direct avec ce profil peut être sauvegardé/appliqué puis atteindre `profile.reference_game.title` absent. Le signal UI normal fournit bien la référence ; ajouter une précondition explicite au handler serait utile pour ses appels futurs et les tests d’API.

Les métadonnées source peuvent rester différentes de la sensibilité active après réglage/calibration : c’est une origine historique utile. **Ne pas imposer `reference_game.source_cm_per_360 == profile.cm_per_360`**, ce qui empêcherait de calibrer un profil importé. En revanche, le formulaire ne doit pas présenter le mélange des deux comme une nouvelle mesure réellement réalisée.

## 3. Cinq groupes de contre-exemples à intégrer aux tests permanents

| Cas | Entrées / actions | Attendu et observation actuelle |
|---|---|---|
| CE-1 — DPI source différents | DPI actifs 1 600 ; importer VALORANT 0,35, DPI source 800 ; ne pas changer la souris. | Préserver 1 600 DPI actifs ou confirmer explicitement leur changement ; attendu 0,01225°/count avec la même distance. Actuellement : actifs remplacés par 800, rotation 0,0245. Tester aussi destination 1 600, conversion 0,175. |
| CE-2 — Réouverture CS2 custom | CS2 2,0 / 800 / yaw 0,0165 ; rouvrir, appliquer sans éditer, répéter. | Même coefficient, même valeur source et même distance ; actuellement le premier brouillon passe de 34,636363636364 à 46,181818181818 cm. Contrôler le service **et** les champs UI. |
| CE-3 — Mesure CoD historique et décimales | CoD Modern Warfare III (2023), 800 / 5 / 34,123456 ; rouvrir ; puis changer localement à 40 cm et rouvrir encore. | Le coefficient historique ne change pas sans nouvelle mesure ; actuellement arrondi à 34,12, puis réinterprétation de 40 cm comme mesure de la sensibilité source 5. Préserver la précision et expliciter historique/nouveau profil. |
| CE-4 — Coefficient invisible dans le champ | CoD mesuré, 64 000 DPI / sensibilité 100 000 / 149 cm ; changer jeu aller-retour, sauvegarder/recharger, rafraîchir sans éditer le yaw. | L’état exact reste distinct du champ arrondi à zéro. Conversion ≈ 100 000 et copie non nulle ; sous-cas initial testé et passant. Compléter les changements de jeu/rechargements. Une édition volontaire du coefficient doit rester identifiée comme manuelle. |
| CE-5 — Refus, métadonnées et migration | Profil existant corrompu ; référence avec mauvais types/confiance ; profil local sans référence envoyé directement au handler ; checkpoint bien formé de protocole 1. | Aucun profil/caméra/fichier modifié lors d’un refus ; erreur explicite sans crash pour l’API ; nouvelle calibration possible après archivage contrôlé d’un ancien protocole. Refus et types testés positivement ; migration reproduite bloquante ; handler sans référence encore à tester. |

Tolérances : distances/rotations canoniques comparées en `float` sans quantification intermédiaire ; la suite utilise **1e−9** pour les exemples usuels. Pour valeurs extrêmes, définir également une tolérance relative raisonnable : la représentation flottante de 100 000 diffère d’environ 1,5e−11 ici. Les nombres copiés à six décimales ont leur propre erreur d’arrondi assumée, à distinguer du profil canonique.

## 4. Protocole 2 : vérification qualitative et logique

Le service contient maintenant **cinq blocs contigus de douze passages** : **trois familiarisations de 8 s puis neuf essais mesurés de 12 s** pour le même exercice. Total : 15 familiarisations et 45 mesurés. Il ne conserve pas par erreur l’ancienne phase de quinze familiarisations globales avant toutes les mesures.

Les trois répétitions d’un exercice utilisent un décalage cyclique des candidats, avec décalage supplémentaire par index d’exercice : chaque candidat occupe exactement une fois chaque position. Par exemple C02 : ABC, BCA, CAB ; C04 : BCA, CAB, ABC. Les candidats d’une même répétition partagent leur graine ; les répétitions et la familiarisation utilisent des graines distinctes. `block_index` suit le scénario. Ces invariants ont été vérifiés directement sur les 60 étapes.

**Qualitativement cohérent avec le parcours demandé** : apprendre un exercice, comparer les réglages sur celui-ci, puis passer au suivant. Les protections d’acceptation, les trois observations par cellule, le confort, les scores et les statuts incertains sont conservés en lecture du service. Le test ciblé ne rejoue pas une calibration complète avec recommandations ; sa portée est le plan et le rejet de l’ancienne version.

Limites à communiquer et à tester :

- Familiarisation A/B/C toujours dans le même ordre ; ordre des exercices fixe C02 → C04 → S01 → T01 → T05. Pas de contrebalancement complet entre exercices/séances ni de garantie contre la fatigue locale.
- Ordre cyclique équilibré par position, mais pas toutes les six permutations ni tous les effets de report d’un réglage au suivant. Garder la prudence du conseil et une confirmation différée.
- Une graine commune n’impose pas des apparitions identiques aux mêmes instants dans les tâches où les impacts déclenchent les remplacements.
- Un repos plus long choisi entre blocs doit être proposé/consigné sans modifier silencieusement la difficulté ou les critères d’acceptation. L’animation/HUD ne doit pas changer le timing logique.
- Les tests métier actuels comptent cellules/graines/positions, mais ne prouvent pas à eux seuls l’organisation **3 + 9 contiguë** : ajouter le contrôle explicite exercé ici. L’expression historique `(stage_index - 15) % 3` reste alignée parce que les blocs et la phase warm-up sont multiples de trois ; elle ne documente pas le nouveau bloc et devrait être rendue explicite dans les tests futurs.
- `docs/CALIBRATION.md` et `docs/DECISIONS.md` décrivent encore le protocole 1 à cette lecture ; mise à jour à confier au parent, sans modification par cette mission. Résoudre surtout l’archivage/migration avant de promettre « recommencer » aux utilisateurs de la version précédente.

## 5. Commandes et portée des vérifications exécutées

Validation temporaire hors dépôt : `/tmp/aimlocal-sensitivity-qa.gd`, données sous des dossiers uniques `/tmp/aimlocal-sensitivity-qa-*` et `user://tests/<identifiant>` de la suite existante. Aucun profil utilisateur produit n’est écrasé.

```text
timeout 45s bash tools/godot.sh --headless --script /tmp/aimlocal-sensitivity-qa.gd
```

Godot **4.7.2 standard**. Deux passes ciblées : la première **245 assertions, 0 échec** ; la seconde, avec vérifications de rafraîchissement/DPI destination et observation de migration, **247 assertions, 0 échec**, dont **39** issues de `tests/sensitivity_import_tests.gd`. Journaux sans `ERROR`/`SCRIPT ERROR`, dernier code de sortie 0. Le typage `altered`/`reloaded` compile désormais correctement.

Les assertions vérifient les invariants encore corrects ; les contre-exemples de défauts sont des **observations numériques et d’état consignées**, pas encore des assertions rouges ajoutées au dépôt. Aucun résultat « suite entière verte » n’est annoncé.

Non exécutés : imports/exports globaux, suite globale, rendus graphiques, capture physique souris/DPI, écoute, exécution Windows native, mesure dans un jeu tiers ou validation du protocole par de vrais joueurs. Aucun coefficient tiers supplémentaire n’a été recherché ou validé.

**À transmettre au parent :** corriger le rebinding CS2 et CoD, arbitrer/concrétiser DPI source vs actifs, débloquer la migration contrôlée des checkpoints, ajouter les cinq groupes de tests permanents et mettre à jour les documents du protocole. La présentation SessionPanel reste dans le périmètre du parent.

## 6. Correctifs intégrés et retestés — code gelé

Suivi du **11 octobre 2026, Europe/Paris**. Cette section remplace les réserves initiales pour les parcours explicitement retestés ci-dessous ; elle ne réécrit pas les observations antérieures.

### Fichiers corrigés dans le périmètre exclusif

- `scripts/sensitivity/game_profile_service.gd:42` : validation du profil actif avant import ; conservation de ses DPI et préférences. Les DPI de la source restent dans `reference_game.dpi`. Une mesure manuelle est conservée directement, sans inversion numérique superflue. Si les entrées source correspondent exactement à l’historique, le service reprend l’ensemble des métadonnées et son coefficient sans les reconstruire, même si la distance active a changé.
- `scripts/ui/sensitivity_import.gd:70` : restauration depuis les **DPI, sensibilité, mesure et yaw source historiques**, pas depuis la valeur locale. Les SpinBox ne quantifient plus ces valeurs (`step = 0`), tandis que `custom_arrow_step` conserve des incréments utilisables. Les nouveaux profils manuels démarrent à une mesure **0**, invalide tant qu’une mesure réelle n’est pas fournie. Les valeurs hors limites restent visibles et sont refusées par le service au lieu d’être clampées en mesures plausibles.
- `scripts/ui/sensitivity_import.gd:102` : aperçu de la sensibilité locale avec les **DPI actifs conservés**, actualisé sans réinitialiser les champs source. Le libellé « DPI du jeu source » et l’explication « Réglage source d’origine » distinguent restauration de l’ancien réglage et modification du réglage actif.
- `tests/sensitivity_import_tests.gd:105` : tests adversariaux permanents du service, des champs UI, de réimports successifs, de profils relus sur disque, de nouveaux profils sans mesure et de la précondition Main fournie par le parent.

Les signatures de `import_profile`, `bind_context`, `select_game`, `draft` et du signal `profile_requested` sont **inchangées**. Le schéma du profil n’est pas modifié : `profile.dpi` désigne toujours les DPI actifs, `reference_game.dpi` les DPI source.

### Suivi des réserves initiales

| Réserve | Correction / intégration | Résultat retesté |
|---|---|---|
| DPI source confondus avec actifs | Service corrigé ici ; Dashboard parent transmet seulement distance/référence et rafraîchit le contexte actif du formulaire sans réinitialiser ses entrées. | Source VALORANT 0,35 / 800, actifs 1 600 : distance préservée, caméra puis prochain C03 à **0,01225°/count**. Changer les DPI actifs après ouverture garde les champs source 800 / 0,35 et actualise l’aperçu à 1 600 DPI. |
| Réouverture CS2 custom | Champs restaurés depuis l’historique, coefficient personnalisé conservé ; pas de reconstruction avec 0,022. | Valeurs source à nombreuses décimales et DPI source fractionnaires conservés exactement ; changement de jeu aller-retour et cinq réimports sans édition gardent référence/coefficient identiques en mémoire. |
| CoD : mesure historique réinterprétée / arrondie | Mesure historique distincte de la distance active, pas de quantification, restauration du coefficient historique. | CoD et custom, mesure précise **34,12345678901234** ou **42,12345678901234**, distance locale modifiée à 45 : réimport restaure la source, sans réécrire son coefficient. Une nouvelle mesure explicitement éditée recalcule correctement le nouveau profil. |
| Nouveau profil manuel prétendument mesuré | Mesure initiale 0 et bouton d’import désactivé tant que la mesure n’est pas valide. | CoD/custom sans historique : 0 refusé ; mesure négative ou 151 cm refusée sans clamp ; DPI source 0 ou 64 001 refusés sans clamp ; vraie mesure débloque l’import. |
| Référence absente / malformée dans Main | Précondition ajoutée par le parent avant sauvegarde/bind/apply ; tests ajoutés ici. | Absence, null, booléen, tableau, chaîne, dictionnaire vide, types numériques/provenance erronés : **UI, paramètres caméra et octets du fichier inchangés**, erreur visible sans succès annoncé. |
| Sauvegarde refusée | Transaction existante conservée et contrôlée plus largement. | Fichier à schéma 999 : pas de modification de l’UI, de la caméra ou des octets sauvegardés. |
| Checkpoint version 1 bloquant | Pris en charge par le parent/agent chargé de la migration, hors des fichiers corrigés ici. | La dernière suite globale inclut les tests de migration et passe. Aucun changement de stockage ou de Main n’a été réalisé par cette mission. |

Le coefficient CoD très petit reste exact dans l’état du convertisseur parent, malgré l’arrondi du champ ; il est conservé également par les réimports historiques du formulaire. Les détails du convertisseur affichent désormais le coefficient réel via le correctif parent, sans le format GDScript `%g` non supporté. **Aucune constante CoD générique n’est ajoutée.**

### Précision et portée du verdict

Le service et le formulaire sont testés avec égalité exacte pour les métadonnées historiques en mémoire, y compris après une réouverture sans édition. La relecture JSON Godot de certains coefficients peut déplacer les derniers bits : exemples observés **0,006682703549872773 → 0,00668270354987277** et **0,006762758589958955 → 0,00676275858995895**. Ce n’est pas un arrondi au pas d’un contrôle ni une reconstruction de la mesure.

Les tests de stockage utilisent une tolérance **relative 1e−14** pour ces nombres, une égalité exacte pour les métadonnées textuelles, puis vérifient que le réimport d’une référence relue conserve **exactement le coefficient relu**, sans le recalculer. Cette limite du parseur ne doit pas être présentée comme une conservation bit à bit sur disque ; aucun changement du stockage hors périmètre n’est effectué.

### Dernière validation exécutée

```text
bash tools/test.sh
```

- **AIM/LOCAL : 2 186 assertions, 0 échec, 1 contrôle non exécuté** — capture physique du pointeur en headless.
- **GEOMETRY REGRESSION : 1 560 assertions, 0 échec** — lancée par le runner du parent ; projection Camera3D sans validation graphique physique.
- Code de sortie **0**, dernier journal `/tmp/aimlocal-sensitivity-integrated.log` sans `ERROR` ni `SCRIPT ERROR`. La passe précédente comptait 2 183 assertions ; les trois dernières assertions vérifient l’aperçu live et la conservation des champs source lors d’un changement des DPI actifs.
- Les passes intermédiaires rouges ont signalé l’adaptation Dashboard des DPI et son format `%g` ; les correctifs parent sont inclus dans cette dernière passe. Les chiffres 245/247 de l’audit initial restent historiques et ne constituent pas ce verdict post-correction.
- Contrôle des espaces dans les quatre fichiers autorisés : aucun diagnostic. Aucun import `.godot`, export global ou nouveau rendu graphique n’a été lancé par cette mission.

**Code gelé après cette passe**, sans modification supplémentaire pour les opérations de cold import/export du parent. Les quatre fichiers autorisés sont le seul périmètre modifié ici. La réception visuelle post-correctifs, le cold import/export, le matériel et Windows natif restent à la charge du parent/joueur ; aucun de ces essais n’est prétendu exécuté par cette mission.
