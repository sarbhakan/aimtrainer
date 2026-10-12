from hashlib import sha256
from pathlib import Path
import json
import os
import re
import struct
from zipfile import ZIP_DEFLATED, ZipFile
import zlib


LAYOUTS = {800: 450, 1280: 720, 1920: 1080}
EXERCISES = {
    "C01": "Cible unique", "C02": "Micro-précision", "C03": "Multicibles",
    "C04": "Grands mouvements", "C05": "Précision avancée", "C07": "Visée verticale",
    "D01": "Réflexes", "D02": "Cible mobile", "T01": "Suivi horizontal",
    "T02": "Suivi vertical", "T03": "Suivi diagonal", "T04": "Suivi circulaire",
    "T05": "Suivi réactif", "T09": "Suivi avancé", "S01": "De cible en cible",
    "S02": "Transitions mobiles", "M01": "Flicks mixtes", "T10": "Suivi varié",
}
WEAPONS = ("pulse", "vector", "classic")


def validate_png(capture):
    contents = capture.read_bytes()
    if contents[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("signature absente")
    offset = 8
    header = None
    image_data = bytearray()
    palette = False
    data_ended = False
    ended = False
    while offset < len(contents):
        if len(contents) - offset < 12:
            raise ValueError("chunk tronqué")
        length, chunk_type = struct.unpack_from(">I4s", contents, offset)
        end = offset + length + 12
        if end > len(contents):
            raise ValueError("chunk incomplet")
        payload = contents[offset + 8:end - 4]
        checksum = struct.unpack_from(">I", contents, end - 4)[0]
        if zlib.crc32(contents[offset + 4:end - 4]) != checksum:
            raise ValueError("CRC incorrect")
        if header is None and chunk_type != b"IHDR":
            raise ValueError("IHDR doit être le premier chunk")
        if chunk_type == b"IHDR":
            if header is not None or length != 13:
                raise ValueError("IHDR invalide")
            header = struct.unpack(">IIBBBBB", payload)
        elif chunk_type == b"PLTE":
            if image_data or palette or length == 0 or length > 768 or length % 3:
                raise ValueError("palette invalide")
            palette = True
        elif chunk_type == b"IDAT":
            if data_ended:
                raise ValueError("IDAT non consécutifs")
            image_data.extend(payload)
        elif chunk_type == b"IEND":
            if length or end != len(contents):
                raise ValueError("fin PNG invalide")
            ended = True
            break
        elif chunk_type[0] & 32 == 0:
            raise ValueError("chunk critique inconnu")
        if image_data and chunk_type != b"IDAT":
            data_ended = True
        offset = end
    if not ended or header is None or not image_data:
        raise ValueError("image incomplète")
    width, height, depth, color, compression, filtering, interlace = header
    depths = {0: (1, 2, 4, 8, 16), 2: (8, 16), 3: (1, 2, 4, 8), 4: (8, 16), 6: (8, 16)}
    if not width or not height or depth not in depths.get(color, ()) or compression or filtering or interlace not in (0, 1):
        raise ValueError("format d’image invalide")
    if color == 3 and not palette:
        raise ValueError("palette absente")
    decoder = zlib.decompressobj()
    pixels = decoder.decompress(image_data) + decoder.flush()
    if not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
        raise ValueError("flux zlib incomplet ou superflu")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
    passes = ((0, 0, 1, 1),) if not interlace else (
        (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
        (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2),
    )
    offset = 0
    for start_x, start_y, step_x, step_y in passes:
        columns = max(0, (width - start_x + step_x - 1) // step_x)
        rows = max(0, (height - start_y + step_y - 1) // step_y)
        if not columns or not rows:
            continue
        stride = (columns * channels * depth + 7) // 8 + 1
        for row_index in range(rows):
            row_offset = offset + row_index * stride
            if row_offset >= len(pixels) or pixels[row_offset] > 4:
                raise ValueError("ligne ou filtre PNG invalide")
        offset += rows * stride
    if offset != len(pixels):
        raise ValueError("taille des pixels incohérente")
    filename_width = re.match(r"(800|1280|1920)-", capture.name)
    if filename_width:
        expected_width = int(filename_width.group(1))
        if (width, height) != (expected_width, LAYOUTS[expected_width]):
            raise ValueError("dimensions différentes du format annoncé")


project_root = Path(__file__).resolve().parent.parent
version = re.search(r'config/version="([^"]+)"', (project_root / "project.godot").read_text()).group(1)
preview_dir = Path(os.environ.get("AIM_LOCAL_SCREENSHOT_DIR") or project_root / "dist" / "preview").expanduser().resolve()
current_marker = preview_dir / "CURRENT"
try:
    current = json.loads(current_marker.read_text(encoding="utf-8"))
except (OSError, ValueError) as error:
    raise SystemExit(f"Marqueur CURRENT absent ou invalide dans {preview_dir}. Relancer la validation visuelle actuelle.") from error
if (not isinstance(current, dict) or current.get("app_version") != version
        or current.get("protocol_version") != 5 or current.get("scenario_revision") != 6):
    raise SystemExit("La galerie CURRENT ne correspond pas à cette version, au protocole 5 et aux variantes r6.")
capture_names = current.get("captures", [])
if (not isinstance(capture_names, list) or not capture_names or len(capture_names) >= 180
        or any(not isinstance(name, str) or Path(name).name != name or not name.endswith(".png") for name in capture_names)
        or len(set(capture_names)) != len(capture_names)):
    raise SystemExit("La liste des captures CURRENT est invalide ou dépasse le budget de moins de 180 images.")
captures = sorted(preview_dir / name for name in capture_names)
required = {
    "1280-07-entrainement.png", "800-16-survol.png", "1280-25-impact.png",
    "1280-06-decompte-2.png", "1280-06-decompte-1.png", "1280-21-tir.png", "1280-22-recul.png",
    "1280-17-import-valorant.png", "800-17-import-valorant.png", "1280-18-conversion-valorant.png",
    "1280-19-import-cod.png", "1280-20-conversion-cod.png", "1280-34-sensibilite-en-pause.png",
    "1280-11-courbe-test.png", "800-11-tableau-exemple.png", "1280-29-record-exemple.png",
    "1280-24-viseur-cross.png", "1280-24-viseur-circle.png", "1280-24-viseur-t.png", "800-24-viseur.png",
}
for width in LAYOUTS:
    for page_index, page in enumerate(("accueil", "exercices", "sensibilite", "conversion", "progression", "reglages")):
        required.add(f"{width}-{page_index:02d}-{page}.png")
    for screen in ("15-repos", "10-bilan", "26-guide-depart", "27-guide-exercice", "28-guide-affinage",
                   "30-guide-conseil-exemple", "37-calibration-pause", "41-calibration-mesures-exemple"):
        required.add(f"{width}-{screen}.png")
    for block_index in range(1, 6):
        required.add(f"{width}-38-calibration-bloc-{block_index}-exemple.png")
for scenario_id in EXERCISES:
    required.add(f"1280-31-exercice-{scenario_id}.png")
for weapon in WEAPONS:
    required.add(f"1280-32-arme-{weapon}.png")
    for width in (800, 1280):
        required.add(f"{width}-36-inspection-{weapon}.png")
for duration_s in (45, 60):
    for width in (800, 1280):
        required.add(f"{width}-40-routine-{duration_s}-bilan-exemple.png")
        for stage_index in range(1, 4):
            for screen in ("depart", "exercice", "repos-exemple"):
                required.add(f"{width}-39-routine-{duration_s}-etape-{stage_index}-{screen}.png")
for phase in ("early", "late", "predeadline", "deadline", "hold-2s"):
    required.add(f"1280-42-lifeC03-{phase}.png")
for phase in ("early", "midlife", "predeadline", "cycle-1", "cycle-2"):
    required.add(f"1280-43-lifeT10-{phase}.png")
for width in (800, 1280):
    required.add(f"{width}-44-expirations-score-v2-exemple.png")
    required.add(f"{width}-45-calibration-protocole4-exemple.png")
missing = required - {capture.name for capture in captures}
if missing:
    raise SystemExit(f"Captures manquantes dans {preview_dir} : " + ", ".join(sorted(missing))
                     + ". Lancer bash tools/visual_smoke.sh avec le même AIM_LOCAL_SCREENSHOT_DIR.")
lifecycle_states = current.get("lifecycle_states", [])
expected_lifecycle = {name for name in required if "-42-lifeC03-" in name or "-43-lifeT10-" in name}
if (not isinstance(lifecycle_states, list) or len(lifecycle_states) != 10
        or any(not isinstance(state, dict) or state.get("active") is not True
               or state.get("shots") != 0 or state.get("input_events") != 0 for state in lifecycle_states)
        or {state.get("capture") for state in lifecycle_states} != expected_lifecycle):
    raise SystemExit("Les dix captures temporelles CURRENT doivent provenir d’exercices actifs sans input.")
for capture in captures:
    try:
        validate_png(capture)
    except (OSError, ValueError, struct.error, zlib.error) as error:
        raise SystemExit(f"Capture PNG invalide : {capture.name} ({error})") from error

archive = project_root / "dist" / f"AimLocal-{version}-visuels.zip"
archive.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(archive, "w", ZIP_DEFLATED) as output:
    for capture in captures:
        output.write(capture, capture.name)
    output.write(current_marker, "CURRENT")
    output.writestr("LIRE-MOI.txt", (
        f"AIM/LOCAL {version} — {len(captures)} captures PNG\n\n"
        "Décompresser sur Mac ou Windows, puis ouvrir les images normalement.\n"
        "Il ne s'agit pas d'une application Mac, ni d'une vidéo propriétaire.\n"
        "Rendus réels de Godot 4.7.2 / OpenGL Compatibility, Mesa logiciel.\n"
        "Navigation : 00-accueil, 01-exercices, 02-sensibilite, 03-conversion,\n"
        "04-progression, 05-reglages ; formats 800, 1280 et 1920 px.\n"
        "06-depart/decompte : préparation 3, 2, 1 ; 07-entrainement : timer et score.\n"
        "16-survol/23-accueil-survol : bulles contenues ; 24-viseur : personnalisation.\n"
        "21-tir/22-recul/25-impact : flash de tir, recul et vrai impact du moteur.\n"
        "17/19-import, 18/20-conversion : exemples d’import physique et conversion.\n"
        "34-sensibilite-en-pause : modification sans mélanger les scores.\n"
        "35-pattern-D01/D02 : instantanés de tailles et mouvements variables.\n\n"
        "Calibration progressive 0.8, protocole 5 : cinq exercices temporels r6,\n"
        "chacun avec cinq essais de\n"
        "60 secondes, soit 25 essais. Les scores guident les cinq sensibilités\n"
        "testées et resserrent la zone avant le bloc suivant. Le bilan présente\n"
        "une seule sensibilité retenue, sans promesse de sensibilité parfaite.\n"
        "26-guide-depart/27-guide-exercice/37-calibration-pause : écrans actuels.\n"
        "38-calibration-bloc-1..5-exemple : cinq colonnes de mesures synthétiques.\n"
        "15-repos et 28-guide-affinage : noms compatibles des blocs 1 et 5.\n"
        "10-bilan/30-guide-conseil-exemple : bilan progressif synthétique unique.\n"
        "41-calibration-mesures-exemple : calculs et intervalles dépliés.\n"
        "Clics et transitions : score V2, réussite = touches / (tirs + expirations).\n"
        "Les suivis conservent le score V1 et leur vrai temps sur cible.\n"
        "45-calibration-protocole4-exemple : ancien bilan 0.7, vingt-cinq essais\n"
        "V1 et définitions historiques conservés, avec mention visible.\n"
        "Les anciens noms guide sont conservés pour compatibilité des captures.\n\n"
        "31-exercice-ID : les dix-huit exercices actuels :\n"
        + "\n".join(f"  {scenario_id} — {title}" for scenario_id, title in EXERCISES.items())
        + "\n\n"
        "32-arme-ID : trois armes en gameplay ; 36-inspection-ID : trois profils\n"
        "3D nus, latéraux, orthographiques, sans mains ni manches, à 800/1280 px.\n"
        "39-routine-45/60-etape-1..3 : départ, exercice et repos pour M01 Flicks\n"
        "mixtes, T10 Suivi varié et S02 Transitions mobiles, à 45 et 60 secondes.\n"
        "40-routine-45/60-bilan-exemple : trois résultats séparés, sans total.\n\n"
        "42-lifeC03 : début, rétrécissement, juste avant la vraie échéance,\n"
        "remplacement immédiat puis plus de deux secondes sans souris ni tir.\n"
        "43-lifeT10 : début, milieu et fin de la durée seedée, puis deux cycles\n"
        "réels de réapparition, avec taille et profondeur calculées par le moteur.\n"
        "Le HUD reste actif et ses expirations et son score sont actualisés.\n"
        "44-expirations-score-v2-exemple : 36 touches, 48 tirs, 12 expirations ;\n"
        "précision brute 75 %, réussite effective V2 60 %, données synthétiques.\n"
        "CURRENT identifie cette galerie 0.8 et ses états temporels seedés.\n\n"
        "Les bilans, blocs, repos de routine, records et historiques portent une\n"
        "mention visible de données synthétiques. Le résultat 09 utilise une\n"
        "visée et une durée simulées. Aucun score n’est présenté comme une\n"
        "performance réelle d’un joueur. Les données restent sous user://tests.\n"
        "Les départs et exercices utilisent les écrans actuels ; les essais longs\n"
        "sont illustrés sans attendre 25 fois 60 secondes de jeu humain.\n"
        "Les effets brefs et certains écrans sont figés pour leur capture ; ceci\n"
        "ne mesure ni fluidité GPU, ni son, ni souris physique ou latence Windows.\n"
    ))
checksum = archive.with_name(archive.name + ".sha256")
checksum.write_text(f"{sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n", encoding="utf-8")
print(f"VISUAL PACKAGE : {len(captures)} captures, {archive}")
