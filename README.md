# AIM/LOCAL

Aim trainer 3D hors ligne pour Windows, en **Godot 4.7.2 stable + GDScript**.

La **V1 0.1.0** ajoute 16 exercices, un parcours de calibration, les conversions de sensibilité et la progression locale. La [spécification originale](docs/SPECIFICATION.md) reste la cible complète ; cette V1 n'implémente pas encore ses 55 exercices, le déplacement du joueur, l'ADS ou les routines personnalisées.

Priorités : fidélité des mouvements de souris, pertinence des exercices, mesure réelle de la progression.

## Ouvrir sous Windows

Télécharger [AimLocal-0.1.0-windows-x64.zip](https://github.com/sarbhakan/aimtrainer/raw/refs/heads/main/downloads/AimLocal-0.1.0-windows-x64.zip), puis extraire **tout** le dossier et lancer `AimLocal.exe`. Le paquet est conservé dans `downloads/` pour permettre un essai immédiat ; sa [somme SHA-256](downloads/AimLocal-0.1.0-windows-x64.zip.sha256) permet d'en vérifier l'intégrité. Sous PowerShell : `Get-FileHash .\AimLocal-0.1.0-windows-x64.zip -Algorithm SHA256`.

Avec le ZIP distribué, extraire tout le contenu puis ouvrir `AimLocal.exe` : **aucune installation de Godot n'est nécessaire**.

Pour ouvrir les sources, installer l'édition standard de Godot **4.7.2 stable** et ses export templates de la même version depuis les [releases officielles](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable). Importer `project.godot`, puis lancer le projet avec F6 depuis `Main.tscn`, ou F5.

- **Calibration** : renseigner les DPI déjà configurés sur la souris, la distance de départ en `cm/360°` et l'objectif. 35 cm/360° est un départ, pas une sensibilité idéale présumée.
- Le parcours compare trois réglages sur **micro-précision, grands flicks, switching, suivi fluide et strafes** : 15 familiarisations non notées puis 45 passages mesurés, ordre alterné, graines communes et confort déclaré. Prévoir environ **16 minutes minimum** ; l'interruption est reprenable.
- Le bilan explique les scores et la dispersion. Un avantage net autorise une application explicite ; une égalité propose une plage, un manque de données ou un mauvais confort interdit l'application. On peut revoir le bilan ou affiner la plage.
- **Exercices** : 16 scénarios de 15/30/60 secondes actives, avec métriques, tirs analytiques et difficulté fixe.
- **Convertir** : CS2, Valorant ou coefficient yaw manuel ; valeurs à saisir dans le jeu, sans modification de fichiers ni interaction avec ses processus.
- **Progression** : historique comparable, record, médiane récente, tendance après 10 séances et export CSV/JSON.
- **Test souris** : repère 3D sans score. **Échap** et perte de focus suspendent le jeu et libèrent le pointeur ; la reprise reste explicite.

Défaut : **800 DPI, 35 cm/360°, FOV vertical 75°**, soit `914,4 / (800 × 35)` degré par count. Aucun lissage, accélération ni facteur de delta temporel n'est ajouté à la souris. Les DPI ne sont pas détectés matériellement. La calibration conseille un réglage dans la plage testée, **pas un optimum universel garanti** : relire le [protocole et les formules](docs/CALIBRATION.md), retester un autre jour et mesurer la distance réelle à la règle.

Les données sont dans `user://aim_local`, soit **`%APPDATA%\AIM_LOCAL\aim_local` sous Windows**. Séances et bilans sont immuables ; profil et checkpoint utilisent un remplacement atomique avec backup. Un fichier corrompu est conservé et signalé, jamais écrasé silencieusement.

## Développer dans le cloud Linux

Depuis `/workspace/aimtrainer` :

```bash
bash tools/setup_godot.sh
bash tools/godot.sh --headless --editor --import
bash tools/test.sh
bash tools/godot.sh --headless --quit-after 10
```

L'installation vérifie les SHA-512 officiels et conserve Godot, les archives et les templates Windows/Linux x86-64 dans `/workspace/.aim-local-tools`, hors du dépôt. Les téléchargements vérifiés sont réutilisables hors ligne. `AIM_LOCAL_TOOLS_DIR` permet de choisir un autre emplacement ; `GODOT_BIN` peut sélectionner un binaire existant de la version requise.

La commande `godot` globale du cloud reste indépendante : utiliser le wrapper du projet pour obtenir la version épinglée. Avec un environnement graphique, `bash tools/godot.sh --editor` ouvre l'éditeur et `bash tools/godot.sh` lance l'application. Le mode headless ne simule pas une souris physique ni sa capture.

## Exporter pour Windows

Cloud Linux, avec `curl`, `unzip`, `sha512sum` et Python 3 disponibles :

```bash
bash tools/export_windows.sh
```

Ce script importe, exécute les tests, exporte en release, ouvre le pack avec le moteur Linux dans un dossier isolé, vérifie le format PE x86-64 et le PCK embarqué, puis crée :

- `dist/AimLocal.exe`
- `dist/AimLocal-0.1.0-windows-x64.zip`, avec l'exécutable, les instructions et les notices Godot/tiers.
- `dist/AimLocal-0.1.0-windows-x64.zip.sha256`

Sous Windows, depuis PowerShell :

```powershell
.\tools\export_windows.ps1 -Godot "C:\Dev\Godot\Godot_v4.7.2-stable_win64_console.exe"
```

Le script PowerShell produit l'EXE, sans nécessiter Python. Avec Python 3, `python tools/package_windows.py` crée ensuite le ZIP. Une fois les templates installés, l'export et l'application fonctionnent hors ligne. Le preset désactive la signature et l'édition des ressources Windows : aucun outil `rcedit` n'est requis pour l'export depuis Linux.

`dist/` et `.godot/` sont ignorés par Git. Ne pas distribuer seulement le projet source : extraire tout le ZIP, puis démarrer `AimLocal.exe` sur Windows sans Godot installé.

## Validation et performances

Les tests couvrent souris et focus, conversions, catalogue, collisions, scoring, replay tracking à 60/144/240 FPS, recommandation, reprise, sauvegardes et progression. `tools/test.sh` refuse aussi les erreurs de script malgré un code Godot nul. Le pack exporté est ouvert hors du checkout et les 16 exercices sont exercés avec leurs ressources embarquées.

Le moteur utilise six sphères réutilisables, un tampon d'input préalloué et une intégration tracking à 240 Hz indépendante du rendu. Benchmark logiciel reproductible : `bash tools/godot.sh --headless --script res://tests/benchmark.gd`. Il ne mesure **ni polling matériel, ni latence, ni FPS Windows**.

Voir le [plan de tests](docs/TEST_PLAN.md), les [décisions](docs/DECISIONS.md) et l'[architecture](docs/ARCHITECTURE.md). Les essais natifs Windows, le scaling, le `cm/360` physique et les souris 2–8 kHz restent obligatoires avant de revendiquer une fidélité matérielle validée.
