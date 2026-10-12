# Plan de validation

## Refonte 0.6.0 — 12 octobre 2026, UTC

Direction artistique produite avant l’implémentation : deux planches conceptuelles originales, puis trois lots UI/armes/patterns et un audit indépendant des sauvegardes. Les concepts sont distincts des captures réelles.

| Contrôle | Résultat final |
|---|---|
| Suite intégrée input/UI/UX/calibration/archives/armes/pause | **10 664 assertions, 0 échec** ; capture physique du pointeur non exécutée en headless |
| Géométrie et silhouettes | **2 049 assertions, 0 échec** ; seize exercices, rayons/depths temporels, frustum, sol et vitesses |
| Recherche adaptative | **906 assertions, 0 échec** ; protocole 3 conservé |
| Scroll, espacement et focus | **385 assertions, 0 échec** ; barres invisibles, gestes, clavier, icônes accessibles et précision canonique |
| Projection des aperçus | **8 176 assertions, 0 échec** ; plus de badge, même silhouette temporelle que la hitbox |
| Patterns et graines | **1 918 assertions, 0 échec** ; D01/D02/S02 r4, cinq empreintes de calibration r3 et archives r2 inchangées |
| Relecture des scores JSON | **32 771 assertions, 0 échec** ; 512 graines par exercice, frontières numériques et altérations refusées |
| Rendu OpenGL Compatibility/Mesa, Xorg dummy | **86 captures, 0 échec** ; trois tailles, pause modifiable/verrouillée, décompte, seize exercices, trois armes et instantanés des variantes |
| Import sans cache et démarrage isolé | Code 0, journaux sans ERROR/SCRIPT ERROR, manifestes SHA-256 identiques avant/après import |
| Export Windows et pack ouvert sous Linux hors checkout | EXE PE x64/PCK, seize exercices, trois viewmodels/imports, protocole 3/recherche et quatre viseurs, 0 échec ; trois contrôles supplémentaires du pack final réussis |
| ZIP Windows et galerie Mac | Intégrité et SHA-256 vérifiés ; seulement les distributions 0.6.0 dans downloads |
| Débit logiciel | 200 000 événements caméra/timeline : **319,32 ms**, 1,597 µs/événement, tampon max 183/32 768, six cibles ; aucune conclusion comparative ou matérielle |
| Windows natif, son entendu, souris/scaling/latence/GPU et réception humaine | **Non exécutés** |

Total des sept runners : **56 869 assertions sans échec**. `tools/test.sh` vérifie compilation, assertions positives, marqueur terminal, timeout et erreurs/fuites ; l’export réexécute ces contrôles. Les tests UI supplémentaires de l’agent et ses 18 rendus d’armes sont des contrôles distincts, pas additionnés au total.

Contre-exemples traités avant distribution :

- Avec le scroll horizontal désactivé, le grid pouvait conserver son minimum de cinq colonnes et empêcher une réduction à 800 px. La bibliothèque garde sa largeur flexible ; les autres panneaux restent sans débordement.
- SHOW_NEVER ne suffisait pas à suivre le focus dans tous les cas : révélation explicite du contrôle ciblé et navigation Page/Fin testées, sans désactiver le scroll.
- Les anciens tests réservaient encore 18 px au badge et utilisaient le rayon nominal pour S02/D01. Ils vérifient maintenant le cadre complet et la géométrie réellement rendue à chaque instant, sans supprimer les contrôles de collision.
- Un échec de stockage de l’abandon après réglage pouvait rester silencieux. Le rapport avec UID stable est retenu, le bilan signale l’erreur, la relance réessaie l’écriture et la fermeture demande confirmation. Les quatre entrées de calibration ne laissent pas de flags actifs après refus.
- Un premier contrôle du pack aléatoire a échoué : la campagne de 8 192 rapports a reproduit cinq scores tracking rejetés après JSON autour de 112,5 points. La vérification admet seulement les deux entiers voisins à la frontière au dernier bit ; les scores V1, utilités et fichiers ne sont pas réécrits. Un point altéré ailleurs, une fraction et deux points à la frontière restent refusés.
- Un import isolé concurrent s’est terminé par SIGABRT après l’import. Le contrôle a été réexécuté séquentiellement avec arrêt obligatoire sur code non nul ; import et démarrage passent, sources intactes. Le premier journal sans ERROR n’a pas été considéré comme un succès.

Les anciens résultats ci-dessous sont des jalons historiques, pas des preuves matérielles de la 0.6.

## Refonte 0.5.0 — 12 octobre 2026, Europe/Paris

Godot `4.7.2.stable.official.ed1daf0bf`, Linux. Quatre agents ont implémenté des lots disjoints ; intégration, revue des rendus et publication sont coordonnées séparément.

| Contrôle | Résultat final |
|---|---|
| Suite intégrée UI/UX/input/moteur/archives/armes | **10 431 assertions, 0 échec** ; capture physique du pointeur non exécutée en headless |
| Géométrie des seize exercices r3 | **2 001 assertions, 0 échec** ; frustum, silhouette/hitbox, sol, espacement et vitesses |
| Recherche adaptative | **906 assertions, 0 échec** |
| Espacement et petites valeurs | **91 assertions, 0 échec** ; trois tailles, valeurs canoniques et coefficient avancé |
| Projection et bulles | **7 084 assertions, 0 échec** ; confinement, redimensionnement, visibilité et replay indépendant |
| Rendu OpenGL/Mesa + Xorg dummy | **77 captures, 0 échec** ; trois tailles, seize exercices, trois modèles, countdown, menus et effets |
| Import sans `.godot/`, puis lancement isolé | Code 0, aucun `ERROR`/`SCRIPT ERROR` ; manifeste de sources identique avant/après import |
| Export Windows 0.5.0 et pack ouvert hors checkout | 16 exercices r3, 3 vrais viewmodels, 3 imports, protocole 3/recherche et 4 viseurs ; 0 échec |
| ZIP Windows et galerie Mac | Intégrité ZIP et SHA-256 vérifiées ; EXE PE x86-64/PCK + notices, galerie de 77 PNG séparée |
| Débit logiciel hors rendu | 200 000 événements en 309,03 ms, 1,545 µs/événement, tampon max 183/32 768 et six cibles ; pas une mesure de latence matérielle |
| Souris physique, son entendu, scaling/latence/GPU Windows et essais humains | **Non exécutés** |

Total final : **20 513 assertions logicielles sans échec**. `bash tools/test.sh` exécute les cinq runners avec compilation préalable, assertions positives, marqueur final, timeout et refus des erreurs/fuites signalées. L’export a d’abord exécuté 20 508 assertions ; la suite finale ajoute cinq contrôles contre les empreintes r2 réellement publiées, sans changement des sources produit ni du ZIP.

Contre-exemples corrigés :

- Les libellés HUD auto-wrap pouvaient devenir verticaux et étirer les cartes sur toute la hauteur. Le retour à la ligne est désactivé pour les compteurs/GO, les cartes restent compactes ; contrôles aux trois tailles ajoutés.
- C03 conserve une grille 3×3, mais ses bornes r3 sont ±18°/±10° : la fixture métier utilisait encore ±16°/±9°. Elle vérifie désormais les cellules de la définition versionnée, avec les contrôles géométriques explicites de r3.
- Les cinq exercices de calibration sont reconstruits depuis des paramètres r2 figés et leurs SHA-256 publiés, pas depuis les nouveaux `.tres`. Checkpoints v2/v3 vides, partiels et complets, recherches guidées, erreurs et fichiers falsifiés restent couverts.
- Une ouverture/fermeture de la très petite sensibilité valide à 64 000 DPI/150 cm pouvait recalculer le canonique depuis le paramètre arrondi du signal natif. `precise_value_changed` filtre cette fausse modification ; profil exact conservé. Les faibles valeurs sont affichées « <0,01 », jamais zéro. `m_yaw` avancé garde sa précision utile.
- Le curseur d’aperçu masquait presque entièrement C02 miniature. Son centre est ouvert, sans changer la projection, les cibles, leur taille ou le RNG. La main du viewmodel est cadrée avec une arme plus petite/plus éloignée, sans changer la caméra de visée.
- Le rendu logiciel peut dépasser les 65/110 ms des effets courts. Tir/impact sont vérifiés immédiatement, puis figés uniquement pour la capture. Durées réelles, arrêt, recyclage et indépendance du score sont testés séparément. Ces PNG ne constituent pas une vidéo de fluidité matérielle.

La réinstallation épinglée revalide les deux SHA-512 officiels. Elle réextrait temporairement le binaire : ne pas la lancer en parallèle des validations. Une telle concurrence a interrompu un premier runner après ses suites réussies ; la validation finale complète est relancée une fois l’installation terminée.

Sources produit identiques entre import vierge, export et checkout. Les exemples de progression/calibration/record restent synthétiques sous `user://tests`, jamais des données de joueur. Le décor statique et les viewports masqués au repos ne dispensent pas d’un benchmark GPU Windows.

### Réception 0.5 sous Windows

1. Comparer la taille des cibles normales et des défis avancés ; tester chaque famille et les FOV extrêmes, le repère de réalignement, les trois secondes de préparation sans score et la pause/focus.
2. Importer puis recopier CS2/Valorant/profil CoD mesuré. Vérifier à la règle, éditer les champs puis les ouvrir/quitter sans changement ; contrôler DPI actuels/source et précision conservée.
3. Tester armes visibles/masquées, recul/flash, hitmarker, volume/silence, maintien tracking, animations réduites et reprise sans tir automatique ; le score ne doit pas changer selon l’arme.
4. Redimensionner, tester scaling 100/125/150/200 %, clavier et survol ; aucune bulle débordante, texte collé ou action inaccessible.
5. Refaire des comparaisons guidées sur plusieurs jours ; conserver les archives r2 et séparer les records r2/r3, confirmer confort et progression. Aucun optimum universel n’est garanti.

## Historique

## Finition 0.4.0 — 12 octobre 2026, Europe/Paris

Godot `4.7.2.stable.official.ed1daf0bf`, Linux. Résultats après intégration des lots UI, UX, gameplay, feedback et calibration ; les essais précédents restent historiques.

| Contrôle | Résultat |
|---|---|
| Suite intégrée UI/UX/moteur/import/viseur/reprise/records | **5 469 assertions, 0 échec**, 1 contrôle physique non exécuté en headless |
| Régressions géométriques | **1 560 assertions, 0 échec** |
| Calibration adaptative | **906 assertions, 0 échec** ; bornes, bruit, inconfort, contexte, historique falsifié, consentement, recentrage d’affinage et 240 passages synthétiques |
| Rendu Mesa llvmpipe et Xorg dummy | **53 captures, 0 échec** ; trois tailles, onglets, bulles, viseurs, impact réel du moteur, footer fixe, tableau et recherche guidée |
| Import vierge sans `.godot/` et lancement isolé | Code 0, aucun `ERROR`/`SCRIPT ERROR` ; mêmes sources que le build final |
| Export Windows 0.4.0, pack lancé hors checkout | Code 0 ; 16 exercices, 3 armes, 3 imports, protocole 3/recherche guidée et 4 viseurs, zéro échec |
| ZIP, PE x64/PCK, notices et SHA-256 | Vérifiés ; seule la version 0.4.0 est conservée dans les téléchargements |
| Benchmark logiciel | 200 000 événements en 292,23 ms, 1,461 µs/événement, tampon max 183/32 768, 6 nœuds ; observation concurrente, pas benchmark matériel |
| Souris physique, écoute, scaling/latence Windows et essais humains | **Non exécutés** ; aucune validation matérielle ou amélioration causale revendiquée |

Total logiciel : **7 935 assertions sans échec**. Les runners exigent compilation préalable (`--check-only`), marqueur final avec assertions positives, journaux sans erreur ni fuite signalée, et timeout. Un code de sortie zéro ou des tests qui n’ont pas fini ne suffit pas.

### Contre-exemples et corrections

- QA indépendante : 13 RED initiaux ; contexte moteur/rendu/révision/empreinte altéré avec ancienne clé était accepté. La clé est maintenant reconstruite depuis les métadonnées du rapport, le score depuis les mesures, et ces incohérences sont refusées avant stockage ou record. Les rapports anciens cohérents restent lisibles.
- Source CS2 à nombreuses décimales : un focus/blur pouvait décaler un float d’un dernier bit et provoquer une reconstruction de la référence. Le canonique est séparé du Range ; tests ciblés **85 assertions** et UX **205**, zéro échec. L’ancien formulaire produit neuf RED sur les mêmes cas. Certains RED initiaux étaient des fixtures sans `invert_y` ou une égalité JSON bit à bit injustifiée : détails dans `docs/QA_040_IMPORT.md`.
- Le fixture « aucun signal » de l’ancien audit affichait 100 % de précision sans tir : il est réellement incohérent, pas un bug du validateur. Les vrais essais sans signal conservent des tirs ratés cohérents et ne donnent pas de conseil.
- Poses initiales ±30° : pas d’occlusion par le sol, mais une zone mondiale peut être hors frustum. Le départ attend désormais un réalignement avec repère/flèche, sans supprimer les counts ni snap de caméra. Source de l’audit : `docs/GAMEPLAY_040_REVIEW.md`.
- Les faux champs de scénario introduits pendant l’intégration ont été détectés par les tests d’exécution, corrigés vers `yaw_extent_deg`/`pitch_extent_deg`, puis les suites et rendus réexécutés. La compilation seule ne prouve pas un parcours fonctionnel.

Les assertions de parcours couvrent recherche/comparaison écrites ensemble, dernier passage terminé avant décision, rollback d’écriture, transition relue, double acceptation interdite, reprise aux nouveaux candidats, version inconnue/archives conflictuelles protégées et essai stable uniquement consenti. Les records proviennent aussi de vrais raycasts sur dix cibles par événements synthétiques ; panne, interruption et contexte modifié ne sont jamais célébrés.

Les préférences de viseur/arme restent hors clé mécanique. Elles peuvent influencer la perception : médiane/record mesurent les séances, pas une preuve causale de développement d’une habileté. La recherche garde un même profil et des conditions verrouillées pendant ses comparaisons.

Les captures de progression, records et conseils sont des fixtures isolées avec notice visible. Les valeurs du tableau de démonstration suivent la formule du score, mais ne sont pas les performances d’un joueur. Seules les captures de navigation sont publiées comme interface dans `docs/screenshots/`.

### Réception 0.4 sous Windows

1. Vérifier navigation souris/clavier, sélection persistante au survol, animations réduites et petites fenêtres. Les CTA de résultats restent visibles pendant le scroll.
2. Personnaliser les quatre viseurs, couleur/contour et dimensions ; enregistrer, redémarrer, vérifier HUD/aperçu et absence d’effet sur caméra ou collision.
3. Cliquer et manquer : hitmarker uniquement sur touche, aucune trace dans le centre du viseur. Tester maintien en suivi, pause, Alt+Tab, silence et reprise explicite.
4. Détourner la caméra pendant le countdown : repère/flèche, aucune mesure avant réalignement ; pas de rotation forcée.
5. Terminer une séance comparable et battre son record ; vérifier animation, date/tableau et bonne clé. Changer durée/DPI/FOV : pas de mélange. Interruption et panne d’écriture : pas de record annoncé.
6. Comparer un réglage connu puis faire une recherche guidée complète. Vérifier plages successives, bruit/inconfort, pause entre comparaisons, fermeture/reprise, consentement et conversion inverse. Confirmer à deux puis sept jours ; ne pas extrapoler un optimum universel.

## Itération 0.3.0 — 11–12 octobre 2026, Europe/Paris

Godot `4.7.2.stable.official.ed1daf0bf`, Linux. Validation finale après intégration des quatre agents ; les résultats précédents restent historiques.

| Contrôle | Résultat |
|---|---|
| Suite intégrée : domaine, UI, import, armes, blocs, bulles, migration | **2 186 assertions, 0 échec**, 1 contrôle de capture réelle non exécuté en headless |
| Régressions géométriques lancées par `tools/test.sh` | **1 560 assertions, 0 échec** ; projections, rayons, sol, séparation, vitesse et taille C02 |
| Import vierge sans `.godot/`, puis démarrage dans une copie isolée | Codes 0, aucune erreur de script/ressource ; sources et scénarios identiques au checkout final |
| Rendu Mesa llvmpipe avec Xorg dummy | **41 captures, 0 échec** : six pages en 800×450/1280×720/1920×1080, bulles d’accueil/catalogue, imports/conversions, tir/recul, repos et bilan |
| Export Windows 0.3.0 et ouverture du pack hors checkout | Code 0, aucune erreur de script/ressource |
| Harness externe sur le pack exporté | **16 exercices révision 2, 3 armes, 3 imports et protocole 2**, 0 échec ; ressources de tests absentes du pack |
| Archive Windows | PE x86-64/PCK embarqué, ZIP intègre et SHA-256 vérifié ; EXE et notices, aucun ancien exécutable dans le ZIP |
| Benchmark logiciel corrigé pour l’origine caméra réelle | 200 000 événements en **165,67 ms**, 0,828 µs/événement ; tampon max 183/32 768 et 6 nœuds |
| Windows natif, écoute, souris physique, essais humains et jeux tiers | **Non exécutés**, nécessaires à la réception ; aucun polling matériel, gain joueur ni FPS Windows revendiqué |

`tools/test.sh` exige la fin effective de chacun des deux runners avec un nombre d’assertions positif, rejette les erreurs de script/ressource et les fuites signalées, même avec code Godot nul. L’export réexécute cette suite puis impose les trois marqueurs du harness isolé. Le benchmark n’est qu’une observation dans cette instance, pas un seuil CI ou une preuve de performance matérielle.

### Vérifications réparties entre agents

- **Arme/HUD** : recoil 220 ms, flash 65 ms, trace 45 ms vers le viseur ; aucun effet sur caméra/score. Voix audio bornées, silence, maintien, pause, focus et animation réduite. Les tests isolés de l’agent couvraient aussi 27 captures ; la validation finale intégrée est comptée ci-dessus.
- **Géométrie** : C07 auparavant sous le sol, S02 se chevauchant, vitesse diagonale T03 et inversion T05. C02 atteint 9,826 px à 720p/FOV 75° et 6,142 px à 450p, sans agrandir une hitbox cachée. Le runner graphique de l’agent a effectué 1 581 assertions et sept captures, distinct du runner headless final.
- **Aperçus** : survol/focus temporisé, clic explicite, sélection inchangée au survol, filtres/recherche/défilement/Échap, animations masquées arrêtées. Une bulle anormalement haute dans un conteneur a été reproduite puis corrigée ; le test vérifie les limites après allocation réelle des frames, pas seulement la taille initiale.
- **Recherche/QA adversariale** : séparation DPI source/actuels, rebind CS2 `m_yaw` personnalisé, mesure CoD historique intacte après calibration, valeurs extrêmes, écritures refusées et handler sans référence. Les constats initiaux et leurs retests sont conservés dans `docs/QA_REVIEW.md` ; les limites documentaires dans `docs/REFERENCE_TASKS.md`.
- **Intégration parent** : protocole 2 en cinq blocs contigus 3+9, graines/positions équilibrées, warm-up exclu, retry après repos sans avancer le checkpoint, cinq comparaisons avec les vraies valeurs A/B/C. Migration proto1 vide/partielle/complète, archivage octet pour octet, collisions/corruption/protocole inconnu refusés, sans altérer les anciens scores.

Les fixtures utilisent des dossiers uniques sous `user://tests/`. Les exemples de CoD, repos, bilan et courbe sont synthétiques : aucun résultat de joueur ni mesure réellement faite dans CoD n’est annoncé. Les screenshots de navigation publiés ne présentent pas de scores de démonstration. Une attente de fermeture de 100 ms laisse le mixer traiter les commandes d’arrêt du fixture de tir ; le runner ne masque pas une fuite.

```bash
bash tools/godot.sh --headless --editor --import
bash tools/test.sh
bash tools/visual_smoke.sh
bash tools/export_windows.sh
cd downloads
sha256sum --check AimLocal-0.3.0-windows-x64.zip.sha256
unzip -t AimLocal-0.3.0-windows-x64.zip
```

### Réception Windows de cette version

1. Extraire tout le ZIP dans un dossier vierge ; vérifier fenêtres minimale/large, scaling Windows, accès visible à la sensibilité et bulles au survol, au clavier et au clic.
2. À **1 600 DPI actuels**, importer VALORANT **0,35 à 800 DPI source** sans changer la souris : conversion vers 800 DPI = 0,35, vers 1 600 = 0,175 ; mesurer la même distance de tour complet dans les deux jeux, sans zoom. Vérifier aussi CS2 avec `m_yaw` personnalisé et les réimports sans modification.
3. Pour CoD, inscrire titre/version/mode et une mesure réellement faite à la règle. Vérifier source → AIM/LOCAL → source, puis changer la sensibilité locale et rouvrir : la référence historique ne doit pas devenir une nouvelle mesure fictive. Sans mesure, le bouton doit rester désactivé.
4. Jouer les cinq blocs de calibration ; refaire un passage avant validation, vérifier pause/reprise/redémarrage, confort, graines et médianes. Confirmer le conseil un autre jour ; ne pas extrapoler une garantie à tous les jeux ou au-delà de la plage testée.
5. Parcourir les 16 exercices : cibles sans occlusion par le sol, sphères/hitboxes cohérentes, mouvements séparés et inversions continues. C05/T09 sont volontairement avancés, sans adaptation de difficulté cachée.
6. Écouter les trois armes, tester clic/maintien, volume zéro, arme masquée, animations réduites et Alt+Tab ; aucune reprise de tir automatique ni rotation de caméra cosmétique. Réceptionner ensuite les mesures physiques 2–8 kHz, latence et frametimes décrites plus bas.

## Historique — interface 0.2.0

## Refonte 0.2.0 — 11 octobre 2026

Godot `4.7.2.stable.official.ed1daf0bf`, Linux ; les résultats 0.1.0 sont conservés plus bas comme historique, pas comme mesures de cette refonte.

| Contrôle | Résultat |
|---|---|
| Import et suite GDScript | 797 assertions, 0 échec, 1 contrôle de capture physique non exécuté |
| Import vierge sans `.godot/`, puis démarrage dans une copie isolée | Codes 0, aucune erreur de script/ressource ; thème chargé après import des SVG |
| Rendu graphique avec Mesa llvmpipe et Xorg dummy | 29 captures, 0 échec ; six pages à 800×450, 1280×720 et 1920×1080, listes déroulantes, HUD, pause, repos, bilans et courbe isolée |
| Export Windows 0.2.0 et démarrage du pack isolé | Code 0, aucune erreur de script/ressource |
| Harness externe sur le pack exporté | 16 exercices et 3 profils d’arme embarqués, 0 échec |
| Archive Windows | ZIP, PE x86-64/PCK, notices, intégrité ZIP et SHA-256 vérifiés |
| Windows natif, écoute, souris physique et validation utilisateur | Non exécutés ; nécessaires avant réception finale |

La nouvelle couverture vérifie navigation/filtres/recherche, consignes et aperçus, arrêt des traitements masqués, compatibilité des anciens profils, conservation de la distance physique lors d’un changement de DPI, préférences cosmétiques hors du contexte de score, trois sprites/six sons PCM distincts, frames de boucle, voix bornées, silence, clic simple vs maintien en tracking, arrêt sur focus/pause/menu et recommandation sans familiarisations. Les erreurs de sauvegarde restent visibles même quand les détails sont repliés. Les captures synthétiques de courbe/bilan ne sont jamais ajoutées aux données réelles.

```bash
bash tools/godot.sh --headless --editor --import
bash tools/test.sh
bash tools/visual_smoke.sh
bash tools/export_windows.sh
cd dist
sha256sum --check AimLocal-0.2.0-windows-x64.zip.sha256
unzip -t AimLocal-0.2.0-windows-x64.zip
```

Le contrôle graphique requiert X11 ou Xvfb/Xorg avec le pilote dummy ; il refuse le headless et ne confond pas absence d’affichage avec succès. Il démarre si besoin un affichage temporaire, attend sa disponibilité et le ferme à la sortie. L’avertissement Mesa concernant VSync n’est pas une erreur de script. Le rendu logiciel n’est pas un benchmark Windows. Aucun nouveau benchmark matériel n’est annoncé.

### Réception UX et audio sous Windows

En complément des essais physiques plus bas :

1. Extraire le nouveau ZIP dans un dossier vierge ; ouvrir les six destinations, les listes de durée/jeu, puis parcourir les cartes avec souris et clavier. Vérifier les tailles minimale et normale, ainsi que le scaling Windows.
2. À 800×450, vérifier que « Lancer l’exercice » et « Enregistrer » restent accessibles et que la fiche, les réglages et les résultats défilent sans débordement horizontal.
3. Faire essayer « Ma sensibilité » à une personne sans connaissance de cm/360° : elle doit pouvoir entrer ses DPI, comprendre le confort, reprendre un test et appliquer/copier le conseil sans ouvrir les détails.
4. Écouter Pulse, Vector et Classic au casque à faible volume : tirs distincts, boucle sans clic audible, aucun son résiduel après relâchement, Échap, Alt+Tab, menu ou résultats. Vérifier silence, volume zéro et retour après pause sans tir automatique.
5. Dans un exercice de clic, maintenir le bouton ne doit pas tirer plusieurs fois. En suivi, tester avec/sans clic maintenu : la mécanique de mesure ne doit pas dépendre de ce retour audio. Masquer l’arme et réduire les animations ne doit pas faire tourner la caméra.
6. Enregistrer les préférences, redémarrer et les retrouver ; charger aussi un profil 0.1.0. Vérifier que les anciens résultats comparables restent présents et qu’aucune courbe de démonstration n’apparaît.

## Historique — V1 0.1.0

## Résultats cloud du 11 octobre 2026

Godot `4.7.2.stable.official.ed1daf0bf`, Linux sans serveur graphique :

| Contrôle | État |
|---|---|
| Installation épinglée et SHA-512 officiels | Nouvelle exécution vérifiée sans téléchargement, version correcte |
| Suite GDScript | 657 assertions, 0 échec, 1 contrôle physique non exécuté |
| Benchmark logiciel caméra/timeline/pool | 200 000 événements en 235,31 ms (1,177 µs/événement), tampon max 183/32 768, 6 nœuds |
| Import, startup headless et export Windows V1 | Code 0, aucune erreur de script/ressource |
| Pack isolé : lancement et 16 exercices embarqués | Code 0, 16 exercices terminés, 0 échec ; tests exclus du pack |
| ZIP, en-têtes PE x86-64/PCK, SHA-256 | Vérifiés, ZIP intègre EXE et notices officielles |
| Exécution native Windows, souris réelle, latence | Non exécutées, réception manuelle nécessaire |

La valeur du benchmark est une observation dans cette instance, pas une garantie ou un seuil de CI. Les timestamps 8 kHz sont synthétiques ; aucun paquet matériel 8 kHz n'a été reçu. La Phase 0 précédente avait 35 assertions ; les résultats ci-dessus concernent la nouvelle logique, sans extrapoler la réception Windows de cette ancienne version. Le contrôle isolé a détecté les services omis par le filtre de scènes : le preset `all_resources` corrige l'inclusion, puis l'ensemble du build et des contrôles a été réexécuté.

## Commandes

```bash
bash tools/godot.sh --headless --editor --import
bash tools/test.sh
bash tools/godot.sh --headless --script res://tests/benchmark.gd
bash tools/export_windows.sh
cd dist
sha256sum --check AimLocal-0.1.0-windows-x64.zip.sha256
unzip -t AimLocal-0.1.0-windows-x64.zip
```

`tools/test.sh` conserve le code de sortie via `pipefail`, impose un timeout et refuse les lignes `ERROR`/`SCRIPT ERROR`, même si Godot quitte à zéro. La suite a également un watchdog de 90 s. Le contrôle de capture est explicitement non exécuté en headless : `MOUSE_MODE_VISIBLE` reste imposé par ce backend.

## Couverture automatisée

- Counts cumulés et angles, `screen_relative` différent de `relative`, aucun facteur FPS, pitch borné, yaw sur de nombreux tours, inversion Y.
- Menu/test/exercice, Échap et focus, refus de reprise sans focus, compte à rebours suspendable, pression vs relâchement, reset, fin unique et abandon conservé.
- Conversions DPI/cm360/degrés/yaw aller-retour, CS2/Valorant, FOV vertical/horizontal, valeurs négatives/nulles/non finies et profils mal typés.
- Les 16 définitions et cinq graines chacune ; 100 touches/respawns par graine dans chaque scénario de clic/switching ; grille effective, limites de FOV, rayon tangent intérieur/extérieur, cible derrière.
- Tracking des six trajectoires avec le **même replay de poses horodatées** à 60/144/240 FPS : temps exposé, ratio, erreur moyenne/p95 et réacquisition identiques. Expiration des pop-ups indépendante des frames.
- Scores zéro/N/A, cohérence tirs/touches/ratés, pénalité du spam, absence de plafond artificiel chez un joueur rapide, horloge de pause, tampon borné et saturation invalidante.
- Plan 15+45, graines appariées, trois répétitions par cellule et toutes les positions contrebalancées ; rejet de changements DPI/inversion, corruption, inactivité et freeze.
- Exclusion des familiarisations, avantage net, égalités/plage, forte dispersion, données manquantes ou sans signal, mauvais confort, bord de plage et pondérations.
- Sauvegarde atomique/backup, précision JSON complète, immutabilité et revue de bilan idempotente, reprise partielle/complète, refus de traversal de chemin, préservation de fichiers corrompus, CSV/JSON.
- Panne simulée de checkpoint : aucun passage perdu en mémoire, index annulé, réessai avançant exactement une fois ; reprise UI après interruption, bilan complet, application du conseil au profil et convertisseur immédiatement actualisé.
- Contextes séparés par DPI/cm/FOV/FPS/input/inversion/durée ; tendance sur deux groupes non chevauchants, échauffements/abandons/invalides exclus.

Les données de calibration fabriquées pour les tests servent à vérifier l'algorithme, jamais à remplir un profil utilisateur. Elles ne constituent pas une étude de validation des poids ni du seuil de dispersion.

## Réception Windows obligatoire

Sur Windows 10/11 x86-64, extraire le ZIP dans un dossier utilisateur vierge, sans Godot :

1. Démarrer hors ligne ; tester les six destinations, Tab/Entrée, Quitter, fenêtres 800×450 et 1280×720. Vérifier que le résultat long défile correctement.
2. Déclarer les DPI réels. Dans Test souris, mesurer le déplacement horizontal pour 360° avec une règle, plusieurs essais gauche/droite ; comparer la distance et les counts, pas seulement l'impression visuelle.
3. Refaire aux scalings Windows 100/125/150 %, aux tailles de fenêtre, aux FPS 60/144/240, DPI 400/800/1600 ; le cm/360 doit rester constant si les DPI et le profil sont cohérents.
4. Tester les deux modes d'accumulation à 1/2/4/8 kHz, avec matériel identique et mesure externe de frametime/latence. Les événements du HUD ne certifient pas le taux HID. Consigner machine, version Windows, fréquence écran, souris, driver et résultats.
5. Échap/Alt+Tab pendant compte à rebours et exercice : horloge arrêtée, curseur libre, caméra ignorante des mouvements hors focus, retour sans reprise ni saut parasite. Aucun tir en pause ou après fin.
6. Exercer chacun des 16 scénarios : cibles turquoise, viseur central, hitbox conforme au rayon visible, expiration réelle des pop-ups, aucune sphère hors de l’arène par défaut, grille réelle, suivi continu et croisement des cibles mobiles.
7. Faire une calibration entière en conditions stables : 15 familiarisations exclues, 45 passages mesurés, repos/confort, A/B/C, bilan détaillé et refus d'appliquer si indiscernable/insuffisant. Fermer après quelques passages puis reprendre sans modifier les conditions.
8. Revoir le bilan après redémarrage ; appliquer explicitement et vérifier le profil. Affiner uniquement si utile, puis refaire à un autre jour. Comparer stabilité de la plage et confort, pas une seule meilleure valeur.
9. Reporter manuellement CS2/Valorant aux DPI déclarés, sans accélération et avec yaw connu. Mesurer un vrai 360° dans le jeu ; documenter les écarts et limites ADS/FOV.
10. Vérifier fichiers sous `%APPDATA%\AIM_LOCAL\aim_local`, dix séances identiques et tendance, puis changer sensibilité/durée : autre contexte. Exporter et relire CSV/JSON dans un tableur.
11. Sauvegarder les données hors de l'application, simuler disque plein/fichier en lecture seule/JSON corrompu. L'erreur doit rester visible ; l'original ne doit pas être supprimé. Restaurer manuellement une copie `.bak` valide après avoir archivé le fichier fautif, application fermée. Tester arrêt brutal et persistance native Windows.

À ce jour, aucun de ces essais matériels/natifs n'est annoncé comme exécuté. `--main-pack` ouvre les ressources avec le binaire Linux et un harness externe ; il ne lance pas le template PE Windows. Le script PowerShell de build reste également à essayer sur Windows.
