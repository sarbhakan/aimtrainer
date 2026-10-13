# Preuves de réception — AIM/LOCAL 1.0.0

Cette recette des 12–13 octobre 2026 utilise **Godot 4.7.2 stable**, GDScript natif et Linux. Les sources originales du kit sont conservées dans `docs/reference/v2` ; leur import vérifie 81 SHA-256, 24 configurations et 54 phases. Les journaux ci-dessous sont des sorties de commandes réelles, pas les rapports de réussite fournis par le kit.

## Logiciel

- [`export.txt`](export.txt) : recette complète `bash tools/export_windows.sh`, avec import, **26 runners GDScript**, **94 tests Python**, export release et ouverture isolée du PCK. Les suites terminent sans échec ; le contrôleur CAL final compte **15 103 assertions**. Le premier smoke historique comporte un avertissement audio, conservé dans ce log et diagnostiqué ci-dessous, pas présenté comme une validation sans avertissement.
- [`pack-checks.txt`](pack-checks.txt) : contrôle final du même binaire après correction du fixture de réception : **trois smokes historiques complets**, puis **94 assertions V2, zéro échec, zéro erreur et aucune fuite signalée**. Le script d’export refuse désormais aussi les avertissements de fuite, même avec exit code nul.
- [`app-xorg.txt`](app-xorg.txt) : vrai MainV2 avec Xorg dummy/Mesa, **282 assertions, 0 échec, 0 route d’entrée non exécutée**. Le parcours appelle les callbacks de souris/clic synthétiques ; il ne mesure aucun paquet HID.
- [`ui-rendered.txt`](ui-rendered.txt) : **246 assertions, 0 échec**, avec captures supplémentaires de l’interface à trois tailles. Le runner headless commun compte 192 assertions ; ses 54 vérifications de PNG ne sont pas exécutées sans affichage.
- [`visuals.txt`](visuals.txt), [`visuals-current.json`](visuals-current.json) : **70 captures natives, 536 assertions, 0 échec**, run `20261013T001220_d57612555b4af0d8`. Les sources, PNG, dimensions, pixels et empreintes sont revalidés par le packager. Le manifeste complet est dans la galerie téléchargée.
- [`cold-import.txt`](cold-import.txt) : reconstruction sans le dossier `.godot` existant, puis démarrage, foundations et analyse du contrôleur ; empreintes du kit inchangées.
- [`artifacts.json`](artifacts.json) : sommes de diffusion et empreintes des fichiers sources de cette recette. Les journaux ne contiennent pas de token ni de secret.

La suite CAL flow exécute **57 tâches mesurées synthétiques et 95 familiarisations natives** avec le vrai contrôleur, le runner, le moteur de tâche et le stockage. Elle vérifie les dates contrôlées, les gains réels, les attentes, les audits complets, trois tests de niveau, une journée interrompue puis son retry entier, l’express et les deux journées de confirmation. Elle obtient un candidat réellement confirmé par le protocole natif, refuse un candidat altéré, l’applique via le bouton UI, recrée le contrôleur, annule via le bouton UI puis vérifie un second redémarrage. Les nombres exacts d’assertions de chaque exécution figurent dans `export.txt`.

Le smoke historique lançait ses nombreux décomptes en temps accéléré avec le son activé. Le diagnostic verbose ([`audio-diagnosis.txt`](audio-diagnosis.txt)) identifie des `AudioStreamWAV`/`AudioStreamPlaybackWAV` encore retenus au shutdown du backend headless, de façon intermittente. Le fixture initialise désormais **son propre profil QA muet**, sans modifier le profil produit ni supprimer les validations des ressources sonores des trois armes. La fermeture attend aussi deux frames. Les trois répétitions finales sont sans avertissement ; l’écoute audio et la fermeture native Windows restent non réceptionnées. Ce changement n’est pas une preuve de correction du backend audio matériel.

Un essai CAL isolé antérieur aux deux correctifs d’export est aussi conservé dans [`cal-application.txt`](cal-application.txt) : **15 104 assertions, 0 échec**. Ce résultat n’est pas substitué à la suite finale du contrôleur courant. La recette du PCK a détecté un chargement incorrect des scripts remappés et une reprise de coroutine sur un shell détruit ; le contrôleur utilise `ResourceLoader.exists`, et le focus est désormais coalescé sur une connexion à usage unique, automatiquement supprimée avec son récepteur. Le smoke exige l’initialisation du runner CAL **par la scène publique exportée**, pas seulement la présence de son fichier.

## Références reproduites

- [`reference-catalogue.json`](reference-catalogue.json) : 47 cas négatifs et 4 positifs du validateur original.
- [`reference-motion.json`](reference-motion.json) : 2 025 700 contrôles du compilateur original.
- [`reference-calibration.txt`](reference-calibration.txt) : calculateur et scheduler de référence ; cette vérification ne prétend pas intégrer le runtime humain.
- L’Atlas original a été validé séparément : 213 115 contrôles sans échec. Son rapport livré reste byte-identique ; les validateurs qui écrivent doivent être exécutés sur une copie temporaire du kit, jamais en place dans les références suivies.

## Ce qui reste non exécuté

**Lancement Windows natif, PowerShell, souris physique 1/2/4/8 kHz, cm/360 à la règle, scaling Windows, écoute audio, GPU/scanout et pilote humain sur deux journées.** Le pack Windows est ouvert avec Godot Linux hors du checkout ; cela prouve la disponibilité des ressources, pas son lancement sous Windows. Mesa logiciel et des frametimes synthétiques ne certifient aucune performance matérielle. Les bilans de galerie et les entrées QA ne sont pas des résultats utilisateur.

La configuration cloud de démarrage V2 est enregistrée dans le brouillon d’environnement ; installation, réseau et secrets préexistants sont préservés. Cette sauvegarde ne publie pas un nouveau snapshot. Le push Git et la publication de l’environnement par le produit restent des opérations distinctes.

Les seuls écarts de whitespace signalés par le diff sont les copies byte-identiques de la licence DejaVu et le README original du kit. Ils restent intentionnellement inchangés pour préserver les empreintes fournies ; le code et la documentation rédigés pour cette intégration passent le contrôle de whitespace.
