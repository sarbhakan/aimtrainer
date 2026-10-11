from hashlib import sha256
from pathlib import Path
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

archive = dist_dir / "AimLocal-0.1.0-windows-x64.zip"
with ZipFile(archive, "w", compression=ZIP_DEFLATED) as package:
    package.write(executable, "AimLocal/AimLocal.exe")
    for notice in sorted((project_root / "LICENSES").glob("*.txt")):
        package.write(notice, f"AimLocal/LICENSES/{notice.name}")
    package.writestr(
        "AimLocal/README.txt",
        "AIM/LOCAL 0.1.0 - calibration et entraînement local\n\n"
        "Windows 10/11 x86-64. Extraire tout le ZIP, puis ouvrir AimLocal.exe.\n"
        "Godot n'est pas nécessaire. L'application fonctionne hors ligne.\n"
        "Indiquer les DPI de la souris, puis la distance de départ en cm/360 degrés.\n"
        "Calibration : 5 exercices, 3 réglages, 15 familiarisations puis 45 essais mesurés.\n"
        "Prévoir environ 16 minutes. Repos, confort et reprise sauvegardée inclus.\n"
        "La recommandation est indicative : retester un autre jour, jamais un optimum garanti.\n"
        "16 exercices autonomes, métriques, progression à contexte fixe, export CSV/JSON.\n"
        "Convertir : CS2, Valorant ou coefficient yaw manuel ; vérifier la distance en jeu.\n"
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
