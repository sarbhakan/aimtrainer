#!/usr/bin/env python3
"""Import the original V2 kit JSON after offline checksum and Atlas checks.

Usage: python3 tools/import_v2_atlas.py --kit docs/reference/v2 \
    --atlas docs/reference/v2/ATLAS_EXERCICES_V2.html --output-dir content/v2
Add --check to verify existing outputs without writing them.

The supplied, checksum-pinned Python validator owns catalogue schema validation.
Atlas JavaScript is never executed. Extracted definitions stay in memory and are
only compared with the original catalogue; illustrative samples are not imported.
Documentary JSON hashes use sorted UTF-8 JSON, not AIM-CANON-1.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from types import ModuleType
from typing import Any


PINNED_CHECKSUMS_SHA256 = "e76ad021da07675dbcee0621ef75c00a543e72b7f8c87e4cdabc109a8b4b4cb1"
IMPORT_PATHS = (
    "donnees/catalogue.v2.json",
    "donnees/interface.theme.json",
    "donnees/runtime.contract.json",
    "donnees/calibration_v2_protocol.json",
    "donnees/empreintes.fixtures.json",
)
SCHEMA_PATH = "schemas/catalogue.schema.json"
VALIDATOR_PATH = "outils/valider_catalogue.py"
ATLAS_PATH = "ATLAS_EXERCICES_V2.html"
ATLAS_STATES_PATH = "donnees/atlas.etats.json"
REQUIRED_REFERENCE_PATHS = (
    SCHEMA_PATH,
    VALIDATOR_PATH,
    ATLAS_PATH,
    ATLAS_STATES_PATH,
    "outils/geometrie_reference.py",
    "outils/mouvements_reference.py",
    "outils/empreintes_reference.py",
    "outils/calibration_v2_reference.py",
    "donnees/calibration_v2_plan_example.json",
    "donnees/calibration_v2_comparison_examples.json",
    "donnees/calibration_v2_plan_negative_fixtures.json",
)
MANIFEST_NAME = "atlas_source_manifest.json"
DERIVED_OUTPUT_NAMES = ("atlas_definitions.v2.json", "atlas_theme.v2.json")
DIFFICULTIES = ("novice", "standard", "advanced")
CONFIGURATION_ORDER = tuple(
    (f"EX{program_number:02d}", difficulty)
    for program_number in range(1, 9)
    for difficulty in DIFFICULTIES
)


class AtlasImportError(ValueError):
    pass


@dataclass(frozen=True)
class VerifiedKit:
    root: Path
    hashes: dict[str, str]
    files: dict[str, bytes]


@dataclass(frozen=True)
class ExtractedAtlas:
    data: dict[str, Any]
    raw_data: bytes


@dataclass(frozen=True)
class ImportBundle:
    artifacts: dict[str, bytes]
    manifest: dict[str, Any]


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise AtlasImportError(f"Duplicate JSON key: {key!r}")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise AtlasImportError(f"Non-finite JSON constant: {value}")


def _check_json_values(value: Any, path: str = "$") -> None:
    if isinstance(value, str):
        if any(0xD800 <= ord(character) <= 0xDFFF for character in value):
            raise AtlasImportError(f"{path}: unpaired Unicode surrogate")
    elif isinstance(value, float):
        if not math.isfinite(value):
            raise AtlasImportError(f"{path}: non-finite or overflowing JSON number")
    elif type(value) is int:
        if abs(value) > 2**53 - 1:
            raise AtlasImportError(f"{path}: integer outside exact JSON interchange range")
    elif isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise AtlasImportError(f"{path}: JSON object keys must be strings")
            _check_json_values(key, path)
            _check_json_values(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _check_json_values(child, f"{path}[{index}]")
    elif value is not None and not isinstance(value, bool):
        raise AtlasImportError(f"{path}: unsupported JSON value type")


def strict_loads(raw: bytes | str, source: str = "JSON") -> Any:
    try:
        decoded = raw.decode("utf-8", errors="strict") if isinstance(raw, bytes) else raw
        if decoded.startswith("\ufeff"):
            raise AtlasImportError("UTF-8 BOM is not accepted")
        result = json.loads(
            decoded, object_pairs_hook=_unique_pairs, parse_constant=_reject_constant
        )
        _check_json_values(result)
        return result
    except (ValueError, RecursionError) as error:
        raise AtlasImportError(f"{source}: {error}") from error


def serialized_json(value: Any) -> bytes:
    _check_json_values(value)
    return (json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


class AtlasDataParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self.found = False
        self.active = False
        self.complete = False
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if not any(name == "id" and value == "atlas-data" for name, value in attrs):
            return
        if tag != "script":
            raise AtlasImportError("atlas-data must belong to a script element")
        if self.found:
            raise AtlasImportError("Duplicate atlas-data script")
        names = [name for name, value in attrs]
        if len(names) != len(set(names)):
            raise AtlasImportError("Duplicate atlas-data script attribute")
        if dict(attrs) != {"id": "atlas-data", "type": "application/json"}:
            raise AtlasImportError("atlas-data script requires only id and type=application/json attributes")
        self.found = True
        self.active = True

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        if self.active:
            raise AtlasImportError("atlas-data script cannot be self-closing")

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self.active:
            self.active = False
            self.complete = True

    def handle_data(self, data: str) -> None:
        if self.active:
            self.parts.append(data)

    def raw_data(self) -> bytes:
        if not self.found:
            raise AtlasImportError("Missing atlas-data script")
        if not self.complete or self.active:
            raise AtlasImportError("Unclosed atlas-data script")
        return "".join(self.parts).encode("utf-8")


def _object_keys(value: Any, expected: set[str], path: str) -> None:
    if not isinstance(value, dict):
        raise AtlasImportError(f"{path}: expected an object")
    missing, unknown = expected - value.keys(), value.keys() - expected
    if missing or unknown:
        raise AtlasImportError(f"{path}: missing fields {sorted(missing)}; unknown fields {sorted(unknown)}")


def extract_atlas(source: bytes) -> ExtractedAtlas:
    try:
        parser = AtlasDataParser()
        parser.feed(source.decode("utf-8", errors="strict"))
        parser.close()
        raw_data = parser.raw_data()
    except (UnicodeError, RecursionError) as error:
        raise AtlasImportError(f"Atlas HTML: {error}") from error
    data = strict_loads(raw_data, "atlas-data")
    _object_keys(data, {"version", "compiler_version", "theme", "configs", "scope"}, "$atlas")
    if data["version"] != "aimlocal.atlas.v2" or data["compiler_version"] != "motion_reference_v2.0":
        raise AtlasImportError("$atlas: unsupported Atlas or compiler version")
    if not isinstance(data["theme"], dict):
        raise AtlasImportError("$atlas.theme: expected an object")
    if not isinstance(data["scope"], str) or not data["scope"].strip():
        raise AtlasImportError("$atlas.scope: expected a nonempty string")
    return ExtractedAtlas(data, raw_data)


def extract_definitions(atlas: ExtractedAtlas) -> list[dict[str, Any]]:
    configs = atlas.data["configs"]
    if not isinstance(configs, list) or len(configs) != 24:
        raise AtlasImportError("$atlas.configs: expected 24 configurations")
    definitions = []
    for index, config in enumerate(configs):
        path = f"$atlas.configs[{index}]"
        _object_keys(config, {"program_id", "difficulty", "title", "phases"}, path)
        identity = (config["program_id"], config["difficulty"])
        if identity != CONFIGURATION_ORDER[index]:
            raise AtlasImportError(f"{path}: program/level matrix or configuration order mismatch")
        if not isinstance(config["title"], str) or not config["title"].strip():
            raise AtlasImportError(f"{path}.title: expected a nonempty string")
        if not isinstance(config["phases"], list) or not config["phases"]:
            raise AtlasImportError(f"{path}.phases: expected a nonempty list")
        phases = []
        for phase_index, phase in enumerate(config["phases"]):
            phase_path = f"{path}.phases[{phase_index}]"
            _object_keys(phase, {"id", "definition", "static_positions", "opportunities", "states"}, phase_path)
            definition = phase["definition"]
            if not isinstance(definition, dict):
                raise AtlasImportError(f"{phase_path}.definition: expected an object")
            if not isinstance(phase["id"], str) or phase["id"] != definition.get("id"):
                raise AtlasImportError(f"{phase_path}.id: wrapper and definition IDs disagree")
            for name in ("static_positions", "opportunities", "states"):
                if not isinstance(phase[name], list):
                    raise AtlasImportError(f"{phase_path}.{name}: expected an illustrative list")
            phases.append(copy.deepcopy(definition))
        definitions.append({
            "program_id": config["program_id"],
            "difficulty": config["difficulty"],
            "title": config["title"],
            "phases": phases,
        })
    if sum(len(config["phases"]) for config in definitions) != 54:
        raise AtlasImportError("$atlas.configs: expected 54 phases")
    return definitions


def parse_checksums(raw: bytes) -> dict[str, str]:
    try:
        lines = raw.decode("ascii", errors="strict").splitlines()
    except UnicodeError as error:
        raise AtlasImportError(f"SHA256SUMS.txt: {error}") from error
    hashes = {}
    for index, line in enumerate(lines):
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if not match:
            raise AtlasImportError(f"SHA256SUMS.txt:{index + 1}: malformed checksum entry")
        digest, relative = match.groups()
        parts = relative.split("/")
        if (
            PurePosixPath(relative).is_absolute()
            or any(part in ("", ".", "..") for part in parts)
            or "\\" in relative
            or ":" in relative
            or any(ord(character) < 32 or ord(character) == 127 for character in relative)
            or relative == "SHA256SUMS.txt"
        ):
            raise AtlasImportError(f"SHA256SUMS.txt:{index + 1}: unsafe source path")
        if relative in hashes:
            raise AtlasImportError(f"SHA256SUMS.txt:{index + 1}: duplicate source path")
        hashes[relative] = digest
    if not hashes:
        raise AtlasImportError("SHA256SUMS.txt: empty manifest")
    return hashes


def _read_kit_file(root: Path, relative: str) -> bytes:
    candidate = root
    for part in PurePosixPath(relative).parts:
        candidate = candidate / part
        if candidate.is_symlink():
            raise AtlasImportError(f"{relative}: symlinked kit sources are not accepted")
    if not candidate.is_file():
        raise AtlasImportError(f"{relative}: required source is missing or is not a regular file")
    return candidate.read_bytes()


def verify_kit(kit_path: Path) -> VerifiedKit:
    root = kit_path.resolve()
    manifest = _read_kit_file(root, "SHA256SUMS.txt")
    if sha256(manifest) != PINNED_CHECKSUMS_SHA256:
        raise AtlasImportError("SHA256SUMS.txt: checksum manifest differs from the pinned original V2 kit")
    hashes = parse_checksums(manifest)
    required = set(IMPORT_PATHS + REQUIRED_REFERENCE_PATHS)
    if required - hashes.keys():
        raise AtlasImportError(f"Checksum manifest omits required references: {sorted(required - hashes.keys())}")
    files = {}
    for relative, expected in hashes.items():
        raw = _read_kit_file(root, relative)
        if sha256(raw) != expected:
            raise AtlasImportError(f"{relative}: kit source SHA-256 mismatch")
        if relative in required:
            files[relative] = raw
    return VerifiedKit(root, hashes, files)


def load_reference_validator(kit: VerifiedKit) -> ModuleType:
    raw = kit.files[VALIDATOR_PATH]
    if sha256(raw) != kit.hashes[VALIDATOR_PATH]:
        raise AtlasImportError("Reference validator bytes changed after kit verification")
    reference = ModuleType("aimlocal_verified_catalogue_validator")
    reference.__file__ = str(kit.root / VALIDATOR_PATH)
    exec(compile(raw, reference.__file__, "exec"), reference.__dict__)
    return reference


def _require_valid(result: dict[str, Any], source: str) -> None:
    if not result["valid"]:
        evidence = "; ".join(
            f"{error['path']} [{error['code']}]: {error['message']}"
            for error in result["errors"][:4]
        )
        raise AtlasImportError(f"{source}: {result['failed_stage']}: {evidence}")


def _require_same(actual: Any, expected: Any, path: str = "$") -> None:
    numeric = (int, float)
    if type(actual) in numeric and type(expected) in numeric:
        if actual == expected:
            return
    elif type(actual) is type(expected):
        if isinstance(actual, dict):
            if actual.keys() != expected.keys():
                raise AtlasImportError(f"{path}: fields disagree with authoritative kit")
            for key in sorted(expected):
                _require_same(actual[key], expected[key], f"{path}.{key}")
            return
        if isinstance(actual, list):
            if len(actual) != len(expected):
                raise AtlasImportError(f"{path}: list length disagrees with authoritative kit")
            for index, (actual_child, expected_child) in enumerate(zip(actual, expected)):
                _require_same(actual_child, expected_child, f"{path}[{index}]")
            return
        if actual == expected:
            return
    raise AtlasImportError(f"{path}: value disagrees with authoritative kit")


def validate_atlas_agreement(
    atlas: ExtractedAtlas,
    catalogue: dict[str, Any],
    theme: dict[str, Any],
    schema: dict[str, Any],
    reference: ModuleType,
) -> list[dict[str, Any]]:
    definitions = extract_definitions(atlas)
    candidate = copy.deepcopy(catalogue)
    for program, definition in zip(candidate["programs"], definitions):
        program.update(definition)
    result, parsed = reference.validate_bytes(serialized_json(candidate), schema)
    _require_valid(result, "Atlas definitions under the supplied catalogue schema")
    expected = [
        {name: program[name] for name in ("program_id", "difficulty", "title", "phases")}
        for program in catalogue["programs"]
    ]
    _require_same(definitions, expected, "$atlas.configs")
    _require_same(atlas.data["theme"], theme, "$atlas.theme")
    return definitions


def prepare_import(kit_path: Path, atlas_path: Path | None = None) -> ImportBundle:
    kit = verify_kit(kit_path)
    source = kit.files[ATLAS_PATH] if atlas_path is None else atlas_path.read_bytes()
    if sha256(source) != kit.hashes[ATLAS_PATH]:
        raise AtlasImportError("Atlas source SHA-256 mismatch with the original kit")
    atlas = extract_atlas(source)
    reference = load_reference_validator(kit)
    schema = strict_loads(kit.files[SCHEMA_PATH], SCHEMA_PATH)
    reference.check_schema_subset(schema)
    originals = {relative: strict_loads(kit.files[relative], relative) for relative in IMPORT_PATHS}
    result, catalogue = reference.validate_bytes(kit.files[IMPORT_PATHS[0]], schema)
    _require_valid(result, IMPORT_PATHS[0])
    definitions = validate_atlas_agreement(atlas, catalogue, originals[IMPORT_PATHS[1]], schema, reference)
    _require_same(atlas.data, strict_loads(kit.files[ATLAS_STATES_PATH], ATLAS_STATES_PATH), "$atlas.states_document")
    phases = [phase for config in definitions for phase in config["phases"]]
    artifacts = {PurePosixPath(relative).name: kit.files[relative] for relative in IMPORT_PATHS}
    manifest = {
        "purpose": "verified_original_kit_import_and_documentary_atlas_agreement",
        "source_file": ATLAS_PATH,
        "source_sha256": sha256(source),
        "raw_data_sha256": sha256(atlas.raw_data),
        "checksum_manifest_file": "SHA256SUMS.txt",
        "checksum_manifest_sha256": PINNED_CHECKSUMS_SHA256,
        "checksum_files_verified": len(kit.hashes),
        "atlas_version": atlas.data["version"],
        "compiler_version": atlas.data["compiler_version"],
        "catalogue_revision": catalogue["catalogue_revision"],
        "catalogue_top_level_keys": list(catalogue),
        "configuration_count": len(definitions),
        "public_program_count": len({config["program_id"] for config in definitions}),
        "phase_count": len(phases),
        "difficulty_counts": dict(Counter(config["difficulty"] for config in definitions)),
        "mechanic_counts": dict(Counter(phase["mechanic"] for phase in phases)),
        "motion_kind_counts": dict(Counter(phase["motion"]["kind"] for phase in phases)),
        "linear_reflection_counts": dict(Counter(
            phase["motion"]["reflection"] for phase in phases if phase["motion"]["kind"] == "linear_reflect"
        )),
        "agreement": {
            "configurations": len(definitions),
            "phase_definitions": len(phases),
            "theme": True,
            "atlas_states_document": True,
        },
        "schema_validation": {
            "schema_source": SCHEMA_PATH,
            "schema_sha256": kit.hashes[SCHEMA_PATH],
            "named_definition_count": len(schema["$defs"]),
            "validator_source": VALIDATOR_PATH,
            "validator_sha256": kit.hashes[VALIDATOR_PATH],
            "scope": "supplied frozen schema subset and semantic checks",
            "geometry_certificate_count": len(result["metrics"]["geometry"]),
        },
        "extraction": {
            "purpose": "preliminary_atlas_derived_for_agreement_only",
            "definitions_serialized_sha256": sha256(serialized_json(definitions)),
            "theme_serialized_sha256": sha256(serialized_json(atlas.data["theme"])),
            "hash_encoding": "UTF-8 sorted-key JSON, two-space indent, LF ending; not AIM-CANON-1",
            "illustrative_samples_imported": False,
            "reconstructed_catalogue_imported": False,
        },
        "required_reference_paths": list(REQUIRED_REFERENCE_PATHS),
        "missing_required_reference_paths": [],
        "artifacts": {
            PurePosixPath(relative).name: {"source_path": relative, "sha256": kit.hashes[relative]}
            for relative in IMPORT_PATHS
        },
    }
    artifacts[MANIFEST_NAME] = serialized_json(manifest)
    return ImportBundle(artifacts, manifest)


def save_or_check(bundle: ImportBundle, output_dir: Path, check: bool = False) -> None:
    for name in DERIVED_OUTPUT_NAMES:
        if (output_dir / name).exists() or (output_dir / name).is_symlink():
            raise AtlasImportError(f"{name}: obsolete derived artifact; use a clean output directory")
    for name in bundle.artifacts:
        if (output_dir / name).is_symlink():
            raise AtlasImportError(f"{name}: symlinked output is not accepted")
    if check:
        for name, expected in bundle.artifacts.items():
            destination = output_dir / name
            if not destination.is_file():
                raise AtlasImportError(f"{name}: imported output is missing")
            actual = destination.read_bytes()
            strict_loads(actual, name)
            if actual != expected:
                raise AtlasImportError(f"{name}: stale or altered output; rerun the importer")
        return
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, raw in bundle.artifacts.items():
        temporary_path = None
        try:
            with tempfile.NamedTemporaryFile(dir=output_dir, prefix=f".{name}.", delete=False) as temporary:
                temporary_path = Path(temporary.name)
                temporary.write(raw)
            temporary_path.replace(output_dir / name)
        finally:
            if temporary_path is not None:
                temporary_path.unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kit", required=True, type=Path, help="Original V2 kit root containing SHA256SUMS.txt")
    parser.add_argument("--atlas", type=Path, help="Local Atlas HTML; defaults to the kit's Atlas")
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--check", action="store_true", help="Verify existing imports without writing")
    args = parser.parse_args(argv)
    try:
        if args.output_dir.resolve().is_relative_to(args.kit.resolve()):
            raise AtlasImportError("Output directory must be outside the original kit")
        bundle = prepare_import(args.kit, args.atlas)
        save_or_check(bundle, args.output_dir, args.check)
    except (AtlasImportError, OSError) as error:
        print(f"V2 import failed: {error}", file=sys.stderr)
        return 1
    action = "Checked" if args.check else "Imported"
    print(f"{action} 5 original JSON files; verified {bundle.manifest['checksum_files_verified']} SHA-256 entries, 24 configurations and 54 phase definitions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
