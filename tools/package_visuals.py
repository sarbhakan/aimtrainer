from hashlib import sha256
from pathlib import Path
import json
import math
import os
import re
import struct
from zipfile import ZIP_DEFLATED, ZipFile
import zlib
import runpy


if 'config/version="1.0.0"' in (Path(__file__).resolve().parents[1] / "project.godot").read_text(encoding="utf-8"):
    runpy.run_path(str(Path(__file__).with_name("package_v2_visuals.py")), run_name="__main__")
    raise SystemExit(0)


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
TRACKING = {"T01", "T02", "T03", "T04", "T05", "T09", "T10"}


def finite_number(value):
    return type(value) in (int, float) and math.isfinite(value)


def validate_tracking_motion(scenario_id, motion, project_root):
    if not isinstance(motion, dict) or motion.get("model") != "bounded_tracking_rhythm_v1":
        raise ValueError(f"modèle de rythme absent : {scenario_id}")
    minimum = motion.get("tracking_speed_min_deg_s")
    maximum = motion.get("tracking_speed_max_deg_s")
    acceleration = motion.get("tracking_ramp_acceleration_deg_s2")
    lifetime_s = motion.get("lifetime_s")
    if (not all(finite_number(value) for value in (minimum, maximum, acceleration, lifetime_s))
            or not 0 < minimum < maximum <= 120 or not 0 < acceleration <= 600
            or not 8.5 <= lifetime_s <= 11.5):
        raise ValueError(f"bornes du rythme invalides : {scenario_id}")
    source = (project_root / "content" / "scenarios" / f"{scenario_id}.tres").read_text(encoding="utf-8")
    speed_match = re.search(r"^speed_deg_s\s*=\s*([0-9.]+)\s*$", source, re.MULTILINE)
    if speed_match is None:
        raise ValueError(f"vitesse nominale absente : {scenario_id}")
    nominal = float(speed_match.group(1))
    if not all(math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12) for actual, expected in (
            (minimum, nominal * 0.45), (maximum, nominal * 1.35), (acceleration, nominal * 1.35 * 4.0))):
        raise ValueError(f"déclaration de rythme différente du contrat r7 : {scenario_id}")
    if motion.get("seed") != 42 or type(motion.get("target_id")) is not int or motion["target_id"] < 1:
        raise ValueError(f"identité du rythme seedé invalide : {scenario_id}")
    times_s = motion.get("times_s")
    speeds = motion.get("speeds_deg_s")
    kinds = motion.get("kinds")
    if (not all(isinstance(values, list) for values in (times_s, speeds, kinds))
            or not 2 <= len(times_s) <= 128 or len(times_s) != len(speeds) or len(kinds) != len(times_s) - 1
            or not all(finite_number(value) for value in times_s + speeds)
            or times_s[0] != 0 or times_s[-1] < lifetime_s
            or any(value != 0 and not minimum <= abs(value) <= maximum for value in speeds)
            or speeds[0] == 0 or any(not isinstance(kind, str) for kind in kinds)
            or set(kinds) != {"hold", "accelerate", "brake", "pause", "restart"}
            or not any(value > 0 for value in speeds) or not any(value < 0 for value in speeds)):
        raise ValueError(f"chronologie du rythme absente ou incohérente : {scenario_id}")
    previous_sign = 1 if speeds[0] > 0 else -1
    for index, kind in enumerate(kinds):
        duration_s = times_s[index + 1] - times_s[index]
        before, after = speeds[index:index + 2]
        if duration_s <= 0 or 1.5 * abs(after - before) / duration_s > acceleration * (1.0 + 1e-12):
            raise ValueError(f"rampe de rythme non bornée : {scenario_id}")
        if ((kind == "hold" and (before == 0 or before != after))
                or (kind == "accelerate" and (before * after <= 0 or abs(after) <= abs(before)))
                or (kind == "brake" and (before * after < 0 or abs(after) >= abs(before)))
                or (kind == "pause" and (before != 0 or after != 0))
                or (kind == "restart" and (before != 0 or after == 0 or after * previous_sign >= 0))):
            raise ValueError(f"phase de rythme contradictoire : {scenario_id}")
        if after != 0:
            previous_sign = 1 if after > 0 else -1


def validate_current(current, version, project_root):
    if (version != "0.9.0" or not isinstance(current, dict) or current.get("app_version") != version
            or current.get("protocol_version") != 6):
        raise ValueError("la galerie CURRENT doit correspondre à AIM/LOCAL 0.9.0, protocole 6")
    revisions = current.get("scenario_revisions")
    fingerprints = current.get("scenario_fingerprints")
    lifecycle = current.get("lifecycle_fingerprints")
    motion = current.get("tracking_motion")
    if (not all(isinstance(values, dict) and set(values) == set(EXERCISES)
                for values in (revisions, fingerprints, lifecycle))
            or not isinstance(motion, dict) or set(motion) != TRACKING):
        raise ValueError("les 18 définitions et les 7 déclarations de rythme doivent être présentes")
    for scenario_id in EXERCISES:
        expected_revision = 7 if scenario_id in TRACKING else 6
        if type(revisions[scenario_id]) is not int or revisions[scenario_id] != expected_revision:
            raise ValueError(f"révision courante incorrecte : {scenario_id}")
        if any(not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None
               for value in (fingerprints[scenario_id], lifecycle[scenario_id])):
            raise ValueError(f"empreinte absente ou invalide : {scenario_id}")
        if (fingerprints[scenario_id] != lifecycle[scenario_id]) != (scenario_id in TRACKING):
            raise ValueError(f"empreinte historique r6 altérée ou suivi r7 non versionné : {scenario_id}")
        if scenario_id in TRACKING:
            validate_tracking_motion(scenario_id, motion[scenario_id], project_root)
    if len(set(fingerprints.values())) != 18 or len(set(lifecycle.values())) != 18:
        raise ValueError("les empreintes doivent identifier chacune des 18 difficultés")


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
try:
    validate_current(current, version, project_root)
except (OSError, ValueError) as error:
    raise SystemExit(f"Manifeste CURRENT invalide : {error}. Relancer la validation visuelle actuelle.") from error
capture_names = current.get("captures", [])
if (not isinstance(capture_names, list) or len(capture_names) != 177
        or any(not isinstance(name, str) or Path(name).name != name or not name.endswith(".png") for name in capture_names)
        or len(set(capture_names)) != len(capture_names)):
    raise SystemExit("La galerie CURRENT doit conserver exactement les 177 captures, sous le budget de 180 images.")
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
for state in lifecycle_states:
    scenario_id = "C03" if "-42-lifeC03-" in state["capture"] else "T10"
    if (state.get("scenario_id") != scenario_id
            or state.get("scenario_revision") != current["scenario_revisions"][scenario_id]
            or state.get("scenario_fingerprint") != current["scenario_fingerprints"][scenario_id]):
        raise SystemExit("Les états capturés doivent utiliser les empreintes et révisions publiques r6/r7 déclarées.")
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
        "Calibration progressive 0.9.0, protocole 6 : trois activités r6 et deux\n"
        "suivis r7 à rythme variable borné,\n"
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
        "Les sept suivis actuels alternent accélérations, freinages, pauses et\n"
        "reprises seedés, avec vitesse maximale bornée et rampes de cadence limitées.\n"
        "Les onze autres variantes conservent exactement leur difficulté r6.\n"
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
        "CURRENT identifie la galerie 0.9.0, ses empreintes r6/r7 et ses états\n"
        "temporels seedés. Il conserve les chronologies de rythme du moteur ;\n"
        "les images fixes ne mesurent pas les vitesses ni les accélérations.\n"
        "Les protocoles historiques 4/5 gardent leurs conditions et leurs scores.\n\n"
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
