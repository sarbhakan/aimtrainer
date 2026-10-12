# Exercices 0.6 — varier sans fausser les mesures

La base reste décrite dans [la conception 0.5](EXERCISE_DESIGN_050.md). Le score V1, l’intégration tracking à 240 Hz et les cinq difficultés de calibration restent inchangés. Cette version ne prétend pas reproduire les algorithmes privés d’un autre aim trainer.

## Pratique aléatoire, comparaison contrôlée

Chaque lancement et chaque clic sur **Rejouer** obtient une nouvelle graine. La graine reste enregistrée dans le rapport pour reproduire les événements lors d’un replay logiciel ou d’un audit. Le tirage utilise le moteur seedé local, pas le framerate, le réglage souris ou le score précédent.

La calibration suit une autre règle : un même exercice et une même répétition utilisent les graines prescrites communes aux candidats. Refaire un passage interrompu reprend ce passage, pas une nouvelle difficulté choisie au hasard. Les échauffements restent exclus du conseil.

## Trois variantes explicitement versionnées

| Exercice | Travail visé | Variante révision 4 | Mesure |
|---|---|---|---|
| D01 — Réflexes | Repérer, centrer et déclencher à temps | Apparitions aléatoires, diamètre initial dans une plage fixée, rétrécissement pendant la seconde d’exposition puis remplacement | Cibles/min et précision ; expirations dans le détail |
| D02 — Cible mobile | Déclencher sur une cible dont la destination n’est pas apprise | Destinations horizontales seedées non cycliques, interpolation continue avec accélérations/freinages bornés | Cibles/min, précision et délai d’acquisition |
| S02 — Transitions mobiles | Passer entre plusieurs cibles en mouvement | Quatre couloirs séparés, profondeurs entre 3,5 et 5,5 m par apparition | Cibles/min, précision et délai de transition |

S02 garde un diamètre **angulaire** constant de 3,2° : une cible plus lointaine a un rayon physique plus grand. La profondeur ne prétend donc pas, à elle seule, rendre la cible plus difficile. Le cadrage, le sol et le mur sont contrôlés à la profondeur maximale. Les changements de taille de D01 suivent une fonction du temps, jamais une adaptation cachée à la réussite du joueur.

`target_geometry(index, time_s)` constitue la source des positions, distances et rayons utilisée par le rendu, les raycasts, les mesures et la silhouette des aperçus. La cible ne reçoit pas une hitbox plus grande que sa silhouette ; le recul de l’arme ne modifie pas la caméra.

C03 garde sa grille et ses cellules disponibles aléatoires ; C01/C02/C04/C05/C07 gardent leurs contraintes de flick, les suivis gardent leurs mouvements déclarés et S01 son switching statique. Tout transformer en trajectoire erratique détruirait la spécificité des exercices. Une nouvelle graine renouvelle déjà leurs positions/phases entre entraînements.

## Sensibilité en pause

Échap propose une valeur AIM/LOCAL ou son équivalent Valorant/CS2, sans modifier les DPI matériels. Le `m_yaw` du profil CS2 importé est conservé si présent. Affichage arrondi, modèle précis : cliquer puis quitter un champ sans édition ne réinterprète pas la sensibilité.

**Appliquer et recommencer** sauvegarde d’abord le profil. En cas de refus, l’ancien essai reste suspendu et intact. En cas de réussite, le passage déjà mesuré est enregistré comme interrompu à son ancienne sensibilité, puis un nouveau décompte démarre avec un nouveau contexte. Les scores des deux réglages ne sont jamais fusionnés. Pendant la calibration, le réglage est visible mais verrouillé.

Si l’enregistrement de l’abandon échoue après celui du profil, le bilan signale l’erreur et conserve le rapport en mémoire. Rejouer réessaie cette écriture avant de démarrer ; une nouvelle capture reste bloquée tant qu’elle échoue. Fermer à ce moment demande confirmation explicite de la perte du rapport non enregistré. Cette mémoire n’est pas une sauvegarde durable en cas de crash.

## Historique et limites

Les empreintes des trois variantes diffèrent de leur révision 3 : leurs anciens records restent stockés, mais ne deviennent pas ceux de la nouvelle difficulté. C02/C04/S01/T01/T05 conservent leurs empreintes et leur protocole ; aucune migration de leurs checkpoints de révision 3 n’est nécessaire. Les archives de révision 2 et les protections contre les fichiers incohérents restent actives.

Le changement de décor/armes est cosmétique : les clés mécaniques ne permettent pas d’attribuer une amélioration à cette seule présentation. Les petits replays synthétiques vérifient cohérence et invariants, pas la pertinence clinique d’un exercice ni le transfert vers un FPS. La lisibilité, le confort, l’écoute et les performances GPU doivent encore être évalués sur Windows avec des joueurs et des souris physiques.

La campagne de sérialisation couvre aussi 512 graines par exercice. Elle a reproduit un rejet rare autour d’un demi-point lors de la relecture JSON. Le score V1 calculé reste identique ; sa vérification prend en compte uniquement cette frontière au dernier bit, sans réécrire les scores ni tolérer un point arbitraire ailleurs. Voir D25 dans [les décisions](DECISIONS.md).
