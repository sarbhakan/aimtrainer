from hashlib import sha256
from pathlib import Path
import re
import os
from zipfile import ZIP_DEFLATED, ZipFile


project_root = Path(__file__).resolve().parent.parent
version = re.search(r'config/version="([^"]+)"', (project_root / "project.godot").read_text()).group(1)
preview_dir = Path(os.environ.get("AIM_LOCAL_SCREENSHOT_DIR", project_root / "dist" / "preview"))
captures = sorted(preview_dir.glob("*.png"))
required = {"1280-00-accueil.png", "1280-02-sensibilite.png", "1280-07-entrainement.png",
            "800-16-survol.png", "1280-25-impact.png", "1280-32-arme-vector.png"}
if not required.issubset({capture.name for capture in captures}):
    raise SystemExit("Captures manquantes : lancer bash tools/visual_smoke.sh avant le packaging.")
for capture in captures:
    if capture.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"Capture PNG invalide : {capture.name}")

archive = project_root / "dist" / f"AimLocal-{version}-visuels.zip"
with ZipFile(archive, "w", ZIP_DEFLATED) as output:
    for capture in captures:
        output.write(capture, capture.name)
    output.writestr("LIRE-MOI.txt", (
        f"AIM/LOCAL {version} — {len(captures)} captures PNG\n\n"
        "Décompresser sur Mac ou Windows, puis ouvrir les images normalement.\n"
        "Il ne s'agit pas d'une application Mac, ni d'une vidéo propriétaire.\n"
        "Rendus réels de Godot 4.7.2 / OpenGL Compatibility, Mesa logiciel.\n"
        "Navigation : 00-accueil, 01-exercices, 02-sensibilite, 03-conversion,\n"
        "04-progression, 05-reglages ; formats 800, 1280 et 1920 px.\n"
        "06-depart/decompte : préparation 3, 2, 1 ; 07-entrainement : HUD.\n"
        "16-survol/23-accueil-survol : bulles ; 24-viseur : personnalisation.\n"
        "21-tir/22-recul/25-impact : effets cosmétiques et impact du moteur.\n"
        "31-exercice-ID : les seize exercices ; 32-arme-ID : les trois modèles 3D.\n\n"
        "34-sensibilite-en-pause : modification sans mélanger les scores.\n"
        "35-pattern-D01/D02 : instantanés de tailles et mouvements variables.\n\n"
        "Les bilans, records, historiques et conseils sont des fixtures synthétiques\n"
        "isolées sous user://tests, pas les performances réelles d'un joueur.\n"
        "Les effets très brefs sont figés pour leur capture sur le rendu logiciel ;\n"
        "ceci ne mesure ni fluidité GPU, ni son, ni souris physique ou latence Windows.\n"
    ))
checksum = archive.with_name(archive.name + ".sha256")
checksum.write_text(f"{sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n", encoding="utf-8")
print(f"VISUAL PACKAGE : {len(captures)} captures, {archive}")
