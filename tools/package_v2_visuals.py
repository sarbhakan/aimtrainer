#!/usr/bin/env python3

import argparse
import hashlib
import html
import io
import json
import math
from pathlib import Path
import struct
import zipfile
import zlib

try:
    from PIL import Image as PngImage
except ImportError:
    PngImage = None


PROJECT_ROOT = Path(__file__).resolve().parents[1]
APP_VERSION = "1.0.0"
PROGRAM_IDS = {f"EX{index:02}" for index in range(1, 9)}
DIFFICULTIES = {"novice", "standard", "advanced"}
CAL_STATUSES = {
    "repeated_improvement", "repeated_regression", "mixed_tradeoff", "close_observed",
    "undetermined", "incomplete", "unstable_conditions", "exploratory_only",
}
DIMENSIONS = {(800, 450), (1280, 720), (1920, 1080)}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(contents):
    return hashlib.sha256(contents).hexdigest()


def read_json(path):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f"Clé JSON répétée : {key}")
            result[key] = value
        return result

    def reject_constant(value):
        raise ValueError(f"Nombre JSON non fini : {value}")

    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object,
                      parse_constant=reject_constant)


def canonical_encode(value):
    if value is None:
        return b"Z"
    if isinstance(value, bool):
        return b"T" if value else b"F"
    if isinstance(value, (int, float)):
        require(math.isfinite(value), "Nombre canonique non fini")
        if isinstance(value, int):
            require(abs(value) <= 9007199254740991, "Entier canonique hors précision")
        return b"N" + struct.pack(">d", 0.0 if value == 0 else float(value))
    if isinstance(value, str):
        encoded = value.encode("utf-8", errors="strict")
        return b"S" + struct.pack(">I", len(encoded)) + encoded
    if isinstance(value, list):
        return b"A" + struct.pack(">I", len(value)) + b"".join(canonical_encode(item) for item in value)
    if isinstance(value, dict):
        require(all(isinstance(key, str) for key in value), "Clé canonique non textuelle")
        keys = sorted(value, key=lambda key: key.encode("utf-8"))
        return b"O" + struct.pack(">I", len(keys)) + b"".join(
            canonical_encode(key) + canonical_encode(value[key]) for key in keys)
    raise ValueError(f"Type canonique non reconnu : {type(value).__name__}")


def semantic_sha256(value):
    return sha256(b"AIM-CANON-1\0" + canonical_encode(value))


def paeth(left, above, upper_left):
    prediction = left + above - upper_left
    distances = (abs(prediction - left), abs(prediction - above), abs(prediction - upper_left))
    if distances[0] <= distances[1] and distances[0] <= distances[2]:
        return left
    return above if distances[1] <= distances[2] else upper_left


def decode_png(contents, include_pixels=True):
    require(contents.startswith(b"\x89PNG\r\n\x1a\n"), "Signature PNG invalide")
    offset = 8
    dimensions = None
    channels = None
    compressed = bytearray()
    completed = False
    while offset + 12 <= len(contents):
        length = struct.unpack_from(">I", contents, offset)[0]
        chunk_type = contents[offset + 4:offset + 8]
        end = offset + 12 + length
        require(end <= len(contents), "Chunk PNG tronqué")
        data = contents[offset + 8:offset + 8 + length]
        checksum = struct.unpack_from(">I", contents, offset + 8 + length)[0]
        require(zlib.crc32(chunk_type + data) & 0xffffffff == checksum, "CRC PNG invalide")
        if chunk_type == b"IHDR":
            require(dimensions is None and length == 13, "En-tête PNG invalide")
            width, height, depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", data)
            require((width, height) in DIMENSIONS, "Dimensions PNG hors contrat V2")
            require(depth == 8 and color_type in (2, 6) and compression == filtering == interlace == 0,
                    "Le rendu doit être exporté en RGB/RGBA 8 bits sans entrelacement")
            dimensions = (width, height)
            channels = 4 if color_type == 6 else 3
        elif chunk_type == b"IDAT":
            compressed.extend(data)
        elif chunk_type == b"IEND":
            require(length == 0 and end == len(contents), "Fin PNG invalide")
            completed = True
            break
        offset = end
    require(completed and dimensions is not None and compressed, "PNG incomplet")
    width, height = dimensions
    stride = width * channels
    raw = zlib.decompress(compressed)
    require(len(raw) == (stride + 1) * height, "Données PNG de taille incohérente")
    if not include_pixels:
        return dimensions, channels, bytearray()
    if PngImage is not None:
        with PngImage.open(io.BytesIO(contents)) as decoded:
            decoded.load()
            require(decoded.size == dimensions and decoded.mode == ("RGBA" if channels == 4 else "RGB"), "Décodage PNG incohérent")
            return dimensions, channels, decoded.tobytes()
    pixels = bytearray(stride * height)
    for row_index in range(height):
        raw_offset = row_index * (stride + 1)
        filter_type = raw[raw_offset]
        require(filter_type in range(5), "Filtre PNG inconnu")
        row_offset = row_index * stride
        if filter_type == 0:
            pixels[row_offset:row_offset + stride] = raw[raw_offset + 1:raw_offset + 1 + stride]
            continue
        for column in range(stride):
            left = pixels[row_offset + column - channels] if column >= channels else 0
            above = pixels[row_offset + column - stride] if row_index else 0
            upper_left = pixels[row_offset + column - stride - channels] if row_index and column >= channels else 0
            prediction = (0, left, above, (left + above) // 2, paeth(left, above, upper_left))[filter_type]
            pixels[row_offset + column] = (raw[raw_offset + 1 + column] + prediction) & 255
    return dimensions, channels, pixels


def contained_path(root, relative):
    require(isinstance(relative, str) and relative and not Path(relative).is_absolute(), "Chemin relatif obligatoire")
    resolved = (root / relative).resolve()
    require(resolved.is_relative_to(root.resolve()), "Chemin hors dossier de captures")
    return resolved


def validate_gallery(capture_root, current_marker="CURRENT", expected_run_directory=None):
    current_path = capture_root / current_marker
    current = read_json(current_path)
    require(current.get("schema_version") == "aimlocal.visuals.current.v2.0" and current.get("app_version") == APP_VERSION,
            "CURRENT doit provenir du runner V2 1.0.0 ; la galerie 0.9 reste historique")
    manifest_path = contained_path(capture_root, current.get("manifest"))
    if expected_run_directory is not None:
        require(manifest_path.parent == expected_run_directory.resolve(), "Le marqueur temporaire doit désigner le run natif qui vient de finir")
    manifest_bytes = manifest_path.read_bytes()
    require(sha256(manifest_bytes) == current.get("manifest_sha256"), "Empreinte du manifeste CURRENT incorrecte")
    manifest = read_json(manifest_path)
    require(manifest.get("schema_version") == "aimlocal.visuals.manifest.v2.0" and manifest.get("app_version") == APP_VERSION,
            "Manifeste V2 1.0.0 obligatoire")
    require(manifest.get("run_id") == current.get("run_id"), "CURRENT et manifeste désignent des runs différents")
    require(manifest.get("draft") is False, "Une capture draft ne peut pas devenir la galerie CURRENT")
    require(manifest.get("project_config_app_version") == APP_VERSION, "La version réellement déclarée dans project.godot doit être 1.0.0")
    require(manifest.get("scene") == "scenes/app/MainV2.tscn" and manifest.get("artifact_origin") == "native_source_scene_not_exported_binary",
            "Les captures doivent provenir de la scène native MainV2")
    require(manifest.get("failures") == 0 and manifest.get("assertions", 0) > 0, "La recette visuelle contient un échec ou aucun contrôle")
    require(manifest.get("store_isolated") is True and manifest.get("measured_player_data") is False,
            "Le manifeste doit identifier le profil QA isolé et l’absence de mesures utilisateur")
    require(manifest.get("display_server") != "headless" and manifest.get("rendering_driver") and manifest.get("video_adapter"),
            "Métadonnées du renderer natif manquantes")
    require(manifest.get("body_color_srgb_hex") == "42d9cb" and manifest.get("projection_tolerance_px") == 0.5,
            "Le contrat de couleur ou de projection diffère de V2")
    catalogue_path = PROJECT_ROOT / "content/v2/catalogue.v2.json"
    protocol_path = PROJECT_ROOT / "content/v2/calibration_v2_protocol.json"
    catalogue = read_json(catalogue_path)
    protocol = read_json(protocol_path)
    require(sha256(catalogue_path.read_bytes()) == manifest.get("catalogue_file_sha256"), "Le catalogue a changé depuis les captures")
    require(sha256(protocol_path.read_bytes()) == manifest.get("protocol_file_sha256"), "Le protocole a changé depuis les captures")
    require(semantic_sha256(catalogue) == manifest.get("catalogue_semantic_sha256"), "Empreinte sémantique du catalogue incorrecte")
    require(semantic_sha256(protocol) == manifest.get("protocol_sha256") and protocol.get("protocol_id") == manifest.get("protocol_id"),
            "Empreinte sémantique ou identité du protocole incorrecte")
    require(catalogue.get("catalogue_revision") == manifest.get("catalogue_revision") == current.get("catalogue_revision"),
            "Révision de catalogue incohérente")
    expected_definitions = {f'{definition["program_id"]}/{definition["difficulty"]}': semantic_sha256(definition)
                            for definition in catalogue["programs"]}
    require(len(expected_definitions) == 24 and manifest.get("definition_sha256") == expected_definitions,
            "Les 24 empreintes de définition doivent correspondre aux ressources actuelles")
    source_hashes = manifest.get("source_sha256", {})
    require(isinstance(source_hashes, dict) and "scripts/v2/v2_arena.gd" in source_hashes and "scenes/app/MainV2.tscn" in source_hashes,
            "Provenance des sources de la scène absente")
    for source, expected_hash in source_hashes.items():
        source_path = contained_path(PROJECT_ROOT, source)
        require(sha256(source_path.read_bytes()) == expected_hash, f"Source modifiée après capture : {source}")
    fixtures_path = PROJECT_ROOT / "docs/reference/v2/donnees/calibration_v2_comparison_examples.json"
    fixtures = read_json(fixtures_path)["fixtures"]
    fixtures_hash = sha256(fixtures_path.read_bytes())
    require(fixtures_hash == manifest.get("fixture_source_sha256"), "Le kit de fixtures CAL a changé")
    captures = manifest.get("captures", [])
    require(isinstance(captures, list) and 0 < len(captures) <= 100 and len(captures) == current.get("capture_count"),
            "Liste de captures CURRENT incohérente")
    seen_files = set()
    seen_programs = set()
    seen_phases = set()
    seen_pages = set()
    seen_previews = set()
    seen_calibration = set()
    for capture in captures:
        filename = capture.get("file")
        require(isinstance(filename, str) and Path(filename).name == filename and filename.startswith("v2_") and filename.endswith(".png"),
                "Nom de capture hors contrat V2")
        require(filename not in seen_files and capture.get("scene") == "scenes/app/MainV2.tscn", "Capture répétée ou scène incohérente")
        seen_files.add(filename)
        path = contained_path(manifest_path.parent, filename)
        contents = path.read_bytes()
        require(sha256(contents) == capture.get("sha256") and len(contents) == capture.get("byte_count"), f"Capture modifiée : {filename}")
        dimensions, channels, pixels = decode_png(contents, capture.get("kind") == "practice")
        require(list(dimensions) == capture.get("dimensions_px"), f"Dimensions incohérentes : {filename}")
        kind = capture.get("kind")
        if kind == "practice":
            identity = (capture.get("program_id"), capture.get("difficulty"))
            require(identity[0] in PROGRAM_IDS and identity[1] in DIFFICULTIES, "Programme ou niveau non V2")
            seen_programs.add(identity)
            if identity[1] == "standard":
                seen_phases.add((identity[0], capture.get("phase_id")))
            require(capture.get("definition_sha256") == expected_definitions["/".join(identity)], "Définition de capture incohérente")
            require(capture.get("data_origin") == "native_engine_no_input_frozen_clock" and capture.get("snapshot"),
                    "Origine du snapshot de pratique manquante")
            require(capture.get("frame_post_draw_observed") is True and
                    capture.get("prepared_receipt", {}).get("ack_source") == "RenderingServer.frame_post_draw_not_physical_scanout",
                    "La capture doit conserver le reçu de préparation réellement observé après dessin")
            projection_checks = capture.get("projection_checks", [])
            require(projection_checks and all(row.get("maximum_contour_error_px", math.inf) <= 0.5 and row.get("center_error_px", math.inf) <= 0.5 for row in projection_checks),
                    f"Projection hors tolérance : {filename}")
            color_checks = capture.get("body_color_checks", [])
            require(color_checks, f"Couleur de corps non contrôlée : {filename}")
            width = dimensions[0]
            for color_check in color_checks:
                coordinates = color_check.get("matching_pixels_px", [])
                require(color_check.get("expected_srgb_hex") == "42d9cb" and coordinates, "Aucun pixel intérieur conforme")
                for coordinate in coordinates:
                    column, row_index = coordinate
                    require(0 <= column < dimensions[0] and 0 <= row_index < dimensions[1], "Pixel intérieur hors image")
                    pixel_offset = (row_index * width + column) * channels
                    require(pixels[pixel_offset:pixel_offset + 3].hex() == "42d9cb", f"Pixel exporté hors sRGB exact : {filename}")
        elif kind == "menu":
            seen_pages.add((capture.get("page"), dimensions))
        elif kind == "preview":
            require(capture.get("clip_contents") is True and capture.get("data_origin") == "unmeasured_native_engine_preview" and capture.get("snapshot"),
                    "Aperçu sans moteur réel, clipping ou provenance")
            seen_previews.add(dimensions)
        elif kind == "calibration_fixture":
            fixture_name = capture.get("fixture_name")
            require(capture.get("synthetic") is True and capture.get("data_origin") == "synthetic_illustration_not_measured_player_data",
                    "Les résultats CAL synthétiques doivent être explicitement marqués")
            require(fixture_name in fixtures and capture.get("fixture_source_sha256") == fixtures_hash and
                    capture.get("fixture_semantic_sha256") == semantic_sha256(fixtures[fixture_name]), "Fixture CAL non traçable au kit")
            require(capture.get("display_state", {}).get("can_apply") is False, "Une fixture ne doit pas proposer une application réelle")
            seen_calibration.add(capture.get("status"))
    require(seen_programs == {(program_id, difficulty) for program_id in PROGRAM_IDS for difficulty in DIFFICULTIES},
            "Les huit programmes et les trois niveaux doivent être rendus")
    expected_phases = {(definition["program_id"], phase["id"]) for definition in catalogue["programs"]
                       if definition["difficulty"] == "standard" for phase in definition["phases"]}
    require(seen_phases == expected_phases, "Toutes les phases Standard doivent être capturées")
    require({(page, dimensions) for page in ("home", "preparation", "settings", "history", "calibration") for dimensions in DIMENSIONS}.issubset(seen_pages),
            "Les menus doivent être capturés aux trois dimensions")
    require(seen_previews == DIMENSIONS and seen_calibration == CAL_STATUSES, "Aperçus ou huit états CAL incomplets")
    return current, manifest, manifest_path


def gallery_html(manifest):
    tiles = []
    for capture in manifest["captures"]:
        filename = capture["file"]
        provenance = "FIXTURE CAL SYNTHÉTIQUE" if capture.get("synthetic") else capture["data_origin"]
        label = f'{capture["kind"]} · {capture.get("program_id", capture.get("page", capture.get("status", "")))}'
        tiles.append(f'<figure><a href="captures/{html.escape(filename, quote=True)}"><img loading="lazy" src="captures/{html.escape(filename, quote=True)}" alt="{html.escape(label, quote=True)}"></a><figcaption>{html.escape(label)}<br>{html.escape(provenance)}<br>{html.escape(filename)}</figcaption></figure>')
    renderer = html.escape(f'{manifest["rendering_driver"]} · {manifest["video_adapter"]}')
    return ('<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
            '<title>AIM/LOCAL V2 — preuves visuelles 1.0.0</title><style>body{background:#0b1119;color:#f2f6fa;font:16px sans-serif;margin:24px}'
            'main{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:24px}figure{margin:0;background:#121d29;padding:12px}'
            'img{width:100%;height:auto}figcaption{overflow-wrap:anywhere;line-height:1.6}a{color:#42d9cb}</style>'
            f'<h1>AIM/LOCAL V2 · 1.0.0</h1><p>{len(manifest["captures"])} captures de MainV2 · {renderer}</p>'
            '<p>Profil QA isolé. Aucune performance utilisateur. CAL utilise les fixtures synthétiques du kit. '
            'Ces images montrent la scène native source ; elles ne prouvent pas un lancement Windows du binaire exporté.</p>'
            '<p><a href="manifest.json">Manifeste et contrôles</a> · <a href="SHA256SUMS">SHA-256 des fichiers</a></p><main>'
            + "".join(tiles) + '</main></html>')


def write_package(current, manifest, manifest_path, destination):
    files = {f'captures/{capture["file"]}': (manifest_path.parent / capture["file"]).read_bytes()
             for capture in manifest["captures"]}
    files["manifest.json"] = manifest_path.read_bytes()
    packaged_current = dict(current, manifest="manifest.json")
    files["CURRENT"] = (json.dumps(packaged_current, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    files["gallery.html"] = gallery_html(manifest).encode("utf-8")
    files["README.txt"] = ("AIM/LOCAL V2 1.0.0 — preuves visuelles natives\n"
                           "Ouvrir gallery.html. Toutes les captures proviennent de scenes/app/MainV2.tscn.\n"
                           "Le profil QA est isolé. Les pratiques sont des snapshots du moteur sans entrée joueur.\n"
                           "Les huit décisions CAL viennent de fixtures synthétiques identifiées dans le manifeste et les images.\n"
                           "Projection analytique contre Camera3D : erreur maximale 0,5 px. Corps de cible : sRGB #42D9CB exact.\n"
                           "Ce contrôle ne mesure pas les FPS matériels, la latence physique ni la réception Windows.\n").encode("utf-8")
    for filename in ("catalogue.v2.json", "calibration_v2_protocol.json"):
        files["data/" + filename] = (PROJECT_ROOT / "content/v2" / filename).read_bytes()
    files["data/calibration_v2_comparison_examples.json"] = (PROJECT_ROOT / "docs/reference/v2/donnees/calibration_v2_comparison_examples.json").read_bytes()
    files["SHA256SUMS"] = "".join(f"{sha256(contents)}  {filename}\n" for filename, contents in sorted(files.items())).encode("ascii")
    destination.parent.mkdir(parents=True, exist_ok=True)
    pending = destination.with_name(destination.name + ".pending")
    with zipfile.ZipFile(pending, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for filename, contents in files.items():
            archive.writestr(filename, contents)
    with zipfile.ZipFile(pending) as archive:
        require(archive.testzip() is None, "Archive ZIP incohérente")
    pending.replace(destination)
    destination.with_name(destination.name + ".sha256").write_text(f"{sha256(destination.read_bytes())}  {destination.name}\n", encoding="ascii")


def main():
    parser = argparse.ArgumentParser(description="Vérifier et empaqueter uniquement les captures natives V2 actuelles.")
    parser.add_argument("--captures-dir", type=Path, default=PROJECT_ROOT / "dist/preview_v2")
    parser.add_argument("--output", type=Path, default=PROJECT_ROOT / "dist/AIM_LOCAL_V2_visuals_1.0.0.zip")
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--current-marker", choices=("CURRENT", "CURRENT.pending"), default="CURRENT")
    parser.add_argument("--expected-run-dir", type=Path)
    arguments = parser.parse_args()
    try:
        require(arguments.verify_only or arguments.current_marker == "CURRENT", "Seul le marqueur CURRENT publié peut être empaqueté")
        current, manifest, manifest_path = validate_gallery(arguments.captures_dir.resolve(), arguments.current_marker, arguments.expected_run_dir)
        if not arguments.verify_only:
            write_package(current, manifest, manifest_path, arguments.output.resolve())
        print(f'V2 VISUAL PACKAGE : {len(manifest["captures"])} captures vérifiées, 0 échecs.' +
              ("" if arguments.verify_only else f" Archive : {arguments.output.resolve()}"))
    except (ValueError, OSError, KeyError, TypeError, struct.error, zlib.error, json.JSONDecodeError) as error:
        parser.exit(1, f"V2 VISUAL PACKAGE refusé : {error}\n")


if __name__ == "__main__":
    main()
