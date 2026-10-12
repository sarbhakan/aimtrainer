# Suivi à rythme variable — 0.9.0

## Objectif

Travailler l’adaptation au mouvement, pas la mémorisation d’un tempo. Le suivi horizontal reste horizontal, le vertical reste vertical, le diagonal reste diagonal et le cercle conserve son ellipse. Les strafes et le suivi 3D utilisent aussi le nouveau rythme. Aucun bruit aléatoire par frame, aucune téléportation à un changement de vitesse, aucune modification de la souris.

## Bornes de rythme

| Exercice | Cadence basse | Vitesse angulaire maximale |
|---|---:|---:|
| T01 horizontal / T02 vertical | 5,4 °/s | 16,2 °/s |
| T03 diagonal | 7,2 °/s | 21,6 °/s |
| T04 cercle | 8,1 °/s | 24,3 °/s |
| T05 strafes | 11,7 °/s | 35,1 °/s |
| T09 petite cible | 2,7 °/s | 8,1 °/s |
| T10 multidirectionnel | 8,1 °/s | 24,3 °/s |

La cadence pilote la progression le long de la trajectoire. La vitesse réelle peut descendre sous la cadence basse dans les virages, aux extrémités, pendant un freinage ou une pause : ce n’est pas une vitesse minimale imposée au mouvement physique. Le plafond reste une borne de la vitesse angulaire réelle. Le suivi 3D garde ses profondeurs et limite le déplacement en profondeur à 1,62 m/s, après application du rythme.

Chaque apparition construit un petit programme seedé : vitesse de croisière, passages dans une bande rapide et une bande lente, freinage, pause de 0,18 à 0,35 s puis reprise dans l’autre sens. Ordre des deux bandes, vitesses, temps de maintien et durées des rampes varient selon la graine. Les accélérations sont progressives ; les freinages sont plus courts, mais jamais instantanés. Les cycles de vie restent ceux de la 0.8 : durée nominale de dix secondes ±15 %, réduction de taille bornée puis remplacement ailleurs.

Les plateaux mobiles sont compris entre les deux bornes. Les rampes vers zéro et les reprises passent naturellement sous la borne basse. La pente du rythme est limitée à quatre fois le plafond par seconde ; cette borne concerne la variation de cadence, pas l’accélération vectorielle complète d’un déplacement circulaire. Un demi-tour passe par l’arrêt, sans inversion instantanée de vitesse.

## Géométrie et temps

`TrackingRhythm` préconstruit les temps, vitesses signées et intégrales cumulées. Les rampes utilisent une interpolation smoothstep ; leur intégrale analytique donne le déplacement, sans accumulation dépendante du framerate. Une recherche binaire sélectionne le segment. Lire la trajectoire dans un ordre différent ne consomme aucun tirage RNG et ne modifie pas le programme.

Le moteur applique ce déplacement comme horloge locale de la trajectoire existante. Une vitesse négative parcourt la même trajectoire en sens inverse ; pour T10, la frontière initiale est réfléchie sur le début du parcours lissé. Les enveloppes angulaires, profondeurs, collisions et tailles restent communes au rendu, aux aperçus et aux mesures. La préparation utilise le même moteur et la même graine que le départ mesuré ; pause et perte de focus suspendent le temps actif.

Le programme est renouvelé à chaque apparition, à partir de la graine de séance et de l’identité de cible, avec un RNG isolé. Une pratique rejouée reçoit une nouvelle graine. Une calibration garde la graine prescrite pour les cinq sensibilités d’une même activité : le rythme n’est pas adapté au score ou à la sensibilité.

## Conservation des données

Seuls les sept suivis passent en **r7**. Les onze exercices de clic/transitions gardent exactement leurs variantes r6. `ScenarioCatalog.lifecycle_definitions/find_lifecycle` conserve les dix-huit variantes de 0.8, y compris leur RNG et leurs empreintes ; `practice_definitions/find_practice` expose le catalogue courant. `resolve` reconnaît les bases historiques, r6 et r7.

La nouvelle calibration utilise le **protocole 6**. Les protocoles 4 et 5 restent reprenables sur leurs propres difficultés, sans reinterpretation de leurs résultats. La formule de suivi reste le temps sur cible divisé par le temps exposé, mais ses nouveaux records ne sont pas mélangés aux suivis à rythme ancien. Aucun rapport, profil ou bilan historique n’est réécrit.

## Réception

Les tests doivent vérifier les bornes, les rampes, les arrêts, la continuité de position/vitesse, le déterminisme et les replays de mesures à 60/144/240 FPS. Les PNG montrent les états de l’application ; une image fixe ne valide pas une variation de vitesse. Vérifier humainement les sept suivis pendant plusieurs cycles sur Windows, particulièrement la petite cible T09 et la profondeur T10. La validation logicielle ne mesure ni latence HID, ni fluidité GPU native, ni progrès humain.
