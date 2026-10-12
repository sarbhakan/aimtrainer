# Cibles temporaires — 0.8

Les dix-huit pratiques utilisent des variantes **r6** explicitement différentes de leurs références historiques. Le catalogue de base reste figé ; `practice_definitions()` dérive et met en cache les variantes, sans modifier les ressources déjà publiées. Leurs empreintes incluent durées, plage de durées et plancher de rétrécissement. Aucun paramètre ne dépend du score du joueur.

## Clic et transitions

Chaque apparition part à sa taille initiale. Son échéance est tirée avec la graine enregistrée, dans ±15 % d’une durée nominale : 4 s pour les multicibles, 6 s pour la précision avancée, 5 s pour les transitions mobiles, 1 s pour les réflexes, 3 s pour les autres cibles uniques. Ce sont des constantes de difficulté, pas des plages de sensibilité. Les échéances des cibles simultanées sont distinctes ; aucune cible oubliée n’attend indéfiniment.

Le diamètre rétrécit linéairement avec l’âge. Son plancher est déclaré dans la variante : 35–75 % de la taille de départ selon la difficulté ; cela préserve une silhouette visable, y compris dans les modes avancés. À l’échéance, la cible est remplacée sans pause à une nouvelle position. Le rendu et la collision utilisent le même diamètre horodaté. Un clic à l’échéance ne touche pas rétroactivement la cible disparue.

`targets_expired` compte les cibles oubliées. `misses` reste le nombre de **tirs** ratés ; `shots` ne reçoit aucun tir artificiel. Le score **V2** utilise :

`réussite = touches / (tirs + cibles expirées)`

`score = arrondi(1000 × touches/seconde × réussite² / cadence de référence)`

Une expiration ne donne aucun point et réduit la réussite/le score. Les échecs affichés combinent tirs ratés et expirations, avec leur répartition visible. La précision des tirs `touches/tirs` reste disponible séparément dans les données détaillées. Tirer plusieurs fois à côté puis oublier la même cible représente plusieurs actions échouées ; ce ratio n’est pas une probabilité par cible unique.

## Suivi

Les cycles durent 10 s nominales, ±15 %. La taille descend vers un plancher positif de 65–85 % selon la difficulté, jamais zéro. T10 combine ce rétrécissement avec la perspective de ses déplacements en profondeur. À l’échéance, une nouvelle trajectoire commence ailleurs à taille initiale : il faut la réacquérir. Les positions/temps de parcours redémarrent depuis la nouvelle apparition, sans saut de caméra ni modification des counts.

L’expiration programmée d’une cible suivie n’est **pas** un tir raté. Le score reste la fraction du temps réellement sur cible, formule V1, mais la nouvelle difficulté r6 possède une clé distincte. La réacquisition recommence à l’apparition suivante. Le pas logique reste 1/240 s ; un tick traversant une échéance est scindé pour mesurer les deux cibles sans trou d’exposition. La résolution temporelle de rendu/mesure reste celle du moteur, pas une promesse de latence HID.

## Chronologie et conservation

Les expirations de clic sont traitées dans l’ordre chronologique, égalités départagées par indice de cible. Un gros saut de temps et des petits pas consomment donc les mêmes tirages RNG. La pause n’avance pas les cycles. La préparation montre les cibles à âge zéro et utilise un moteur distinct ; au GO, la même graine recrée les conditions.

Les nouvelles calibrations utilisent le **protocole 5** et ces variantes, toujours cinq activités × cinq sensibilités × 45/60 s. Le protocole 4 reste reprenable/reconstructible sur les définitions et scores de 0.7 ; ses bilans ne sont pas présentés comme des mesures temporelles. Les services historiques 1–3 sont inchangés. Les sessions restent stockées dans leur version ; aucune réécriture V1→V2 ni fusion de records entre difficultés.

## Présentation

Un hitmarker original en X, quatre petits traits diagonaux avec centre ouvert, apparaît à distance du viseur après une vraie touche. Contour contrasté et bref fondu ; il n’en prolonge plus les branches. Le décor ajoute des panneaux et petits équipements en périphérie/derrière les cibles, avec un budget de 32 meshes. Une seule lumière directionnelle mondiale vient d’un côté ; elle ombre le décor et les sphères. L’ambient diffus ne projette pas d’ombre contradictoire. Les lumières du viewmodel restent isolées du monde.

Réception humaine, son entendu et performances/souris Windows restent à vérifier. Les images et replays automatisés ne prouvent pas une sensibilité universellement parfaite ni un progrès dans un autre FPS.
