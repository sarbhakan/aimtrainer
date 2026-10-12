from hashlib import sha256
from pathlib import Path
import re
import struct
from zipfile import ZIP_DEFLATED, ZipFile


project_root = Path(__file__).resolve().parents[1]
dist_dir = project_root / "dist"
executable = dist_dir / "AimLocal.exe"
with executable.open("rb") as executable_file:
    if executable_file.read(2) != b"MZ":
        raise SystemExit("L'export n'est pas un exécutable Windows.")
    executable_file.seek(0x3C)
    pe_offset = struct.unpack("<I", executable_file.read(4))[0]
    executable_file.seek(pe_offset)
    if executable_file.read(4) != b"PE\x00\x00":
        raise SystemExit("En-tête PE invalide.")
    if struct.unpack("<H", executable_file.read(2))[0] != 0x8664:
        raise SystemExit("L'export Windows doit être x86-64.")
    executable_file.seek(-4, 2)
    if executable_file.read(4) != b"GDPC":
        raise SystemExit("Le pack Godot doit être embarqué dans l'exécutable.")

version_match = re.search(r'^config/version="([0-9]+\.[0-9]+\.[0-9]+)"$', (project_root / "project.godot").read_text(encoding="utf-8"), re.MULTILINE)
if version_match is None:
    raise SystemExit("Version du projet invalide.")
version = version_match.group(1)
archive = dist_dir / f"AimLocal-{version}-windows-x64.zip"
with ZipFile(archive, "w", compression=ZIP_DEFLATED) as package:
    package.write(executable, "AimLocal/AimLocal.exe")
    for notice in sorted((project_root / "LICENSES").glob("*.txt")):
        package.write(notice, f"AimLocal/LICENSES/{notice.name}")
    package.writestr(
        "AimLocal/README.txt",
        f"AIM/LOCAL {version} - calibration et entraînement local\n\n"
        "Windows 10/11 x86-64. Extraire tout le ZIP, puis ouvrir AimLocal.exe.\n"
        "Godot n'est pas nécessaire. L'application fonctionne hors ligne.\n"
        "Accueil : choisir un exercice ou trouver sa sensibilité.\n"
        "Ma sensibilité : DPI actuels, valeur AIM/LOCAL modifiable ou import d'un jeu.\n"
        "Import : DPI et sensibilité source, sans changer les DPI actuels de la souris.\n"
        "CS2/Valorant : coefficients documentaires ; CoD/autre : titre et mesure manuelle.\n"
        "Calibration : 5 blocs, chacun 3 familiarisations puis 9 essais mesurés.\n"
        "3 réglages comparés par exercice ; 15 familiarisations et 45 mesures au total.\n"
        "Trouver mon réglage : exploration large, recentrage, affinage puis validation.\n"
        "Maximum 4 comparaisons complètes ; prévoir 51-68 minutes avec pauses/reprise.\n"
        "Comparer mon réglage : une comparaison à +/-10 %, environ 17 minutes.\n"
        "Le conseil guidé exige un consentement pour un essai provisoire.\n"
        "Départ 3, 2, 1, GO. Repos, confort et reprise sauvegardée inclus.\n"
        "La recommandation est indicative : retester un autre jour, jamais un optimum garanti.\n"
        "16 exercices autonomes, métriques, progression à contexte fixe, export CSV/JSON.\n"
        "Chaque entraînement rejoué renouvelle ses positions ; calibration à graines communes.\n"
        "D01 rétrécit ; D02 change de destination ; S02 varie les profondeurs.\n"
        "Réglages : 3 armes 3D originales avec sons. Cliquer pour un tir ; en suivi,\n"
        "maintenir le clic pour un son continu facultatif, sans effet sur le score.\n"
        "Volume, silence, arme masquée et animations réduites sont disponibles.\n"
        "Viseur : point, croix, cercle ou T ; taille, épaisseur, gap, couleur et contour.\n"
        "Hitmarker après impact ; animations cosmétiques sans recul de caméra.\n"
        "Échap : sensibilité AIM/LOCAL, Valorant ou CS2 ; appliquer redémarre l'essai.\n"
        "Réglage verrouillé pendant une comparaison de calibration.\n"
        "Progression : filtres, tableau des séances comparables et records sauvegardés.\n"
        "Enregistrer les réglages pour les conserver après fermeture.\n"
        "Conversion inverse : CS2, Valorant ou profil mesuré ; DPI destination au choix.\n"
        "Vérifier la distance physique dans le jeu ; pas d'équivalence ADS automatique.\n"
        "Les valeurs sont à saisir manuellement, aucun jeu n'est modifié.\n"
        "Échap : pause/reprise. La perte de focus suspend l'exercice.\n"
        "Au retour, reprendre explicitement ou revenir au menu.\n\n"
        "Données : %APPDATA%\\AIM_LOCAL\\aim_local\\\n"
        "Défaut : 800 DPI, 35 cm/360 degrés, FOV vertical 75 degrés.\n"
        "La fidélité matérielle et les performances à 2-8 kHz restent à mesurer.\n"
        "Build non signé. Valider le lancement et la souris sur votre PC Windows.\n",
    )

checksum_file = dist_dir / f"{archive.name}.sha256"
checksum_file.write_text(f"{sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n", encoding="utf-8")
print(f"Windows x86-64, PCK embarqué : {executable}")
print(f"Distribution : {archive}")
print(f"SHA-256 : {checksum_file}")
