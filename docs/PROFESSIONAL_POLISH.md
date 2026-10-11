# Plan de finition — 0.4.0

Objectif : une application native Godot cohérente, utilisable par un débutant, dont les retours correspondent à des mesures réelles. Les animations ne doivent jamais modifier les counts souris, le chronomètre, les hitboxes ou les scores.

## Répartition

| Volet | Responsable | Livrables |
|---|---|---|
| UI | Agent spécialisé UI senior | Design system, cartes, focus clavier, états sélectionnés, transitions sobres |
| UX | Agent spécialisé parcours novice | Navigation, microcopy, choix de calibration, filtres et tableau des séances |
| Gameplay | Agent spécialisé moteur/mesures | Audit du cadrage, collisions, mouvements, aperçus représentatifs, scores et comparabilité |
| Feedback | Agent spécialisé viseur/tir | Viseur personnalisable, prévisualisation, hitmarker et animations cosmétiques |
| Sensibilité | Agent spécialisé protocole | Exploration large, recentrage explicable, affinage, limites et sauvegardes versionnées |
| Intégration/QA | Agent principal | Orchestration, transactions, résultats, tests croisés, rendus, distribution |

Le projet utilise des Controls Godot, pas un navigateur. Aucun skill frontend spécialisé n’était installé dans l’environnement au début du travail ; les agents appliquent une démarche de composants, hiérarchie visuelle, accessibilité et validation responsive. Aucun plugin web superflu n’est ajouté.

## Liste des améliorations et critères

### UI et interactions

- Identité et tokens communs : couleurs, contrastes, typographie, marges et rayons cohérents.
- Onglet actif explicite ; survol, pression et focus distincts, sans dépendre uniquement de la couleur.
- Transitions courtes, annulables, avec un état final stable ; respecter Animations réduites.
- Pas de déplacement de layout au survol ; ne pas empiler des tweens à chaque mouvement.
- Cartes lisibles, recherche/filtres accessibles, lancement et durée facilement repérables.
- Bulles bornées après allocation réelle du texte, sans espace réservé dans les conteneurs.
- Répartition à 800×450, 1280×720 et 1920×1080 : pas de texte coupé ni de débordement horizontal.
- Traitements et animations masqués arrêtés ; une seule démonstration animée par écran.

### UX novice

- Une action principale identifiable par page ; le parcours répond à « quoi faire maintenant ».
- Distinguer régler, importer, comparer un réglage connu et rechercher depuis un point de départ incertain.
- Consignes d’exercice : une action, un déroulement court, une mesure pertinente ; détails techniques repliés.
- DPI source distincts des DPI actuels ; imports explicites, aucune détection matérielle inventée.
- Nombres lisibles dans les champs sans réarrondir le modèle physique ni le profil source historique.
- Erreurs et sauvegardes refusées visibles ; rien de « réussi » si les données n’ont pas été écrites.
- Confort, pauses, réessais et reprise compréhensibles ; effort total du mode guidé annoncé honnêtement.
- Aucun historique de démonstration dans les données produit.

### Gameplay et feedback

- Origine réelle de la caméra, diamètre angulaire versionné, collision/rendu identiques.
- Cibles entièrement cadrées au départ et non occultées par le sol ; pas d’auto-difficulté cachée.
- Trajectoires/générations déterministes, vitesse et inversions conformes à la définition de l’exercice.
- Prévisualisations dérivées des mêmes paramètres, projection et temporisation représentatives.
- Compte à rebours avant les mesures ; aucune cible touchée ou métrique enregistrée avant le départ.
- Hitmarker uniquement après un impact ; recul, flash et trace alignés vers le viseur et purement cosmétiques.
- Viseur : point, croix, cercle, T ; taille, épaisseur, espacement, couleur et contour, avec aperçu immédiat.
- Pause, perte de focus et fin arrêtent les effets ; reprise explicite, sans tir automatique.
- Souris sans delta de frame, lissage ou caméra shake ajouté ; aucun I/O sur le chemin de mouvement.

### Mesures et progression

- Score versionné accompagné d’une explication courte adaptée au clic ou au suivi.
- Mesures lisibles : touches sur tirs, cadence, temps réellement sur cible et durée active.
- Conseil lié aux mesures, pas une déduction non prouvée sur le matériel ou le niveau du joueur.
- Record seulement pour une séance terminée, valide et active, hors familiarisation, dans le même contexte.
- Célébration discrète d’un record réellement sauvegardé ; aucun record annoncé après un échec d’écriture.
- Tableau des dernières séances avec dates, exercice, score et contexte ; filtres sans mélange de conditions.
- Médiane récente, meilleur score et tendance distincts ; pas de pourcentage trompeur sans données suffisantes.

### Sensibilité adaptative

- Les DPI ne changent pas pendant la recherche ; seuls des candidats de sensibilité réellement testés changent.
- Exploration plus large que ±10 %, puis recentrage selon les résultats fiables et le confort.
- Chaque comparaison utilise les cinq exercices, trois candidats et trois répétitions mesurées : ne pas conclure depuis deux mini-tests isolés.
- Difficulté, graines communes et paramètres constants au sein de chaque comparaison.
- Si un bord gagne nettement et confortablement, déplacer la plage ; sinon resserrer ou signaler l’incertitude.
- Nombre de comparaisons borné, pas d’escalade sans fin, pas de changement fondé sur du bruit.
- Limites physiques explicites, trois candidats distincts, historique des choix et raison de chaque nouvelle plage.
- Reprise transactionnelle du passage et de la recherche ; anciens checkpoints compatibles ou protégés.
- Application finale explicite, interdite si données insuffisantes/confort mauvais ; confirmation un autre jour.
- Ni « sensibilité parfaite » universelle, ni preuve causale de progression dans un jeu tiers.

## Validation

Tester d’abord chaque composant, puis les parcours croisés : import → réglage → entraînement → résultat → record → historique ; recherche → comparaison → nouvelle plage → fermeture → reprise → bilan → conversion. Vérifier les journaux, pas seulement le code de sortie. Rendre les écrans à trois tailles et publier des captures réelles, en identifiant les fixtures synthétiques.

Les essais humains, souris physique à 2–8 kHz, scaling/latence Windows et écoute ne sont pas remplacés par les bots. Le périmètre ne comprend pas les 55 exercices complets, l’ADS, les leaderboards réseau, les assets propriétaires d’Aimlabs ou une nouvelle version macOS native.
