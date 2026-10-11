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
