# Exercices 0.7 — mouvements variés, géométrie mesurée

Les 18 définitions restent des difficultés fixes pendant un essai, indépendantes du score ou de la sensibilité. Position du joueur fixe, caméra à 1,6 m, FOV issu du profil. Chaque pratique utilise une nouvelle graine enregistrée ; reprendre une calibration conserve celle prévue. Le rendu, le rayon touché et les métriques utilisent la même géométrie horodatée.

| Exercice | Position et mécanique | Ce qui est travaillé |
|---|---|---|
| C03 Multicibles r5 | Six cibles, positions libres dans ±22° horizontal/±13° vertical ; 4 m, diamètre 4,8°. Pas de neuf nœuds mémorisables. Rejet des recouvrements puis réserve bornée si 128 tirages échouent. | Clics rapides, lecture de nouvelles positions et choix de transition. |
| M01 Flicks mixtes r5 | Une cible ; diamètres 2,5–4,2°. Après chaque touche, tirage 50/50 : transition 2,5–6° ou 20–44°. Pas d’alternance fixe ni adaptation au résultat. | Micro-corrections et portée du geste mélangées ; vitesse/précision. |
| T10 Suivi varié r5 | Trajectoire seedée continue, segments horizontaux, verticaux, diagonaux et de profondeur en ordre mélangé. Distance 3–5 m, vitesse angulaire ≤18°/s, vitesse de profondeur ≤1,2 m/s ; interpolation à accélération finie. Rayon physique constant, silhouette angulaire variant avec la profondeur. | Poursuite et corrections multidirectionnelles, adaptation au changement apparent de taille. |

**Entraînement complet** : M01 → T10 → S02, 45 ou 60 s par phase. Chaque phase a son décompte, sa graine et son rapport ; la transition suit une pause de 3 s, suspendue si le focus est perdu. Les trois performances restent distinctes : additionner un taux de suivi et une cadence de clic n’a pas de sens. Ce plan est fixe, pas encore un éditeur de routines.

C02/C04/S01/T01/T05 restent strictement en révision 3, avec les empreintes, tailles, trajectoires et RNG publiés. D01/D02/S02 restent en révision 4. C03 change d’empreinte : ses anciennes séances de grille ne deviennent pas des records du scatter. Les exercices avancés restent facultatifs ; aucun changement de FOV ni grossissement caché ne fait artificiellement monter les scores.

Le laboratoire emploie une source directionnelle unique pour les ombres du décor et des cibles, avec lumière ambiante diffuse. Le viewmodel est dans un monde séparé : sa lumière sert au rendu de l’arme et ne projette pas d’ombres sur les cibles. Biseaux, MSAA 4× et ombres 4096 améliorent les contours ; leur coût GPU Windows reste à mesurer. Hitmarker ambre orthogonal après impact, sans mouvement de caméra. Bips originaux courts 880 Hz pour 3/2/1, 1320 Hz pour GO, PCM alloué au chargement, silence/volume respectés.

Les tests logiciels vérifient transitions, frustum, sol, recouvrements, réserve de placement, vitesses, reproduction seedée, rendu/hitbox partagé, tracking à 60/144/240 FPS et conservation des cinq empreintes de calibration. Ils ne certifient ni sensations de jeu, ni matériel, ni écoute sonore réelle.
