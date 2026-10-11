# Validation de la V1 0.1.0

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

1. Démarrer hors ligne ; tester les quatre onglets, Tab/Entrée, Quitter, fenêtres 800×450 et 1280×720. Vérifier que le résultat long défile correctement.
2. Déclarer les DPI réels. Dans Test souris, mesurer le déplacement horizontal pour 360° avec une règle, plusieurs essais gauche/droite ; comparer la distance et les counts, pas seulement l'impression visuelle.
3. Refaire aux scalings Windows 100/125/150 %, aux tailles de fenêtre, aux FPS 60/144/240, DPI 400/800/1600 ; le cm/360 doit rester constant si les DPI et le profil sont cohérents.
4. Tester les deux modes d'accumulation à 1/2/4/8 kHz, avec matériel identique et mesure externe de frametime/latence. Les événements du HUD ne certifient pas le taux HID. Consigner machine, version Windows, fréquence écran, souris, driver et résultats.
5. Échap/Alt+Tab pendant compte à rebours et exercice : horloge arrêtée, curseur libre, caméra ignorante des mouvements hors focus, retour sans reprise ni saut parasite. Aucun tir en pause ou après fin.
6. Exercer chacun des 16 scénarios : silhouettes orange, viseur central, hitbox conforme au rayon visible, expiration réelle des pop-ups, aucune sphère hors de l'arène par défaut, grille réelle, suivi continu et croisement des cibles mobiles.
7. Faire une calibration entière en conditions stables : 15 familiarisations exclues, 45 passages mesurés, repos/confort, A/B/C, bilan détaillé et refus d'appliquer si indiscernable/insuffisant. Fermer après quelques passages puis reprendre sans modifier les conditions.
8. Revoir le bilan après redémarrage ; appliquer explicitement et vérifier le profil. Affiner uniquement si utile, puis refaire à un autre jour. Comparer stabilité de la plage et confort, pas une seule meilleure valeur.
9. Reporter manuellement CS2/Valorant aux DPI déclarés, sans accélération et avec yaw connu. Mesurer un vrai 360° dans le jeu ; documenter les écarts et limites ADS/FOV.
10. Vérifier fichiers sous `%APPDATA%\AIM_LOCAL\aim_local`, dix séances identiques et tendance, puis changer sensibilité/durée : autre contexte. Exporter et relire CSV/JSON dans un tableur.
11. Sauvegarder les données hors de l'application, simuler disque plein/fichier en lecture seule/JSON corrompu. L'erreur doit rester visible ; l'original ne doit pas être supprimé. Restaurer manuellement une copie `.bak` valide après avoir archivé le fichier fautif, application fermée. Tester arrêt brutal et persistance native Windows.

À ce jour, aucun de ces essais matériels/natifs n'est annoncé comme exécuté. `--main-pack` ouvre les ressources avec le binaire Linux et un harness externe ; il ne lance pas le template PE Windows. Le script PowerShell de build reste également à essayer sur Windows.
