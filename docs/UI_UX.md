# Interface et présentation — 0.2.0

## Une action, puis les détails

L’interface reprend les conventions des aim trainers modernes : navigation latérale, bibliothèque de cartes, aperçu de l’exercice, résultat lisible. L’identité AIM/LOCAL, les pictogrammes, les sprites et les sons sont originaux ; aucune ressource d’Aim Labs n’est utilisée.

Le thème est bleu nuit et turquoise, avec un accent violet réservé à certains équipements. Les panneaux restent sobres, sans effets de rendu coûteux. Les pages apparaissent en 180 ms ; l’option « Animations réduites » coupe les transitions, les aperçus animés et le mouvement de l’arme.

| Écran | Action principale |
|---|---|
| Accueil | S’entraîner ou trouver son réglage |
| Entraînement | Filtrer, consulter un aperçu, choisir la durée et lancer |
| Ma sensibilité | Déclarer ses DPI et commencer ou reprendre le test |
| Conversion | Choisir son jeu et copier la valeur |
| Progression | Lire ses résultats comparables ou exporter ses données |
| Réglages | Personnaliser la présentation et enregistrer ses préférences |

Les libellés visibles sont français et courts. Les textes techniques, mesures détaillées et paramètres avancés sont repliés par défaut. Une erreur de sauvegarde ou un résultat non fiable reste visible sans ouvrir les détails.

## Calibration sans jargon

Le formulaire demande les DPI déjà configurés sur la souris, un objectif et un départ confortable : lent, équilibré ou rapide. Il ne prétend pas détecter les DPI. Le protocole expérimental reste identique : trois réglages, cinq exercices, 15 familiarisations et 45 passages mesurés. Pendant les pauses, le joueur choisit son confort parmi cinq niveaux et voit quand continuer.

Le bilan montre une seule sensibilité d’application, les DPI, le nombre de passages réellement notés et le confort. Les alternatives, pondérations et dispersions restent accessibles dans les mesures détaillées. Une égalité, un manque de signal ou un mauvais confort ne devient pas une recommandation certaine. L’application du conseil reste explicite ; elle ouvre ensuite la conversion.

L’unité de sensibilité AIM/LOCAL utilise le yaw de référence 0,022 : `914,4 / (DPI × cm360 × 0,022)`. L’état sauvegardé demeure la distance physique en cm/360°, pas la valeur arrondie de l’étiquette. Modifier les DPI conserve cette distance. La conversion garde six décimales et les paramètres du jeu dans un panneau séparé ; elle ne promet pas une équivalence ADS ou une détection du jeu.

## Responsive et performances

- Mise en page en pixels réels, sans réduction globale de l’interface ; fenêtre minimale 800×450. Sous 1 060 px, la barre latérale garde ses icônes et leurs infobulles.
- Les contenus longs défilent verticalement. Le lancement d’exercice, sa durée et l’enregistrement des réglages ne sont pas enfouis dans le contenu défilant.
- Les petites fenêtres masquent l’aperçu animé de la fiche pour privilégier le titre et la consigne. Les grandes fenêtres centrent le contenu plutôt que d’étirer indéfiniment les panneaux.
- Les miniatures de la bibliothèque sont statiques. Seul l’aperçu visible est animé, à 30 Hz, et il s’arrête lorsque sa page est masquée. Ces illustrations ne représentent pas des hitboxes ni une calibration visuelle du FOV.
- Le HUD garde le temps, les touches ou le temps sur cible, un viseur discret et une consigne courte. Les courbes utilisent au maximum 20 scores réellement enregistrés dans le même contexte ; aucun historique de démonstration n’est injecté.
- Aucun tween, son, sprite ou aperçu ne modifie les angles de caméra, le moteur de mesure, les définitions d’exercice ou la clé de comparaison.

## Profils d’arme extensibles

Pulse, Vector et Classic associent chacun un sprite, un son de tir et une boucle continue. Ils sont cosmétiques : un clic produit toujours un tir dans les exercices de précision/transitions. Dans les exercices de suivi, maintenir le clic active seulement le son et le flash ; suivre sans cliquer reste pleinement mesuré.

Les quatre voix de tir et la voix continue sont créées à l’avance. Aucun fichier n’est chargé dans le traitement du mouvement de souris. Relâcher le clic coupe la boucle ; pause, perte de focus, changement de page et fin de séance arrêtent les sons. Une reprise n’active pas automatiquement le tir. Le volume, le silence, la visibilité de l’arme et les animations réduites se règlent séparément.

Pour ajouter un profil :

1. Fournir un sprite dans `assets/weapons/` et deux WAV dans `assets/audio/`, avec les droits nécessaires.
2. Conserver les WAV en PCM 16 bits mono ; mettre `compress/mode=0` dans leurs paramètres d’import. La boucle utilise des positions en **frames**, pas en octets.
3. Créer une ressource `WeaponDefinition` sous `content/weapons/`, avec un identifiant unique, le point de flash normalisé et sa cadence visuelle.
4. L’enregistrer dans `WeaponCatalog.DEFINITIONS` et dans les identifiants autorisés de `SensitivityService.validate_profile`.
5. Adapter les tests qui vérifient le catalogue et l’export, puis vérifier l’aperçu, le volume, la boucle et son arrêt sur Windows.

`python3 tools/generate_audio.py` régénère de manière déterministe les six sons originaux livrés. Ce script de développement n’est ni embarqué ni nécessaire pour jouer.

## Vérifier le rendu

`bash tools/visual_smoke.sh` utilise un affichage X11 existant ou démarre un Xvfb/Xorg dummy temporaire. Il attend que l’affichage réponde, utilise le rendu logiciel et arrête uniquement le serveur qu’il a lancé. Les 29 captures couvrent les six pages à trois tailles, les listes déroulantes, les réglages défilés, le HUD, la pause, le repos et les bilans. Les débordements horizontaux et erreurs de script font échouer le contrôle.

Les exemples de calibration et de courbe du harness sont synthétiques et isolés sous `user://tests/`. Ils ne démontrent aucune performance d’un joueur. Les captures de navigation publiées dans `docs/screenshots/` ne contiennent pas ces résultats de test.

Ce contrôle ne remplace pas une prise en main utilisateur, une écoute des sons, un essai natif Windows ou une mesure de souris physique. Voir `docs/TEST_PLAN.md`.
