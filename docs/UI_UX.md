# Interface et présentation — 0.9.0

## Rythmes de suivi

Les sept suivis gardent leur trajectoire mais alternent accélérations, freinages, pauses et reprises. Une seule phrase courte annonce ce rythme avant le départ ; aucun compteur de vitesse ou consigne supplémentaire ne surcharge le HUD. Les aperçus jouent le même moteur que l’exercice. Les captures fixes ne valident pas les variations de vitesse.

## Cibles temporaires

Les cartes et bulles publiques montrent exactement les variantes jouées : onze clics/transitions r6 et sept suivis r7, cibles rétrécissantes, échéances et remplacement. Le résultat de clic affiche Touches, Ratées et Réussite, avec tirs ratés/expirations distincts ; le score est versionné dans les détails, pas dans les libellés courants. Le suivi garde son temps sur cible et explique que ses remplacements programmés ne sont pas des tirs ratés. Le HUD indique une expiration de clic sans ajouter une liste de chiffres devant la visée.

Le hitmarker X n’est plus une extension du viseur. Décor plus riche en périphérie, source directionnelle unique de côté et ombres des sphères conservées pour la profondeur. La nouvelle calibration est protocole 6 ; les reprises 0.7/0.8 gardent leurs protocoles 4/5 et leurs règles historiques. Les options d’objectif historiques non utilisées par la recherche progressive restent cachées.

## Parcours long, rendu cohérent

La calibration publique propose cinq activités × cinq sensibilités, 60 s par essai (45 s au choix), recherche locale ou départ novice lent/normal/rapide. Les résultats montrent seulement les indicateurs pertinents pour la famille : touches/ratés et précision pour le clic, temps réellement suivi et écart pour le tracking. Les cinq essais du bloc ont chacun une carte ; la sensibilité finale est une seule valeur avec Appliquer. Les calculs et intervalles de recherche restent repliés. Pas de questionnaire de confort ni d’échauffement court noté comme une comparaison complète.

L’accueil propose aussi l’entraînement M01 → T10 → S02 en trois phases. Scores séparés et même profil ; la perte de focus pendant la transition exige Continuer. Les anciens boutons de protocole 3 restent cachés même si une ancienne sauvegarde existe.

Réglages : aperçu orthographique de l’arme entière de profil, sans main/manche ; cadrage calculé depuis les bounds avec marge et réutilisé pour les trois tailles de fenêtre. Le HUD garde l’arme tenue et alignée vers le viseur. MSAA 4×, décor biseauté, une source directionnelle commune aux ombres et ambient diffus ; les lumières du viewmodel isolé n’éclairent pas le monde. Hitmarker ambre à quatre traits diagonaux courts, contour contrasté. Décompte sonore 3/2/1 puis GO, volume/silence respectés ; Animations réduites n’annule pas le son.

## Une seule échelle visuelle

Espacements communs de 4/8/12/16/24/32 px, champs alignés, descriptions raccourcies et deux décimales pour les sensibilités visibles. Une valeur positive trop petite pour cet arrondi est indiquée « <0,01 », pas zéro. Le coefficient technique `m_yaw`, replié, conserve ses décimales utiles pour distinguer un réglage personnalisé. Le float canonique reste indépendant de l’affichage : ouvrir/quitter un champ ne réinterprète pas l’arrondi comme une saisie. La conversion copiée conserve sa précision utile.

En jeu : timer isolé à gauche, touches/précision ou temps sur cible et score évolutif à droite. Aucune consigne ni nom d’exercice permanent dans la zone de visée. La préparation affiche 3, 2, 1 avec une impulsion, sans répéter la consigne déjà présentée ; GO disparaît rapidement au-dessus du viseur. Les cibles initiales sont montrées sans avancer les mesures.

La direction [Precision Lab](art-direction/README.md) précède l’implémentation : concepts distincts des captures réelles, laboratoire clair, matériaux mats ombrés, cibles corail et armes perle/graphite/acier. Les actions évidentes Actualiser/Copier utilisent seulement une icône, avec nom accessible et infobulle. Une démo ne conserve ni bande ni texte « Démo animée ».

Le scroll reste natif et les barres sont masquées, pas le défilement : molette, gestes de pavé tactile, flèches/Page haut/Page bas quand le conteneur a le focus et révélation du contrôle ciblé. La bibliothèque garde une largeur flexible pour éviter le cycle de minimum du grid lors d’un passage du grand au petit format. Aucun champ n’est tronqué pour cacher un débordement.

Échap propose la sensibilité locale ou son équivalent Valorant/CS2. Reprendre et Menu ont la taille de leurs libellés. Appliquer redémarre l’essai après sauvegarde ; la comparaison de calibration verrouille le réglage. Un échec d’écriture de l’abandon est visible avant la relance et peut être retenté.

## Finition native

Les composants partagent des états de survol, pression, sélection et focus clavier cohérents. Les transitions durent 100–180 ms, n’animent pas la géométrie des conteneurs et s’arrêtent sur masquage. Animations réduites garde l’information sans mouvement. Compteur et résultats ne dépendent pas de ces effets.

Ma sensibilité distingue **Je cherche un point de départ** et **J’ai déjà un réglage**, avec durée et reprise propres. Les paragraphes redondants laissent place à une action et une consigne. Le formulaire source affiche des nombres lisibles tout en conservant son float canonique : ouvrir/quitter sans éditer n’est pas une nouvelle saisie.

Le résultat associe le score à des mesures utiles : précision, touches/tirs et **cibles réussies/minute** pour le clic ; fraction et secondes réellement suivies, retour sur cible pour le tracking. Un objectif court propose quoi essayer ensuite, sans diagnostiquer magiquement la sensibilité. Les actions restent dans un pied fixe. Un record n’est célébré qu’après écriture, à contexte identique.

Progression dispose de filtres famille/exercice, de courbes et d’un tableau limité aux vingt dernières séances comparables. Record, médiane et tendance sont distincts. Les préférences de viseur/arme restent hors de la clé mécanique ; changer leur perception peut influencer une performance, ce n’est pas une preuve causale de progrès technique.

Viseur : point, croix, cercle et T, taille 1–32 px, épaisseur 1–8 px, espacement 0–24 px, couleur et contour, aperçu immédiat et sauvegarde. Hitmarker contrasté de 110 ms ; flash/recul/trace sans caméra shake ni hitbox différente.

Si le joueur détourne trop la caméra pendant le compte à rebours, le départ attend le réalignement. Repère et flèche indiquent la zone ; aucun count ni angle supprimé, aucun temps d’entraînement mesuré pendant l’attente.

Calibration progressive : scores non arrondis comparés dans chaque activité, essais suivants ajustés et zone transmise resserrée. 25 mesures, environ 28 min à 60 s ou 22 min à 45 s, avec pauses et reprise. Le bilan fournit une sensibilité testée unique, sans prétendre prouver un optimum universel. Voir `docs/CALIBRATION.md`.

## Une action, puis les détails

L’interface reprend les conventions des aim trainers modernes : navigation latérale, bibliothèque de cartes, aperçu de l’exercice, résultat lisible. L’identité AIM/LOCAL, les pictogrammes, les modèles 3D et les sons sont originaux ; aucune ressource d’Aim Labs n’est utilisée.

Le thème est bleu nuit et turquoise, avec un accent violet réservé à certains équipements. Les panneaux restent sobres, sans effets de rendu coûteux. Les pages apparaissent en 180 ms ; l’option « Animations réduites » coupe les transitions, les aperçus animés et le mouvement de l’arme.

| Écran | Action principale |
|---|---|
| Accueil | S’entraîner ou trouver son réglage |
| Entraînement | Filtrer, découvrir une carte, choisir la durée et lancer |
| Ma sensibilité | Modifier le réglage actif, importer celui d’un jeu ou lancer les cinq activités de calibration |
| Conversion | Traduire le réglage actif vers un jeu et copier la valeur |
| Progression | Lire ses résultats comparables ou exporter ses données |
| Réglages | Personnaliser la présentation et enregistrer ses préférences |

Les libellés visibles sont français et courts. Les textes techniques, mesures détaillées et paramètres avancés sont repliés par défaut. Une erreur de sauvegarde ou un résultat non fiable reste visible sans ouvrir les détails.

## Une sensibilité visible et modifiable

Le badge de l’en-tête affiche la sensibilité AIM/LOCAL et les DPI actifs ; un clic ouvre **Ma sensibilité**. Le champ **Sensibilité active dans AIM/LOCAL** est directement modifiable, sans ouvrir les options avancées ni lancer une calibration. Une valeur plus grande fait tourner plus vite. Le changement est utilisé au prochain exercice ; **Enregistrer** permet de le retrouver après fermeture. Ce bouton est disponible dans Ma sensibilité et Réglages.

Les DPI doivent correspondre au réglage réel de la souris, déjà choisi dans son logiciel. L’application ne les détecte pas et ne modifie pas le matériel. Les départs **Plus lent**, **Équilibré** et **Plus rapide** restent des raccourcis facultatifs, pas une obligation ni une recommandation finale.

Le nombre AIM/LOCAL est une unité propre à l’application, avec un coefficient de rotation de référence de 0,022. L’état sauvegardé demeure la distance physique en cm/360°, à pleine précision, pas la valeur arrondie du badge. Modifier les DPI actifs conserve cette distance et recalcule le nombre affiché. Ces détails restent accessibles sans encombrer le parcours débutant.

## Importer un jeu, puis convertir en retour

**Je viens d’un autre jeu**, dans Ma sensibilité, reçoit le jeu source, sa sensibilité et les DPI utilisés dans ce jeu. CS2 utilise par défaut `m_yaw=0,022`, modifiable dans un panneau dédié ; VALORANT utilise le coefficient documentaire 0,07. Un aperçu montre le réglage AIM/LOCAL obtenu avant l’action explicite **Utiliser ce réglage dans AIM/LOCAL**.

Le contrat d’import distingue deux données :

- **DPI source** : associés au réglage historique du jeu, conservés avec sa sensibilité, son coefficient et la distance de rotation correspondante dans `reference_game`.
- **DPI actuels** : réglage réel de la souris déclaré dans AIM/LOCAL, conservé lors de l’import. Le nombre AIM/LOCAL est recalculé pour ces DPI, afin de retrouver la distance de rotation source même si les deux DPI diffèrent.

Changer ensuite les DPI ou la sensibilité active ne réécrit pas silencieusement le profil source historique. Les libellés doivent garder cette distinction ; importer une configuration à 1 600 DPI ne doit pas prétendre modifier une souris actuellement réglée à 800 DPI.

**Call of Duty · profil mesuré** et **Autre jeu · profil mesuré** demandent le titre/version, la sensibilité, les DPI source et une distance mesurée à la règle pour un tour complet, sans zoom. Le coefficient est dérivé de cette mesure et conservé pour ce profil précis. Ce n’est ni une constante commune aux épisodes de CoD, ni une mesure faite automatiquement par AIM/LOCAL. Les données enregistrées sont une référence personnelle historique, pas une certification du comportement d’un jeu tiers.

La page **Conversion** part du réglage AIM/LOCAL actif et des DPI utilisés dans le jeu de destination. Elle affiche une valeur à recopier et garde six décimales pour la copie. Un profil mesuré doit rester identifié par son titre/version ; une destination non renseignée ne reçoit pas arbitrairement un coefficient CoD universel. Les hypothèses restent visibles : rotation sans zoom, coefficient documentaire, personnalisé ou issu de la mesure. Le FOV, l’ADS, l’accélération et les différences entre jeux peuvent modifier le ressenti ; la conversion exige une vérification en jeu.

## Historique conservé — protocole 3

Les descriptions suivantes concernent les anciens services, toujours vérifiés pour protéger les données, mais absents des actions publiques 0.7.

Le joueur choisit son objectif et compare trois réglages autour du départ actuel : **A · lent**, **B · départ**, **C · rapide**, soit 90 %, 100 % et 110 % de sa vitesse de rotation. Le parcours annonce cinq exercices : `C02`, `C04`, `S01`, `T01` et `T05`. Il termine un bloc avant de passer à l’exercice suivant ; les candidats restent les mêmes pendant toute la comparaison.

Chaque bloc comprend **trois échauffements**, un par sensibilité, puis **neuf passages notés**, trois par sensibilité. Les passages notés alternent les candidats dans trois séries contrebalancées, sans changer la difficulté au milieu de la comparaison. Cela donne 15 échauffements et 45 passages notés au total. Les échauffements durent 8 s, les essais notés 12 s ; avec les départs de 3 s, le parcours indique environ 17 minutes, hors pauses prolongées et passages refaits.

Après chaque passage fiable, l’écran de repos (**REST**) affiche l’exercice, la phase, la valeur numérique de la sensibilité essayée, le confort et les scores médians déjà obtenus pour A/B/C. Les valeurs des trois réglages restent visibles : le joueur ne doit pas avoir à deviner ce que représente une lettre.

**Continuer** et **Refaire ce passage** attendent les trois secondes de repos et le retour du focus. Refaire est possible aussi après un passage valide ; cette action recommence la même étape, avec le même scénario, la même sensibilité et la même graine. Elle ne valide pas le résultat en attente et n’avance pas le checkpoint. Seul Continuer accepte le passage avec sa note de confort et avance après sauvegarde réussie. Une erreur de sauvegarde reste visible et laisse le passage disponible pour réessayer ; un abandon ou un passage non fiable doit être refait, pas accepté pour améliorer artificiellement le bilan.

Le bilan présente une recommandation repère et un comparatif **cinq exercices × trois sensibilités** : chaque cellule contient la médiane de trois passages notés, hors échauffements. Les sensibilités numériques associées à A/B/C accompagnent le comparatif. Les scores se comparent entre réglages sur la même ligne, pas entre exercices différents ; la combinaison finale utilise les normalisations, les poids de l’objectif et les garde-fous du protocole, pas une somme brute de scores disparates.

Les mesures détaillées gardent les pondérations et dispersions. Une égalité, un manque de signal ou un mauvais confort ne devient pas une recommandation certaine. Le meilleur réglage en bord de plage invite à affiner. L’application du conseil reste explicite et ouvre ensuite la conversion. Un résultat est un optimum local parmi les sensibilités essayées, à confirmer un autre jour, jamais une sensibilité universellement parfaite. Voir `docs/CALIBRATION.md` pour le protocole technique.

## Responsive et performances

- Mise en page en pixels réels, sans réduction globale de l’interface ; fenêtre minimale 800×450. Sous 1 060 px, la barre latérale garde ses icônes et leurs infobulles.
- Les contenus longs défilent verticalement. Le lancement d’exercice, sa durée et l’enregistrement des réglages ne sont pas enfouis dans le contenu défilant.
- Les pages utilisent toute la largeur disponible, avec des marges raisonnables, sans colonne centrale plafonnée par un `max_width`. Ma sensibilité répartit réglage actif et import sur deux colonnes en grande fenêtre ; les bilans répartissent résultat et comparaison sur deux colonnes. Les petites fenêtres reviennent à une colonne et masquent les aperçus secondaires lorsque nécessaire.
- La bibliothèque ajuste sa grille jusqu’à quatre colonnes, avec un panneau de détail proportionné. L’accueil répartit ses cartes selon la place disponible plutôt que de conserver de grandes bandes vides.
- Le HUD garde le temps, les touches/précision ou le temps sur cible, le score et un viseur discret. La consigne apparaît seulement avant le départ. Les courbes utilisent au maximum 20 scores réellement enregistrés dans le même contexte ; aucun historique de démonstration n’est injecté.
- Aucun tween, son, viewmodel ou aperçu ne modifie les angles de caméra, le moteur de mesure ou la clé de comparaison. Les difficultés révisées restent distinctes et versionnées.

## Découvrir une carte sans ouvrir un formulaire

L’accueil et la bibliothèque proposent une bulle au **survol ou au focus clavier après 180 ms**. Un clic sélectionne l’exercice et ouvre immédiatement sa présentation. La bulle contient le titre, une démonstration animée originale, une description courte de l’action à réaliser et la mesure évaluée. Ce n’est pas une vidéo d’Aim Labs ni un lecteur de médias.

Les miniatures restent statiques. La démonstration visible est rafraîchie à **30 Hz** ; lorsqu’une bulle s’ouvre, l’aperçu de fond ou de détail s’arrête afin de ne garder qu’un aperçu d’exercice animé à la fois sur la page. L’option Animations réduites conserve la présentation textuelle sans animation.

Sortie de survol/focus, défilement, changement de filtre, changement de page et Échap ferment la présentation et annulent son délai en attente. La fermeture rétablit seulement l’aperçu pertinent de la page visible. La bulle reste dans le viewport ; son aperçu est contenu et conserve le ratio sans déformation. Les cibles utilisent la projection et les trajectoires réelles du moteur, pas des cercles agrandis arbitrairement. Plus de FOV ou ratio affiché en permanence ; une indication discrète identifie la démo animée.

## Cibles lisibles et profondeur cohérente

Les distances, tailles et amplitudes sont choisies par exercice : [mécaniques et objectifs](EXERCISE_DESIGN_060.md). Les cibles d’entrée restent lisibles, les exercices de précision avancée sont identifiés comme exigeants. Laboratoire clair et cibles corail, avec ombres directionnelles et remplissage doux. Le décor reste statique et la caméra ne se déplace pas ; seules les rotations suivent les counts souris.

La taille utile reste angulaire, jamais automatiquement agrandie selon la résolution. Silhouette et hitbox conservent le même rayon depuis l’origine de la caméra. D01/D02/S02 passent en révision 4 ; les autres restent en révision 3 : anciennes séances conservées mais jamais mélangées aux records d’une nouvelle difficulté. Les checkpoints r2 reconnus sont archivés, pas poursuivis sur une difficulté différente. Ce contrôle logiciel ne prouve pas un ressenti de souris physique.

## Profils d’arme extensibles

Pulse, Vector et Classic associent chacun un modèle original en 3D, un son de tir et une boucle continue. Géométrie procédurale, canon orienté vers la ligne de visée, silhouette de prise en main dans le bas droit. Le monde et la caméra du viewmodel sont isolés de l’arène ; la zone centrale du viseur reste dégagée. Les SVG hérités du catalogue ne sont plus le rendu de l’arme.

Le retour de tir est **strictement cosmétique** : recul et retour local du modèle en **220 ms**, pièce mobile, flash 3D au canon en **65 ms**, tracer discret de **45 ms**, réservé au HUD et dirigé vers le centre de visée sans masquer le viseur. Le flash suit le canon pendant son mouvement. Le tracer n’est ni une trajectoire balistique ni un rayon utilisé pour déterminer un impact. Aucun recul de caméra, changement de sensibilité, score ou hitbox n’en découle. Dans l’aperçu des réglages, le contrôle reste borné et aucun tracer ne sort vers le reste du menu.

Un clic produit toujours un tir dans les exercices de précision/transitions, sans automatique ajouté par le choix d’arme. Dans les exercices de suivi, maintenir le clic active seulement le son et les impulsions visuelles facultatives ; suivre sans cliquer reste pleinement mesuré. Le retour est limité, ne s’accumule pas avec le spam et ne conserve aucun traitement d’animation une fois au repos.

Les quatre voix de tir et la voix continue sont créées à l’avance. Aucun fichier n’est chargé dans le traitement du mouvement de souris. Relâcher le clic coupe la boucle sonore et laisse le modèle revenir au repos ; pause, perte de focus, changement de page et fin de séance arrêtent les sons et effacent les effets en attente. Une reprise n’active pas automatiquement le tir. Le silence conserve le retour visuel ; masquer l’arme masque ses effets sans imposer le silence. Les animations réduites désactivent recul, flash et tracer indépendamment du son. Le viewport du modèle cesse ses mises à jour lorsqu’il est masqué ou statique.

Pour ajouter un profil :

1. Ajouter une géométrie originale dans `weapon_viewmodel.gd` et deux WAV dans `assets/audio/`, avec les droits nécessaires.
2. Conserver les WAV en PCM 16 bits mono ; mettre `compress/mode=0` dans leurs paramètres d’import. La boucle utilise des positions en **frames**, pas en octets.
3. Créer une ressource `WeaponDefinition` sous `content/weapons/`, avec un identifiant unique, le point de flash normalisé et sa cadence visuelle.
4. L’enregistrer dans `WeaponCatalog.DEFINITIONS` et dans les identifiants autorisés de `SensitivityService.validate_profile`.
5. Adapter les tests qui vérifient le catalogue et l’export, puis vérifier l’aperçu, le volume, la boucle et son arrêt sur Windows.

`python3 tools/generate_audio.py` régénère de manière déterministe les six sons originaux livrés. Ce script de développement n’est ni embarqué ni nécessaire pour jouer.

## Vérifier le rendu

`bash tools/visual_smoke.sh` utilise un affichage X11 existant ou démarre un Xvfb/Xorg dummy temporaire. Il attend que l’affichage réponde, utilise le rendu logiciel et arrête uniquement le serveur qu’il a lancé. Les vérifications couvrent les pages et formats de fenêtre, les listes déroulantes, les réglages défilés, les bulles, le HUD, la pause, le repos et les bilans. Les débordements horizontaux et erreurs de script font échouer le contrôle. Les nombres de tests, les résultats de la dernière exécution et les validations encore nécessaires sont consignés dans `docs/TEST_PLAN.md`, pas présumés ici.

Les exemples de calibration et de courbe du harness sont synthétiques et isolés sous `user://tests/`. Ils ne démontrent aucune performance d’un joueur. Les captures de navigation publiées dans `docs/screenshots/` ne contiennent pas ces résultats de test.

Ce contrôle ne remplace pas une prise en main utilisateur, une écoute des sons, un essai natif Windows ou une mesure de souris physique. Voir `docs/TEST_PLAN.md`.
