# Sensibilité progressive — protocole 5, application 0.8.0

Les nouvelles calibrations suivent toujours cinq activités × cinq sensibilités × 45/60 s, avec les **variantes temporaires r6**. Clic/transitions : cible rétrécissante puis expiration pénalisante, score V2 = cadence × (touches/(tirs+expirations))² / référence. Suivi : cycles avec plancher de taille positif, réapparition ailleurs et réacquisition ; formule de temps sur cible inchangée à difficulté différente. Les cycles sont seedés et ne dépendent pas de la sensibilité, des scores ni des FPS. Voir `EXERCISE_DESIGN_080.md`.

Un checkpoint/bilan **protocole 4** de 0.7 se reconstruit sur ses références r3/r4/r5 et scores V1 d’origine. Le protocole fait partie de l’enveloppe, les empreintes sont contrôlées et la reprise n’adopte pas silencieusement les nouveaux cycles. Un nouveau départ utilise le protocole 5 et archive le parcours précédent selon les mêmes protections. Anciennes mesures et nouveaux records restent séparés.

## Parcours actuel

**Cinq activités, cinq sensibilités par activité, 60 secondes par essai** (45 s au choix). Le DPI déclaré ne change pas. Ordre : C02 micro-précision → C04 grands mouvements → S01 transitions → T01 suivi horizontal → T05 suivi réactif. Les résultats affichent score, touches/ratés, précision et temps sur cible ; aucun questionnaire de confort ne conditionne la recherche.

Le profil lent/normal/rapide ou la sensibilité importée fixe la référence. « Réglage connu » explore initialement les facteurs de vitesse 1/1,2 à 1,2 ; « Nouveau réglage » explore 1/1,6 à 1,6. Les bornes physiques restent 5–150 cm/360°. Une vitesse supérieure correspond à une distance cm/360° inférieure.

1. Essai 1 au réglage de référence ; essai 2 au bord plus rapide. À la borne rapide physique, on teste le côté encore disponible.
2. Si l’essai 2 est meilleur, essai 3 entre les deux vitesses, en espace logarithmique. Sinon, essai 3 plus lent que **l’essai 1**, pas seulement que l’essai 2.
3. Les essais 4 et 5 remplissent les intervalles non testés autour du meilleur score. Dans la première activité novice, un meilleur score au bord peut élargir ce côté une fois, avant d’affiner. Tous les réglages d’un bloc sont distincts.
4. Après cinq essais, le meilleur réglage devient la référence de l’activité suivante. Ses voisins testés délimitent la nouvelle zone, limitée à 70 % de la largeur logarithmique précédente. Les activités suivantes ne réélargissent pas cette zone.
5. Après 25 mesures, **Votre sensibilité** fournit le meilleur réglage testé dans la dernière activité, avec **Appliquer**. Ce bouton enregistre la valeur canonique exacte, actualise la caméra et ouvre la conversion ; l’affichage à deux décimales ne quantifie pas l’input.

Les comparaisons utilisent l’utilité **non arrondie**, uniquement à l’intérieur d’une activité : clic/switching = touches par seconde × précision² ; tracking = temps sur cible / temps exposé. Le score visible V1 conserve sa formule et son arrondi. En cas d’égalité numérique, la référence du bloc est privilégiée ; un écart minuscule ne provoque pas une décision différente après lecture JSON. Les mesures inactives, incomplètes, invalides ou trop saccadées sont rejetées et rejouées.

Chaque essai a 3 s de préparation sonore, puis une durée mesurée entière, puis au moins 3 s de repos avec validation explicite. Minimum : 27 min 30 à 60 s, 21 min 15 à 45 s, hors pauses supplémentaires/rejoués. Aucune donnée de préparation n’entre dans le score. Une graine commune par activité rend son départ reproductible ; des touches à des instants différents peuvent ensuite déclencher des respawns différents. Il ne s’agit pas de cinq vidéos identiques.

`progressive_calibration_checkpoint.json` contient référence, durée, ratio, graines, empreintes et rapports acceptés. La reprise rejoue ces rapports validés pour reconstruire les décisions, sans faire confiance à une fenêtre dérivée sérialisée. Une panne d’écriture restaure l’état précédent et garde le passage en mémoire. Un nouveau parcours archive exactement les octets du précédent ; fichiers corrompus, archives contradictoires et verrous ne sont pas écrasés. Le bilan immuable est revérifié depuis son historique avant sauvegarde/application. Les anciens fichiers de protocoles 1–3 ne sont ni remplacés ni convertis en protocole 4.

## Portée du réglage retenu

Ce parcours fournit **un réglage concret**, pas une plage à interpréter. C’est une recherche adaptative successive, dépendante de l’ordre des activités, de l’apprentissage et de la fatigue. Le réglage final a été mesuré dans la dernière activité ; il n’a pas été retesté dans toutes les activités précédentes. Cinq sensibilités testées une seule fois chacune ne constituent pas cinq répétitions statistiques par sensibilité. La réduction de fenêtre est une heuristique documentée, pas un intervalle de confiance ni une preuve d’optimum universel.

L’application ne détecte pas le DPI réel, ne modifie aucun jeu et ne prouve pas le transfert d’un score vers un FPS. La conversion conserve la rotation physique, pas une équivalence ADS/FOV/ressenti. La réception souris et le contrôle physique cm/360° restent nécessaires.

## Historique conservé — protocole 3

Les sections suivantes décrivent les anciens services conservés pour les données et leurs régressions. Ces parcours courts et leurs commandes ne sont plus proposés par l’interface publique 0.7.

## Deux parcours

**Comparer mon réglage** conserve une comparaison à ±10 % : cinq exercices, 60 passages dont 45 mesures, environ 17 minutes minimum. Les facteurs deviennent configurables, mais chaque candidat et difficulté restent fixes pendant un passage et sa comparaison.

**Trouver mon réglage** utilise une recherche expérimentale bornée à quatre comparaisons complètes, jamais deux mini-exercices suffisants pour conclure :

1. Explorer des vitesses angulaires **0,5 / 1 / 2 × centre**, soit des distances **2 / 1 / 0,5 × centre**.
2. Centre dominant : affiner à **0,75 / 1 / 1,25**, puis valider à **0,9 / 1 / 1,1**.
3. Bord gagnant au-delà du seuil heuristique, confort médian > 2/5 dans chacun des cinq exercices : déplacer le centre vers ce réglage réellement testé et garder une exploration large, maximum deux déplacements. Si un bord gagne pendant l’affinage, recentrer plutôt la validation étroite sur ce meilleur essai ; une validation centrale doit encore être rejouée avant tout conseil.
4. Égalité, manque de signal, inconfort, bord persistant, borne physique ou limite d’essais : arrêter sans conseiller un changement définitif. Profil initial intact.

La plage reste 5–150 cm/360°. Trois candidats distincts imposent un centre d’exploration entre 10 et 75 cm/360° ; les phases plus étroites ont leurs propres bornes. Un départ hors centre est explicité et sauvegardé séparément, pas réécrit silencieusement comme profil actif. DPI, objectif, FOV, ratio et input restent constants. Les graines changent par comparaison avec un pas déterministe de 104 729 et restent communes entre candidats d’une même série.

Un trajet stable prend généralement trois comparaisons, parfois quatre : **51–68 minutes minimum**, hors pauses supplémentaires. L’incertitude peut l’arrêter plus tôt sans conseil applicable. La difficulté ne s’ajuste pas pour faire gagner une sensibilité : seuls les candidats de la prochaine comparaison changent.

Le contrôleur reconstruit ses décisions depuis les 60 passages vérifiés de chaque bilan, sa dispersion, ses poids et le confort. Gagnant arbitraire et historique modifié sont refusés. `guided_calibration_checkpoint.json` écrit recherche et comparaison ensemble ; une panne annule l’avancement mémoire. Reprendre un bilan accepté ne le compte pas deux fois.

Après validation stable : `trial_allowed=true`, `confirmation_required=true`, `apply_allowed=false`. **Essayer ce conseil** exige le consentement ; profil provisoire, pas validation scientifique définitive. Refaire les essais à deux puis sept jours, contrôler confort et distance en jeu reste recommandé. Aucun transfert causal vers un FPS n’est prouvé.

Le protocole 3 restaure un protocole 2 seulement si ses exercices restent identiques. La 0.5 change leur difficulté : les checkpoints 0.3/0.4 reconnus sont vérifiés avec un contexte historique figé, puis archivés octet pour octet avant une nouvelle comparaison. La recherche guidée est vérifiée avec son historique de décisions, pas seulement son dernier passage. Un fichier inconnu ou incohérent bloque l’écrasement ; les séances restent conservées, sans mélange de révisions.

Chaque départ montre les cibles initiales figées pendant **3, 2, 1**, puis mesure à partir de **GO**. La disposition utilise la même graine au départ, sans inclure la préparation dans les scores. Aucun tir n’est enregistré pendant le décompte ; la caméra conserve les vrais mouvements reçus. Les 60 décomptes, 15 × 8 s, 45 × 12 s et 60 repos minimaux de 3 s (dernier bilan compris) donnent **1 020 s (17 min)** hors saisie du confort, pauses et répétitions. Les exercices sont explicités dans `EXERCISE_DESIGN_050.md`.

## Ce que signifie la recommandation

L'application cherche **le meilleur compromis parmi trois réglages réellement testés**, pour les DPI et l'objectif déclarés. Elle ne découvre pas une « sensibilité parfaite » universelle. Fatigue, habitude, FOV, rôle dans le jeu, posture et matériel peuvent changer le résultat. Trois répétitions courtes ne prouvent pas un gain durable ; refaire le test à un autre jour est indispensable.

Les valeurs de départ sont 800 DPI et 35 cm/360° si aucun profil n'existe. Les DPI doivent être renseignés depuis le logiciel/la mémoire de la souris. L'application ne les détecte pas et ne certifie pas les counts physiques. Avant les comparaisons, mesurer un tour de 360° à la règle dans le test souris, puis garder matériel, FOV, format d'écran, mode d'accumulation et limite FPS constants.

## Pourquoi ces cinq tests

| Test | Rôle dans la décision | Mesure principale |
|---|---|---|
| C02 micro-précision | Contrôle de la fin du geste sur petites cibles | Cadence de touches × précision² |
| C04 grands flicks | Portée du geste et compromis vitesse/précision | Même utilité, avec acquisitions et dispersion visibles |
| S01 switching | Transitions rapides entre plusieurs cibles | Même utilité ; temps entre touches |
| T01 suivi fluide | Stabilité des corrections lentes | Fraction du temps réellement sur cible |
| T05 strafes | Réacquisition lors des changements de direction | Même fraction ; erreur et réacquisitions visibles |

Ces contraintes se complètent. Un réglage favorisant uniquement les gros flicks ne doit pas gagner un profil polyvalent au détriment du contrôle fin ; un objectif tracking peut légitimement donner un poids supérieur aux suivis.

## Parcours répété

- Trois vitesses angulaires : **A = 0,90 × référence**, **B = référence**, **C = 1,10 × référence**. En distance, les candidats sont `cm_ref / facteur` : 38,889 / 35 / 31,818 cm/360° pour un départ à 35.
- **Cinq blocs de douze passages**, dans l’ordre C02 → C04 → S01 → T01 → T05. Dans chaque bloc : A/B/C en familiarisation de 8 s, puis trois séries de trois essais mesurés de 12 s. On termine les comparaisons d’un exercice avant le suivant.
- Total : **15 familiarisations**, exclues du classement et de la progression, et **45 mesures** ; trois observations par cellule exercice/réglage.
- Compte à rebours de 3 s et repos minimal de 3 s par passage, confort de 1 à 5. Minimum total proche de 17 min ; augmenter le repos librement et interrompre en cas de douleur/fatigue.
- Chaque candidat occupe une fois chaque position dans les trois séries d’un exercice, avec un décalage supplémentaire par exercice. Les trois candidats partagent une graine par série ; familiarisations et séries ont des graines distinctes. L’ordre des exercices est fixe : les effets de fatigue entre blocs ne sont pas entièrement contrebalancés. Les remplacements déclenchés par un impact ne surviennent pas nécessairement au même instant pour deux joueurs.
- Le HUD indique l’exercice, A/B/C et la série. Le bilan de passage montre la sensibilité actuelle et les médianes A/B/C disponibles, avec le nombre de mesures. Ce parcours explicite n’est pas une étude en aveugle.
- Le checkpoint conserve les passages acceptés et les paramètres. Abandonner ou refaire ne valide rien : le même candidat/graine recommence. Un passage valide est aussi refaisable après le repos minimal, avant de choisir Continuer. Une nouvelle calibration archive le checkpoint précédent. Un protocole 1 reconnu est archivé, jamais interprété selon le nouvel ordre ; un fichier incohérent ou inconnu reste protégé.

Le départ doit être entre 5,5 et 135 cm/360° afin de produire trois candidats distincts dans les limites 5–150 cm/360°. Le FOV doit contenir les cinq scénarios.

**Passage à refaire** : interruption, changement de format, mauvaise révision/graine/profil, tampon saturé, absence de mouvement, moins de trois tirs pour un exercice de clic, ou performances très instables. Garde-fou provisoire explicite : p99 des frametimes > 50 ms ou une frame active > 250 ms ; au moins deux frames doivent être observées. Ces seuils sont heuristiques et ne certifient pas une latence satisfaisante. Les statistiques affichent aussi les événements reçus, qui ne sont pas le polling matériel.

## Scores transparents

### Clic, flick et switching

`précision = touches / tirs`, `cadence = touches / secondes_actives`.

`utilité = cadence × précision²`.

`score_v1 = arrondi(1000 × utilité / cadence_de_référence)`.

Exemple : 30 touches sur 40 tirs en 30 s → précision 0,75, cadence 1/s, utilité 0,5625/s. Avec une référence de 2/s : score 281. Garder 30 touches mais spammer jusqu'à 80 tirs réduit le score à 70. Sans tir : précision **N/A**, score zéro. Chaque pression compte une fois ; aucun autofire par maintien.

Les cadences de référence sont des normalisations de conception, **pas des normes empiriques ou des percentiles de population**. Il n'y a pas de plafond artificiel au score de clic, afin qu'une amélioration réelle reste visible chez un joueur déjà rapide. Le nombre brut de points ne compare pas directement la difficulté de deux exercices.

### Tracking

`utilité = secondes_sur_cible / secondes_exposées` et `score_v1 = arrondi(1000 × utilité)`.

Le rayon angulaire du viseur à la cible est évalué aux milieux de pas fixes à **240 Hz**, avec maintien de la dernière pose horodatée connue. Le dernier pas partiel est intégré à la fin. Sur 12 s, 7,2 s dans la sphère donnent 600 points. Clics/maintien du bouton n'ajoutent pas de score.

L'erreur moyenne est pondérée par le temps ; p95 utilise un histogramme de 0,1° et renvoie la borne supérieure du bin. La réacquisition mesure les passages hors-cible → sur-cible, y compris l'acquisition initiale. Ce n'est ni une détection physique du temps de réaction ni une mesure de latence périphérique.

### Mesures complémentaires

Tirs, touches, ratés, expirations, précision premier tir, touches/minute, temps d'acquisition ou transition médian/p95, erreur médiane au clic, efficacité médiane de trajet, temps sur cible, erreur moyenne/p95, réacquisition, counts/événements reçus et frametimes. L'efficacité de trajet est un diagnostic borné : distance angulaire initiale moins le rayon, divisée par le trajet yaw/pitch accumulé, pour les cibles statiques ; elle n'entre pas dans le score V1. Les valeurs brutes et le contexte restent exportables.

## Recommandation explicable

1. Exiger trois passages mesurés actifs, complets et valides dans chacune des 15 cellules exercice/candidat. Un exercice où tous les candidats ont une utilité nulle ne fournit pas de signal : bilan insuffisant.
2. Calculer la **médiane** de l'utilité et la dispersion robuste `1,4826 × médiane(|utilité − médiane|)` dans chaque cellule.
3. Normaliser les médianes uniquement **à l'intérieur du même exercice**, en divisant par la meilleure médiane de cet exercice. Ne pas mélanger directement secondes de tracking et cadence de flick.
4. Combiner selon l'objectif fixé avant de commencer :

| Objectif | C02 | C04 | S01 | T01 | T05 |
|---|---:|---:|---:|---:|---:|
| Polyvalent | 20 % | 20 % | 20 % | 20 % | 20 % |
| Précision | 30 % | 25 % | 20 % | 15 % | 10 % |
| Tracking | 10 % | 10 % | 10 % | 35 % | 35 % |

5. Pondérer également les dispersions normalisées. Déclarer un avantage seulement si l'écart avec le deuxième dépasse `max(0,03 ; sqrt(dispersion_best² + dispersion_second²))`. Ce garde-fou est **heuristique**, pas un test de significativité ou un intervalle de confiance.
6. Si les réglages restent proches, proposer l'intervalle des candidats compatibles avec ce seuil et conserver la référence. Les égalités exactes privilégient le candidat central, pas arbitrairement un bord.
7. Si le candidat gagnant a un confort médian ≤ 2/5, empêcher l'application. Ne pas masquer les douleurs derrière un score plus élevé.
8. Sinon, autoriser **Appliquer**, sans action automatique. La distance appliquée est arrondie à 0,001 cm et enregistrée dans le profil. Si le meilleur testé est au bord, proposer une nouvelle calibration centrée sur lui ; même protocole, sans extrapolation vers un optimum non testé.

Le bilan sauvegarde tous les passages, médianes par exercice, poids, dispersions, plage, statut, paramètres et versions. L’interface présente aussi les cinq comparaisons A/B/C de scores médians bruts : ce sont des résultats explicatifs, pas des points additionnés entre tâches. Après fermeture, **Revoir le dernier bilan** permet de retrouver la décision. Un changement d'algorithme doit changer sa version et ne doit pas réécrire les séances passées.

## Bibliothèque exécutable

Tous les scénarios ont une difficulté fixe, des trajectoires/générations déterministes par graine, une profondeur nominale spécifique à l’exercice et les mêmes protections de pause/focus. Le pool positionne les cibles depuis l’origine réelle de la caméra. Le diamètre est angulaire, pas automatiquement adapté à la résolution. Six sphères suffisent au pool. Les ressources sont en révision 3 : leur empreinte interdit de mélanger les anciens scores ou de reprendre une ancienne calibration avec cette géométrie. Le tableau détaillé et les raisons de cadrage sont dans `EXERCISE_DESIGN_050.md`.

| ID | Exercice | Cibles | Diamètre | Particularité / référence clic |
|---|---|---:|---:|---|
| C01 | Static Single | 1 | 3,2° | Départ confortable ; 2 touches/s |
| C02 | Micro-précision | 1 | 2,5° | Corrections courtes ; 1,6/s |
| C03 | Grid Targets | 6 | 4,8° | Grandes cellules libres d'une grille 3×3 ; 3/s |
| C04 | Grands flicks | 1 | 3,2° | Écart minimal 20° ; 1,8/s |
| C05 | Sixshot précis | 6 | 0,7° | Petites cibles dispersées ; 2,4/s |
| C07 | Flicks verticaux | 1 | 3° | Zone verticale ±20° ; 2/s |
| D01 | Pop-up | 1 | 3,4° | Expiration après 1 s ; 2/s |
| D02 | Clic mobile | 1 | 3° | Oscillation horizontale ; 1,8/s |
| T01 | Suivi horizontal fluide | 1 | 4° | Sinusoïde horizontale |
| T02 | Suivi vertical | 1 | 3,6° | Sinusoïde verticale |
| T03 | Suivi diagonal | 1 | 3,4° | Yaw et pitch couplés |
| T04 | Circle Track | 1 | 3,4° | Boucle elliptique yaw/pitch |
| T05 | Suivi de strafes | 1 | 3,6° | Déplacements latéraux, retournements continus de 160 ms |
| T09 | Far Small | 1 | 0,9° | Suivi de petite cible, vitesse réduite |
| S01 | Target switching | 4 | 3,4° | Transitions entre touches ; 2,8/s |
| S02 | Moving Switch | 4 | 3,2° | Couloirs séparés ; 2,4/s |

Les paramètres complets résident dans les `.tres`. T03 normalise les amplitudes couplées pour respecter la vitesse angulaire totale annoncée ; l’ellipse a une vitesse variable bornée. S02 utilise des couloirs distants de 6° pour éviter le chevauchement de ses cibles mobiles. La totalité de la sphère, y compris aux coins du champ, doit rester dans le viewport et au-dessus du sol. Rendu et collision partagent le même rayon. C05/T09 conservent volontairement leurs petites cibles avancées. Pas d’adaptation automatique pendant un passage ni de difficulté cachée.

## Conversion et progression

`degrés/count = 914,4 / (DPI × cm360)`.

`sensibilité_jeu = 914,4 / (DPI_destination × cm360 × yaw_jeu)`.

À 800 DPI et 35 cm/360° : AIM/LOCAL et CS2 avec yaw 0,022 donnent environ **1,484416**, Valorant avec yaw documentaire 0,07 environ **0,466531**. CS2 permet de modifier `m_yaw`. Le formulaire accepte sensibilité/DPI source tout en conservant les DPI actuellement déclarés dans l’application. Il n’effectue aucune modification du DPI matériel.

CoD et les jeux personnalisés exigent un titre/version, les DPI et la sensibilité source, puis une distance de tour complet réellement mesurée sans zoom. Le coefficient est dérivé de ce profil précis : `914,4 / (DPI_source × sensibilité_source × cm_mesurés)`. Aucune constante CoD universelle n’est livrée. La provenance historique reste enregistrée même après calibration ; rouvrir le formulaire ne réinterprète pas une nouvelle distance AIM/LOCAL comme une nouvelle mesure dans le jeu tiers.

Distance physique et coefficient source restent en précision complète dans le modèle, séparés des valeurs d’affichage arrondies. Le convertisseur utilise les DPI destination et signale la provenance documentaire/personnalisée/mesurée ; copier arrondit à six décimales. Sans profil connu, CoD/autre ne fournit aucune valeur copiable. La distance physique est conservée, pas une sensation identique à FOV/zoom différents ni une équivalence ADS.

L'historique compare seulement des séances terminées, valides, actives, non-échauffement, de **même empreinte de scénario, durée, version de score, DPI, cm360, FOV vertical, format, inversion Y, accumulation, limite FPS, moteur et renderer**. L'objectif de calibration n'altère pas le score d'entraînement. Après dix séances comparables : médiane des cinq dernières vs cinq premières, sans chevauchement ; un départ à zéro n'affiche pas de pourcentage trompeur. Record et évolution de la médiane restent distincts. Consulter également les mesures brutes pour distinguer progrès de cadence, précision et régularité.

## Ce qui reste à prouver

Le replay logiciel ne prouve pas la fidélité d'une souris Windows à 8 kHz. Le conseil personnalisé ne prouve pas une progression causale dans un autre jeu. Réception physique, conversion à la règle, confort sur plusieurs jours et stabilité des recommandations doivent être validés avant une promesse de performance. Les 39 autres exercices du catalogue complet, les routines, les graphes temporels détaillés, le déplacement du joueur et l'ADS restent des extensions, pas des fonctionnalités annoncées par cette V1.
