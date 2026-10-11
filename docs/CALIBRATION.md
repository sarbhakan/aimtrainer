# Sensibilité repère et exercices — protocole V1

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
- Cinq exercices × trois réglages : **15 familiarisations de 8 s**, exclues du classement et de la progression.
- Ensuite cinq exercices × trois réglages × trois répétitions : **45 passages mesurés de 12 s**.
- Compte à rebours de 2 s et repos minimal de 3 s par passage, confort de 1 à 5. Minimum total proche de 16 min ; augmenter le repos librement et interrompre en cas de douleur/fatigue.
- L'ordre des exercices tourne à chaque répétition ; chaque candidat occupe une fois chaque position dans chaque exercice. Les trois candidats partagent la même graine pour un exercice/répétition. Familiarisations et répétitions ont des graines distinctes.
- L'écran de jeu et le bilan de passage utilisent A/B/C, sans montrer les valeurs numériques avant le bilan final. Cela limite certains biais sans constituer une étude en double aveugle.
- Le checkpoint conserve les passages acceptés et les paramètres. Abandonner un passage ne l'accepte pas : la reprise refait ce seul passage. Une nouvelle calibration archive le checkpoint précédent.

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

Le bilan sauvegarde tous les passages, médianes par exercice, poids, dispersions, plage, statut, paramètres et versions. Après fermeture, **Revoir le dernier bilan** permet de retrouver la décision. Un changement d'algorithme doit changer sa version et ne doit pas réécrire les séances passées.

## Bibliothèque exécutable

Tous les scénarios ont une difficulté fixe, des trajectoires/générations déterministes par graine, des cibles à 8 m et les mêmes protections de pause/focus. Le diamètre est angulaire, pas dépendant de la résolution. Six sphères suffisent au pool.

| ID | Exercice | Cibles | Diamètre | Particularité / référence clic |
|---|---|---:|---:|---|
| C01 | Static Single | 1 | 1,5° | Cible statique ; 2 touches/s |
| C02 | Micro-précision | 1 | 0,65° | Zone étroite ; 1,6/s |
| C03 | Grid Targets | 6 | 1,2° | Cellules libres d'une grille 3×3 ; 3/s |
| C04 | Grands flicks | 1 | 1,4° | Écart minimal 14° ; 1,8/s |
| C05 | Sixshot précis | 6 | 0,7° | Petites cibles dispersées ; 2,4/s |
| C07 | Flicks verticaux | 1 | 1° | Zone verticale ±17° ; 2/s |
| D01 | Pop-up | 1 | 1,5° | Expiration après 1 s ; 2/s |
| D02 | Clic mobile | 1 | 1,8° | Oscillation horizontale ; 1,8/s |
| T01 | Suivi horizontal fluide | 1 | 2° | Sinusoïde horizontale |
| T02 | Suivi vertical | 1 | 2° | Sinusoïde verticale |
| T03 | Suivi diagonal | 1 | 2° | Yaw et pitch couplés |
| T04 | Circle Track | 1 | 2° | Boucle elliptique yaw/pitch |
| T05 | Suivi de strafes | 1 | 1,8° | Trajet triangulaire, inversions nettes |
| T09 | Far Small | 1 | 0,9° | Suivi de petite cible, vitesse réduite |
| S01 | Target switching | 4 | 1,3° | Transitions entre touches ; 2,8/s |
| S02 | Moving Switch | 4 | 1,8° | Cibles mobiles ; 2,4/s |

Les paramètres complets résident dans les `.tres`. `speed_deg_s` règle la vitesse d'un axe de la trajectoire, pas une vitesse 3D constante pour une ellipse/diagonale. Les cibles ne se chevauchent pas à leur génération ; des trajectoires mobiles peuvent ensuite se croiser, auquel cas le rayon touche la sphère la plus proche. Pas d'adaptation automatique pendant un passage ni de difficulté cachée.

## Conversion et progression

`degrés/count = 914,4 / (DPI × cm360)`.

`sensibilité_jeu = 914,4 / (DPI_destination × cm360 × yaw_jeu)`.

À 800 DPI et 35 cm/360° : AIM/LOCAL et CS2 avec yaw 0,022 donnent environ **1,484416**, Valorant avec yaw documentaire 0,07 environ **0,466531**. CS2 permet de modifier `m_yaw` : le coefficient est éditable. Les autres titres/ADS exigent un coefficient connu, jamais une équivalence inventée. Le convertisseur affiche aussi le cm/360 obtenu après arrondi à six décimales. La distance physique est conservée, pas une sensation identique à FOV/zoom différents.

L'historique compare seulement des séances terminées, valides, actives, non-échauffement, de **même empreinte de scénario, durée, version de score, DPI, cm360, FOV vertical, format, inversion Y, accumulation, limite FPS, moteur et renderer**. L'objectif de calibration n'altère pas le score d'entraînement. Après dix séances comparables : médiane des cinq dernières vs cinq premières, sans chevauchement ; un départ à zéro n'affiche pas de pourcentage trompeur. Record et évolution de la médiane restent distincts. Consulter également les mesures brutes pour distinguer progrès de cadence, précision et régularité.

## Ce qui reste à prouver

Le replay logiciel ne prouve pas la fidélité d'une souris Windows à 8 kHz. Le conseil personnalisé ne prouve pas une progression causale dans un autre jeu. Réception physique, conversion à la règle, confort sur plusieurs jours et stabilité des recommandations doivent être validés avant une promesse de performance. Les 39 autres exercices du catalogue complet, les routines, les graphes temporels détaillés, le déplacement du joueur et l'ADS restent des extensions, pas des fonctionnalités annoncées par cette V1.
