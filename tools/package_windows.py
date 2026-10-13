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
    executable_file.seek(struct.unpack("<I", executable_file.read(4))[0])
    if executable_file.read(4) != b"PE\x00\x00" or struct.unpack("<H", executable_file.read(2))[0] != 0x8664:
        raise SystemExit("L'export doit être Windows x86-64.")
    executable_file.seek(-4, 2)
    if executable_file.read(4) != b"GDPC":
        raise SystemExit("Le pack Godot doit être embarqué.")

version_match = re.search(r'^config/version="([0-9]+\.[0-9]+\.[0-9]+)"$', (project_root / "project.godot").read_text(encoding="utf-8"), re.MULTILINE)
if version_match is None or version_match.group(1) != "1.0.0":
    raise SystemExit("Cet empaquetage exige AIM/LOCAL 1.0.0 et le catalogue V2.")
version = version_match.group(1)
archive = dist_dir / f"AimLocal-{version}-windows-x64.zip"
with ZipFile(archive, "w", compression=ZIP_DEFLATED) as package:
    package.write(executable, "AimLocal/AimLocal.exe")
    for notice in sorted((project_root / "LICENSES").glob("*.txt")):
        package.write(notice, f"AimLocal/LICENSES/{notice.name}")
    package.writestr(
        "AimLocal/README.txt",
        f"AIM/LOCAL {version} — catalogue et calibration V2\n\n"
        "Windows 10/11 x86-64. Extraire tout le ZIP, puis ouvrir AimLocal.exe.\n"
        "Application hors ligne, sans Godot, Python, Node, compte ou serveur à installer.\n"
        "Huit programmes de 60 secondes, chacun en Novice, Standard ou Avancé.\n"
        "Acquisition, multicibles, fenêtres temporelles, clic mobile, suivi fluide,\n"
        "suivi réactif, profondeur 3D et transitions avec PV persistants.\n"
        "Les phases et dénominateurs de score sont distincts ; pas de score global inventé.\n"
        "Ma sensibilité : DPI déclarés, distance cm/360°, import CS2/Valorant ou mesure manuelle.\n"
        "L'application ne change pas les DPI matériels ni les fichiers des jeux.\n"
        "La conversion conserve le tour complet ; aucune équivalence ADS n'est promise.\n"
        "CAL : express exploratoire, puis comparaison indépendante sur deux jours.\n"
        "Express : 11 min 36 s à trois réglages ; confirmation : 16 min 48 s par jour.\n"
        "Quatre tâches de 24 s, familiarisations exclues, réglage constant par bloc.\n"
        "Attendre au moins 12 h après l'express ; jours de confirmation séparés de 12 à 168 h.\n"
        "Une interruption CAL invalide l'époque entière, pas seulement une cellule.\n"
        "Le profil initial est restauré à la fin, à l'abandon et au redémarrage.\n"
        "L'application du candidat reste explicite et annulable.\n"
        "Échap : pause de pratique ou interruption de calibration. Reprise explicite après focus.\n"
        "Les rapports et profils V2 restent séparés des données historiques, conservées.\n"
        "Données Windows : %APPDATA%\\AIM_LOCAL\\aim_local\\v2\\\n"
        "Défaut : 800 DPI, 35 cm/360°, FOV horizontal 103° à 16:9.\n\n"
        "Export contrôlé dans le cloud Linux ; lancement natif Windows non réceptionné.\n"
        "Build non signé. Souris physique 2–8 kHz, affichage et confort restent à vérifier.\n"
        "Aucun réglage universellement parfait n'est démontré par cette comparaison.\n",
    )
checksum_file = dist_dir / f"{archive.name}.sha256"
checksum_file.write_text(f"{sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n", encoding="utf-8")
print(f"Windows x86-64, PCK embarqué : {executable}")
print(f"Distribution : {archive}")
print(f"SHA-256 : {checksum_file}")
