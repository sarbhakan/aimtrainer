# Décisions et limites

## D01 — Version épinglée

Godot **4.7.2 stable**, édition standard, GDScript. Le binaire Linux et les export templates proviennent de la release officielle `godotengine/godot-builds/4.7.2-stable` ; leurs SHA-512 publiés sont épinglés dans `tools/setup_godot.sh`. Les deux archives sont vérifiées avant extraction et lors de leur réutilisation. Le wrapper refuse une autre version.

Le cloud disposait de 4.6.3 ; l'installation du projet est indépendante, dans `/workspace/.aim-local-tools`. Aucun changement des outils globaux n'est nécessaire.

Le correctif 4.7.2 pour les souris à haute fréquence est décrit dans l'article officiel [Fixing high polling rate mice on Windows in Godot](https://godotengine.org/article/fixing-high-polling-rate-mice-on-windows/), également vérifiable dans le [source du site Godot](https://github.com/godotengine/godot-website/blob/master/collections/_article/fixing-high-polling-rate-mice-on-windows.md). Ce correctif ne remplace pas un benchmark de cette application sur Windows.

## D02 — Rendu provisoire

Compatibility, géométrie primitive, matériaux mats, sans ombres dynamiques ni effets de post-traitement. Ce choix suit le point de départ du cahier des charges ; aucun benchmark comparatif avec Mobile n'a encore été réalisé.

VSync désactivée dans le projet ; limite FPS explicite 60/144/240/illimitée, défaut 144. Le driver ou le compositeur peuvent imposer d'autres limites : les frametimes mesurés restent nécessaires. Aucun FPS de rendu réel n'est déduit du headless.

## D03 — Input et unités de la V1

Capture pendant test et entraînement, `screen_relative`, sensibilité calculée en `914,4 / (DPI × cm360)` degré/count, pitch limité à ±89°. Défaut : 800 DPI et 35 cm/360°. Aucun lissage, accélération ou facteur de delta temporel n'est ajouté. Le FOV est **vertical**, 75° avec `KEEP_HEIGHT` ; inversion Y optionnelle. Le yaw/count cumulé conserve un `float` 64 bits, le yaw rendu est borné pour éviter de perdre la précision après de nombreux tours.

`Input.use_accumulated_input = true` reste le défaut, configurable. Ce n'est pas une conclusion de benchmark : true/false à 1/2/4/8 kHz restent à comparer sous Windows. Les deltas synthétiques valident le calcul logiciel ; l'équivalence aux counts matériels et le `cm/360` exigent un essai physique. Les timestamps sont ceux de réception applicative, pas ceux des paquets HID.

Les événements en attente sont vidés pendant l'état inactif avant capture/reprise. Aucun premier mouvement non nul n'est arbitrairement supprimé. Le protocole Windows doit encore vérifier l'absence de rotation parasite à la reprise.

## D04 — Distribution

Windows x86-64, export release avec PCK embarqué et toutes les ressources produit (`all_resources`) pour inclure les services globaux référencés implicitement. Tests, outils et documentation restent hors du pack de jeu. Le ZIP contient les notices officielles du moteur et de ses composants tiers. Le lancement isolé a détecté l'omission des services par l'ancien filtre de scènes ; le script interdit de distribuer un pack contenant ces erreurs.

L'exécutable n'est pas signé. L'édition des ressources PE est désactivée afin que Linux puisse exporter sans `rcedit`. Aucun installateur ni outil de jeu tiers n'est utilisé.

## D05 — Validation et scope

Le cloud Linux permet l'import, les tests synthétiques et l'export. Le serveur headless ne capture pas réellement le pointeur : ce contrôle est explicitement non exécuté dans ce mode. La simulation de durées de frame n'est pas un benchmark à FPS matériel constant.

Un lancement du pack exporté par le moteur Linux vérifie ses ressources mais ne constitue pas un lancement natif Windows. La demande de développement étend maintenant le prototype avec 16 exercices et une calibration V1 ; elle ne dispense pas des critères de réception physique du cahier des charges. Les exercices, scores, conversions et données locales sont implémentés, aucune collecte réseau ne l'est. Les 55 exercices et fonctionnalités avancées restent une cible, pas un scope déclaré terminé.

## D06 — Optimum local, pas sensibilité magique

Cinq contraintes complémentaires, trois réglages à ±10 % de vitesse angulaire, 15 familiarisations puis 45 essais mesurés contrebalancés. Les utilités sont normalisées uniquement par exercice puis pondérées selon l'objectif initial. Médiane et MAD scaled limitent l'effet d'une séance aberrante ; trois passages courts ne donnent pas un intervalle de confiance. Un petit écart ou une forte dispersion produit une plage, un mauvais confort empêche l'application, un bord de plage invite à affiner. Les poids, la marge de 3 % et les garde-fous p99/maximum de frametime sont heuristiques, documentés dans `CALIBRATION.md`, à valider avec de vrais joueurs.

## D07 — Mesure et coût borné

Génération seedée, grille réelle pour C03, intersections rayon/sphère analytiques, cibles exprimées en degrés à 8 m. Tracking intégré à 240 Hz avec maintien des poses, même replay identique entre 60/144/240 FPS. Ce sampling ne restitue pas les événements regroupés en amont et n'offre pas une précision temporelle infinie. Un tampon saturé invalide la séance. Six meshes réutilisés, statistiques lourdes calculées à la fin, aucun I/O dans le handler de mouvement. Le benchmark cloud de 200 000 événements ne prouve pas le polling matériel ni les FPS Windows.

## D08 — Données et progression

`user://` fixé au dossier `AIM_LOCAL`, schéma JSON 1, score 1, protocole 1. Profil/checkpoint : remplacement avec backup, précision complète et refus d'écraser des fichiers incohérents. Séances/bilans immuables, reprise transactionnelle et exports locaux CSV/JSON. Deux mille fichiers récents chargés dans l'historique ; pas de suppression automatique. Les contextes différents, échauffements, abandons et inactivité ne sont pas des records comparables. Cinq dernières médianes vs cinq premières après dix séances, sans mélange de sensibilité/difficulté.

## D09 — Conversion limitée à des coefficients connus

CS2 yaw 0,022 éditable ; Valorant yaw 0,07 documentaire, vérification en jeu obligatoire. Coefficient manuel pour d'autres titres/ADS, sans présumer un facteur générique Call of Duty. Conversion par cm/360°, pas par sensation de zoom. Aucun accès aux jeux tiers, injection, modification de configuration ou automatisation de saisie.

## D10 — Interface progressive et identité originale

La 0.2.0 remplace le formulaire dense par six destinations, des cartes filtrables et un aperçu. Les unités techniques restent dans les réglages et mesures repliés ; le parcours débutant commence par les DPI et un départ confortable. Le bilan présente une seule sensibilité repère, sans promesse de valeur parfaite. Le moteur, les 16 définitions, le protocole et le score restent inchangés.

Navigation latérale, bleu nuit/turquoise, icônes et illustrations originales : inspiration des conventions des aim trainers modernes, sans copier les ressources d’Aim Labs. Les animations sont courtes et désactivables. Le stretch global est désactivé pour garder un texte lisible en petite fenêtre ; `screen_relative` et les conversions physiques restent inchangés. Les aperçus et le sprite n’entrent pas dans la caméra ni les calculs.

## D11 — Armes et sons strictement cosmétiques

Trois profils originaux associent sprite, tir court et boucle continue, avec volume/silence et arme masquable. Les sons sont synthétisés hors du jeu, importés en PCM mono 16 bits sans compression ; quatre voix de tir et une boucle sont préallouées. Les tests ont détecté l’import QOA par défaut et imposent le format PCM attendu. La fin de boucle compte des frames audio.

Un clic reste un tir dans les exercices de clic/transitions, sans automatique ni modification du rythme mécanique. En tracking, maintenir le clic joue seulement un retour facultatif : le temps sur cible est mesuré sans tirer. Pause, focus, menu et résultats coupent le son, sans reprise automatique. Les préférences cosmétiques restent compatibles avec les anciens profils et n’altèrent pas les contextes de comparaison.

## D12 — Validation graphique distincte des essais matériels

Le cloud permet désormais 29 captures OpenGL Compatibility avec Mesa logiciel et affichage virtuel : six pages à trois tailles, listes déroulantes, réglages défilés, HUD et bilans. Le helper attend l’affichage et arrête uniquement son propre serveur. Les exemples de bilan et de courbe sont synthétiques, isolés des données produit et non publiés comme performances réelles.

Ces rendus ont permis de corriger les fonds, les retours à la ligne et les boutons enfouis dans les petites fenêtres. Ils ne certifient pas une expérience utilisateur réussie, les sons entendus, les FPS matériels, le scaling Windows ou les souris à haute fréquence. L’export isolé vérifie les armes/sons embarqués ; l’écoute et l’exécution native Windows restent à réceptionner.

Le thème est appliqué aux scènes d’interface, pas chargé comme thème global du projet avant l’import des SVG. Ce chargement anticipé provoquait des erreurs au premier import sans cache. Le build vérifie désormais aussi les journaux d’import et d’export, pas seulement leur code de sortie.

## D13 — Import physique et sensibilité visible, 0.3.0

La valeur AIM/LOCAL est editable dans Ma sensibilité, hors réglages avancés. Importer un profil tiers sépare DPI source et DPI actuels : on conserve la distance calculée, les DPI actuels restent ceux déclarés pour la souris. Une modification du DPI logiciel ne reconfigure jamais le matériel. Le réimport restaure le profil source historique, pas un mélange avec la sensibilité locale calibrée. Les valeurs canoniques ne sont pas relues dans des champs arrondis.

CS2/Valorant utilisent des coefficients documentaires ; CS2 propose un `m_yaw` personnalisé. Aucun yaw universel CoD n’est supposé : titre/version et tour complet mesuré à la règle sont obligatoires. La provenance est qualifiée et ne constitue pas une certification de la mesure. Zoom/ADS et FOV ne sont pas automatiquement équivalents.

## D14 — Calibration par blocs, protocole 2

Chaque exercice possède trois familiarisations puis trois séries A/B/C mesurées. Les positions des candidats tournent ; l’ordre des exercices reste fixe et le parcours n’est pas aveugle. Le joueur voit la sensibilité active et les comparaisons médianes par exercice, peut refaire après le repos minimal et valide explicitement le passage. Les utilités, pondérations et garde-fous de score 1 sont conservés. Ce protocole expérimental produit un compromis dans la plage testée, pas une découverte causale d’un optimum.

Un ancien checkpoint protocole 1 reconnu est archivé avant une nouvelle comparaison. Il ne peut pas être repris sous protocole 2/révision 2. Un fichier incohérent, un protocole inconnu ou une archive contradictoire bloque le remplacement pour protéger les données.

## D15 — Géométrie versionnée, pas de difficulté cachée

Les exercices passent en révision 2 : profondeur 4 m, origine caméra réelle, silhouette et collision cohérentes, contrôle de toute la sphère aux bords du frustum. C02 passe explicitement de 0,65° à 1,2° pour une micro-précision d’entrée utilisable ; C05/T09 restent plus exigeants. C07 n’est plus masqué par le sol. S02 dispose de couloirs séparés, T03 normalise sa vitesse diagonale et T05 retourne en 120 ms à accélération finie. Les anciennes séances restent conservées, sans mélanger leurs records avec les nouvelles empreintes.

## D16 — Inspiration et audit indépendant

Quatre agents ont travaillé sur armes, géométrie, recherche/QA et aperçus, avec périmètres disjoints et tests de régression. L’audit adversarial a identifié des réimports réinterprétés, une confusion DPI et une migration bloquée ; ces cas doivent rester couverts avant publication. Les bots exécutent des scénarios logiciels : ils ne remplacent ni un utilisateur ni une souris physique.

Les conventions publiques des aim trainers servent de référence ; aucun algorithme, score ou asset propriétaire d’Aimlabs n’est annoncé comme reproduit. Les sites officiels indisponibles dans cette session restent non vérifiés, selon `docs/REFERENCE_TASKS.md`. Démonstrations originales, bulles au survol/focus/clic, panneaux répartis sur la largeur disponible et retour HUD vers le viseur remplacent une interface centrée et une arme statique. Ces effets restent cosmétiques.

## D17 — Recherche guidée bornée, 0.4.0

Protocole 3 avec facteurs configurables et reprise compatible 2. Le novice explore 0,5/1/2, puis recentrage sur un bord nettement meilleur et confortable ou affinage à 25 % puis validation à 10 %. Chaque comparaison conserve les cinq exercices et 45 mesures ; maximum quatre comparaisons et deux déplacements. L’incertitude ne déclenche pas une escalade aveugle. Un résultat stable autorise seulement un essai consenti et demande confirmation différée ; rien d’universel ou de causalement prouvé.

## D18 — Cohérence, records et arrondis

La clé est recalculée depuis les conditions du rapport, et le score depuis ses mesures. Changer révision, moteur, renderer ou empreinte sans changer la clé rend le rapport incohérent. Le backend Compatibility est implicite dans les anciens rapports sans renderer. L’exposition continue des suivis 0.1–0.3 peut être lue depuis la durée active, sans réécriture. Un record exige une sauvegarde réussie et un contexte identique. Les styles de viseur/arme restent cosmétiques hors clé mécanique : la progression affichée ne prouve pas une causalité.

Le canonique des champs source est indépendant du Range arrondi ; focus/blur sans édition conserve les métadonnées exactes en mémoire. La relecture JSON peut déplacer les derniers bits, tolérance relative 1e−14 explicitée. Recherche et comparaison sont écrites en une transaction ; panne et reprise ne valident pas deux fois un passage.

## D19 — Cadrage sans trahir la souris

Les cibles restent ancrées dans la zone mondiale. Une rotation pendant le countdown peut mettre cette zone hors champ, sans occlusion par le sol. Le départ attend donc le réalignement avec repère/flèche avant de mesurer. Aucun count supprimé, aucun snap de caméra, aucune cible déplacée pour corriger ce cas. Les régressions vérifient les rotations ±30° et la reprise par vrais deltas.

## D20 — Exercices et préparation, 0.5.0

Les seize exercices passent en révision 3 : tailles angulaires d’entrée plus confortables, amplitudes et profondeur choisies par objectif, précision avancée explicitement distincte. Rapprocher le décor seul n’agrandit pas une cible exprimée en degrés. Le joueur ne se déplace pas ; le FOV reste celui du profil et aucune adaptation cachée ne survient pendant une comparaison. Les compromis sont décrits dans `EXERCISE_DESIGN_050.md` ; ils demandent encore des essais utilisateurs, pas une imitation prétendue des algorithmes privés d’Aimlabs.

Le départ 3, 2, 1 présente les cibles figées via un moteur de préparation séparé ; elles reprennent la même graine lorsque le chronomètre mesuré démarre. Les mouvements préparatoires restent réels mais exclus des mesures. Le HUD garde uniquement temps à gauche, touches/précision ou suivi à droite et score V1 évolutif recalculé à 10 Hz. La formule reste celle du service de score. Aucun texte d’aide permanent devant la zone de tir.

## D21 — Conserver sans comparer des difficultés différentes

Le score V1 et le protocole 3 restent identiques, pas leurs empreintes d’exercice. Les checkpoints de révision 2 sont rejoués avec cinq définitions historiques figées, y compris les recherches guidées et leurs décisions. Seuls les historiques reconnus sont archivés avant une nouvelle comparaison ; CRLF, Unicode et précision d’origine sont conservés octet pour octet. Inconnu, incohérent, verrou ou archive contradictoire interdit l’écrasement. Aucun bilan ancien n’est transformé en conseil valable pour la nouvelle difficulté.

## D22 — Présentation native plutôt que changement de moteur

Godot permet des viewmodels réellement 3D et une UI responsive : migrer le moteur n’est pas nécessaire pour corriger ces problèmes visuels. Trois armes originales procédurales sont rendues dans un monde isolé ; recul et flash n’atteignent ni caméra de visée ni hitbox. L’option de masquage reste disponible. Décor virtuel statique, sans ombres dynamiques, et surfaces sobres favorisent le contraste des cibles. Les sensations, sons et performances GPU Windows restent à réceptionner.

Les composants emploient une échelle commune de 4/8/12/16/24/32 px. Sensibilités affichées à deux décimales, float canonique conservé indépendamment des champs lisibles ; aucune quantification de l’input ni du profil. Les coefficients techniques ne sont pas des sensibilités et restent dans les réglages avancés. Les démos sont contenues et n’affichent plus de FOV/ratio permanent ; ce sont des animations du moteur, pas des vidéos propriétaires.

## D23 — Direction artistique avant réalisation, 0.6.0

Deux planches originales précèdent le code : Precision Lab clair, perle/béton, graphite/cobalt, cibles corail et trois silhouettes d’armes. Elles restent explicitement des concepts, pas des captures. Matériaux éclairés, lumière directionnelle/ombres et remplissage remplacent la grille sombre ; géométrie du décor statique bornée à 32 meshes. Viewmodels biseautés et gantés, cache des meshes, aucun mouvement de caméra ou de hitbox. Les captures réelles et les essais GPU/son matériels restent distincts.

Scroll natif sans barre, commandes Actualiser/Copier par icônes accessibles, démos sans badge et countdown sans consigne répétée. Le suivi du focus est explicite lorsque SHOW_NEVER ne révèle pas seul le contrôle ciblé. La largeur flexible du catalogue évite une boucle de minimum du grid lors du redimensionnement.

## D24 — Changement consenti, conditions séparées

En pause, modifier la valeur locale ou Valorant/CS2 puis appliquer redémarre l’essai. Le profil est sauvegardé d’abord ; l’ancien passage garde son profil et devient un abandon exclu des records. Un refus de profil conserve le passage suspendu. Un refus de rapport conserve celui-ci en mémoire, présente l’erreur et bloque la relance avant enregistrement ; la fermeture exige de confirmer sa perte. Les quatre entrées de calibration vérifient cette sauvegarde avant d’activer leurs flags. Pendant la comparaison, le réglage reste verrouillé.

## D25 — Variations explicites et relecture numérique

Chaque pratique rejouée renouvelle sa graine, conservée dans le rapport ; les graines appariées et les cinq empreintes r3 de calibration restent inchangées. D01/D02/S02 uniquement passent en r4 : rétrécissement borné par l’âge de la cible, destinations non cycliques interpolées et profondeurs par apparition. Même fonction géométrique pour silhouette, rayon et métriques ; aucune adaptation à la réussite. Les anciens records restent stockés dans leurs contextes propres.

Le score V1, ses valeurs générées et ses utilités ne changent pas. La relecture JSON peut déplacer un float d’un dernier bit autour d’un demi-point : cinq replays seedés ont reproduit le rejet de rapports intacts à 112,5 points. La vérification admet uniquement les deux entiers voisins lorsque le score non arrondi est à huit epsilon doubles relatifs du demi-point (tolérance plafonnée à 0,000001 point). Hors de cette frontière, même un point altéré est rejeté ; à la frontière, fractions et écarts de deux points le sont. Le rapport et son score ne sont pas réécrits. Cette borne numérique ne constitue pas une certification anti-triche des données locales.
