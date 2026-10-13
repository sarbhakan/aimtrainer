#!/usr/bin/env python3
"""Stdlib importer tests; all filesystem mutations stay in temporary directories.

Run: python3 -B tests/v2_atlas_import_tests.py --kit docs/reference/v2 -v
"""

from __future__ import annotations

import argparse
import copy
import io
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "tools"))
import import_v2_atlas as importer

KIT_PATH = ROOT / "docs/reference/v2"
TOOL_PATH = ROOT / "tools/import_v2_atlas.py"
ATLAS_ATTRIBUTES = 'id="atlas-data" type="application/json"'
PARSER_DATA = {
    "version": "aimlocal.atlas.v2",
    "compiler_version": "motion_reference_v2.0",
    "theme": {},
    "configs": [],
    "scope": "offline parser fixture",
}


def atlas_html(data: object, attributes: str = ATLAS_ATTRIBUTES) -> bytes:
    raw = json.dumps(data, ensure_ascii=False, allow_nan=False)
    return f"<html><script {attributes}>{raw}</script></html>".encode("utf-8")


class AtlasParserTests(unittest.TestCase):
    def test_offline_data_extraction_ignores_executable_scripts(self) -> None:
        source = b"<script src='https://example.invalid/payload.js'></script>"
        source += b"<script>throw new Error('must never run'); fetch('https://example.invalid')</script>"
        source += atlas_html(PARSER_DATA)
        self.assertEqual(importer.extract_atlas(source).data, PARSER_DATA)

    def test_raw_json_is_not_entity_decoded(self) -> None:
        data = copy.deepcopy(PARSER_DATA)
        data["scope"] = "&amp; &#65; é"
        extracted = importer.extract_atlas(atlas_html(data))
        self.assertEqual(extracted.data["scope"], data["scope"])
        self.assertIn(b"&amp; &#65;", extracted.raw_data)

    def test_case_and_attribute_order_follow_html_rules(self) -> None:
        source = atlas_html(PARSER_DATA, 'TYPE="application/json" ID="atlas-data"')
        source = source.replace(b"<script ", b"<SCRIPT ").replace(b"</script>", b"</SCRIPT>")
        self.assertEqual(importer.extract_atlas(source).data, PARSER_DATA)

    def test_missing_script(self) -> None:
        with self.assertRaisesRegex(importer.AtlasImportError, "Missing atlas-data"):
            importer.extract_atlas(b"<html><script>{}</script></html>")

    def test_duplicate_scripts(self) -> None:
        with self.assertRaisesRegex(importer.AtlasImportError, "Duplicate atlas-data script"):
            importer.extract_atlas(atlas_html(PARSER_DATA) * 2)

    def test_duplicate_id_attributes(self) -> None:
        with self.assertRaisesRegex(importer.AtlasImportError, "Duplicate.*attribute"):
            importer.extract_atlas(atlas_html(PARSER_DATA, ATLAS_ATTRIBUTES + ' id="other"'))

    def test_duplicate_type_attributes(self) -> None:
        with self.assertRaisesRegex(importer.AtlasImportError, "Duplicate.*attribute"):
            importer.extract_atlas(atlas_html(PARSER_DATA, ATLAS_ATTRIBUTES + ' type="text/javascript"'))

    def test_unknown_or_executable_attributes(self) -> None:
        for attribute in (' src="https://example.invalid/atlas.json"', ' onload="alert(1)"', ' data-extra="1"', ' async'):
            with self.subTest(attribute=attribute):
                with self.assertRaisesRegex(importer.AtlasImportError, "requires only"):
                    importer.extract_atlas(atlas_html(PARSER_DATA, ATLAS_ATTRIBUTES + attribute))

    def test_wrong_script_type(self) -> None:
        with self.assertRaisesRegex(importer.AtlasImportError, "requires only"):
            importer.extract_atlas(atlas_html(PARSER_DATA, 'id="atlas-data" type="text/javascript"'))

    def test_missing_script_type(self) -> None:
        with self.assertRaisesRegex(importer.AtlasImportError, "requires only"):
            importer.extract_atlas(atlas_html(PARSER_DATA, 'id="atlas-data"'))

    def test_id_on_non_script(self) -> None:
        with self.assertRaisesRegex(importer.AtlasImportError, "script element"):
            importer.extract_atlas(b'<div id="atlas-data">{}</div>')

    def test_unclosed_script(self) -> None:
        with self.assertRaisesRegex(importer.AtlasImportError, "Unclosed"):
            importer.extract_atlas(atlas_html(PARSER_DATA).replace(b"</script>", b""))

    def test_self_closing_script(self) -> None:
        with self.assertRaisesRegex(importer.AtlasImportError, "self-closing"):
            importer.extract_atlas(b'<script id="atlas-data" type="application/json"/>')

    def test_embedded_closing_script_invalidates_json(self) -> None:
        data = copy.deepcopy(PARSER_DATA)
        data["scope"] = "</script><script>alert(1)</script>"
        with self.assertRaises(importer.AtlasImportError):
            importer.extract_atlas(atlas_html(data))

    def test_invalid_utf8(self) -> None:
        with self.assertRaisesRegex(importer.AtlasImportError, "UTF-8|utf-8"):
            importer.extract_atlas(atlas_html(PARSER_DATA) + b"\xff")

    def test_wrong_root_shape(self) -> None:
        for value in ([], None, 7, "sample"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(importer.AtlasImportError, "expected an object"):
                    importer.extract_atlas(atlas_html(value))

    def test_missing_unknown_root_keys_and_versions(self) -> None:
        mutations = ({"unexpected": True}, {"version": "v1"}, {"compiler_version": "unknown"}, {"theme": []}, {"scope": None})
        for mutation in mutations:
            data = copy.deepcopy(PARSER_DATA)
            data.update(mutation)
            with self.subTest(mutation=mutation):
                with self.assertRaises(importer.AtlasImportError):
                    importer.extract_atlas(atlas_html(data))
        data = copy.deepcopy(PARSER_DATA)
        del data["configs"]
        with self.assertRaisesRegex(importer.AtlasImportError, "missing fields"):
            importer.extract_atlas(atlas_html(data))

    def test_duplicate_json_keys_at_every_depth(self) -> None:
        for raw in (b'{"version":1,"version":2}', b'{"theme":{"color":1,"color":2}}', b'{"configs":[{"id":1,"id":2}]}'):
            with self.subTest(raw=raw):
                with self.assertRaisesRegex(importer.AtlasImportError, "Duplicate JSON key"):
                    importer.extract_atlas(b'<script id="atlas-data" type="application/json">' + raw + b"</script>")

    def test_strict_json_encoding_failures(self) -> None:
        invalid = (b'{"value":NaN}', b'{"value":Infinity}', b'{"value":-Infinity}', b'{"value":1e9999}', b'{"value":9007199254740992}', b'{"value":1,}', b'{"value":"\\ud800"}', b'{"value":"\\udfff"}', b"\xef\xbb\xbf{}", b"{} {}", b'{"value":"\xff"}')
        for raw in invalid:
            with self.subTest(raw=raw):
                with self.assertRaises(importer.AtlasImportError):
                    importer.strict_loads(raw)


class VerifiedKitTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.kit = importer.verify_kit(KIT_PATH)
        cls.reference = importer.load_reference_validator(cls.kit)
        cls.schema = importer.strict_loads(cls.kit.files[importer.SCHEMA_PATH])
        cls.catalogue = importer.strict_loads(cls.kit.files[importer.IMPORT_PATHS[0]])
        cls.theme = importer.strict_loads(cls.kit.files[importer.IMPORT_PATHS[1]])
        cls.atlas = importer.extract_atlas(cls.kit.files[importer.ATLAS_PATH])

    def validate_data(self, data: dict) -> list[dict]:
        atlas = importer.extract_atlas(atlas_html(data))
        return importer.validate_atlas_agreement(atlas, self.catalogue, self.theme, self.schema, self.reference)

    def phase(self, data: dict, program_id: str, phase_id: str) -> dict:
        config = next(config for config in data["configs"] if config["program_id"] == program_id and config["difficulty"] == "standard")
        return next(phase["definition"] for phase in config["phases"] if phase["id"] == phase_id)


class AtlasAgreementTests(VerifiedKitTestCase):
    def test_all_54_definitions_preserved_without_samples(self) -> None:
        before = copy.deepcopy(self.atlas.data)
        definitions = self.validate_data(self.atlas.data)
        self.assertEqual(len(definitions), 24)
        self.assertEqual(sum(len(config["phases"]) for config in definitions), 54)
        for original, extracted in zip(self.catalogue["programs"], definitions):
            self.assertEqual(extracted, {key: original[key] for key in ("program_id", "difficulty", "title", "phases")})
            for phase in extracted["phases"]:
                self.assertFalse({"static_positions", "states", "opportunities"} & phase.keys())
        self.assertEqual(self.atlas.data, before)

    def test_exact_theme_and_smooth_reflection_modifier(self) -> None:
        self.assertEqual(self.atlas.data["theme"], self.theme)
        definitions = self.validate_data(self.atlas.data)
        for config in definitions:
            if config["program_id"] == "EX08":
                mobile = config["phases"][1]["motion"]
                self.assertEqual(mobile["kind"], "linear_reflect")
                self.assertEqual(mobile["reflection"], "symmetric_cubic_smoothstep_velocity")
                self.assertTrue(mobile["finite_acceleration_limit_applies"])

    def test_configuration_matrix_missing_duplicate_unknown_and_order(self) -> None:
        for mutation in ("missing", "duplicate", "unknown", "order"):
            data = copy.deepcopy(self.atlas.data)
            if mutation == "missing":
                data["configs"].pop()
            elif mutation == "duplicate":
                data["configs"][1] = copy.deepcopy(data["configs"][0])
            elif mutation == "unknown":
                data["configs"][0]["difficulty"] = "expert"
            else:
                data["configs"][0], data["configs"][1] = data["configs"][1], data["configs"][0]
            with self.subTest(mutation=mutation):
                with self.assertRaisesRegex(importer.AtlasImportError, "24 configurations|matrix|order"):
                    self.validate_data(data)

    def test_phase_count_and_wrapper_identity(self) -> None:
        for mutation in ("missing", "duplicate", "wrapper"):
            data = copy.deepcopy(self.atlas.data)
            phases = data["configs"][0]["phases"]
            if mutation == "missing":
                phases.pop()
            elif mutation == "duplicate":
                phases.append(copy.deepcopy(phases[0]))
            else:
                phases[0]["id"] = "sample"
            with self.subTest(mutation=mutation):
                with self.assertRaisesRegex(importer.AtlasImportError, "54 phases|IDs disagree"):
                    self.validate_data(data)

    def test_phase_order_even_with_contiguous_retiming(self) -> None:
        data = copy.deepcopy(self.atlas.data)
        phases = data["configs"][0]["phases"]
        phases[0], phases[1] = phases[1], phases[0]
        for index, phase in enumerate(phases):
            phase["definition"]["start_s"] = index * 20
        with self.assertRaisesRegex(importer.AtlasImportError, "phase_identity"):
            self.validate_data(data)

    def test_missing_each_phase_field(self) -> None:
        fields = list(self.atlas.data["configs"][0]["phases"][0]["definition"])
        for field in fields:
            data = copy.deepcopy(self.atlas.data)
            del data["configs"][0]["phases"][0]["definition"][field]
            with self.subTest(field=field):
                with self.assertRaisesRegex(importer.AtlasImportError, "required|IDs disagree"):
                    self.validate_data(data)

    def test_samples_in_definitions_are_rejected_by_original_schema(self) -> None:
        for field in ("static_positions", "states", "opportunities"):
            data = copy.deepcopy(self.atlas.data)
            data["configs"][0]["phases"][0]["definition"][field] = []
            with self.subTest(field=field):
                with self.assertRaisesRegex(importer.AtlasImportError, "additionalProperties"):
                    self.validate_data(data)

    def test_unexpected_wrapper_fields_and_wrong_sample_shapes(self) -> None:
        for mutation in ("config", "phase", "sample"):
            data = copy.deepcopy(self.atlas.data)
            if mutation == "config":
                data["configs"][0]["sample_positions"] = []
            elif mutation == "phase":
                data["configs"][0]["phases"][0]["override"] = True
            else:
                data["configs"][0]["phases"][0]["states"] = {}
            with self.subTest(mutation=mutation):
                with self.assertRaises(importer.AtlasImportError):
                    self.validate_data(data)

    def test_valid_altered_variant_values_still_fail_agreement(self) -> None:
        data = copy.deepcopy(self.atlas.data)
        phase = self.phase(data, "EX01", "micro")
        phase["diameter_deg"] = 1.1
        phase["size"]["world_radius_m"] = 4 * importer.math.sin(importer.math.radians(1.1) / 2)
        with self.assertRaisesRegex(importer.AtlasImportError, "disagrees with authoritative kit"):
            self.validate_data(data)

    def test_altered_theme_and_configuration_title_fail_agreement(self) -> None:
        for mutation in ("theme", "title"):
            data = copy.deepcopy(self.atlas.data)
            if mutation == "theme":
                data["theme"]["palette"]["target_primary"] = "#FFFFFF"
            else:
                data["configs"][0]["title"] = "Illustration"
            with self.subTest(mutation=mutation):
                with self.assertRaisesRegex(importer.AtlasImportError, "disagrees with authoritative kit"):
                    self.validate_data(data)

    def test_schema_ownership_and_unknown_keywords_fail_closed(self) -> None:
        schema = copy.deepcopy(self.schema)
        schema["unevaluatedProperties"] = False
        with self.assertRaisesRegex(ValueError, "unsupported schema keywords"):
            self.reference.check_schema_subset(schema)
        self.assertEqual(len(self.schema["$defs"]), 14)


CONTRACT_MUTATIONS = (
    ("boolean_count", "EX01", "micro", ("target_count",), True, "type"),
    ("boolean_duration", "EX01", "micro", ("duration_s",), True, "type"),
    ("boolean_diameter", "EX01", "micro", ("diameter_deg",), True, "type"),
    ("boolean_distance", "EX01", "micro", ("distance_m",), True, "type"),
    ("nonfinite_scalar", "EX01", "micro", ("diameter_deg",), float("inf"), "non-finite"),
    ("phase_gap", "EX01", "general", ("start_s",), 21, "phase_contiguity"),
    ("phase_overlap", "EX01", "general", ("start_s",), 19, "phase_contiguity"),
    ("phase_duration", "EX01", "amplitude", ("duration_s",), 19, "phase_duration"),
    ("target_slot_mismatch", "EX01", "micro", ("spawn", "target_slots"), 2, "slot_count"),
    ("wrong_score_kind", "EX01", "micro", ("scoring", "id"), "contact_v2", "structure"),
    ("score_duration", "EX01", "micro", ("scoring", "phase_duration_s"), 19, "score_duration"),
    ("wrong_accuracy_exponent", "EX01", "micro", ("scoring", "accuracy_exponent"), 2, "const"),
    ("render_gate", "EX01", "micro", ("lifecycle", "spawn_is_hittable_after"), "logical_birth", "const"),
    ("generic_ttl", "EX01", "micro", ("lifecycle", "ttl_s"), 10, "structure"),
    ("zero_ttl", "EX03", "fixed_window", ("lifecycle", "ttl_s"), 0, "structure"),
    ("window_overflow", "EX03", "fixed_window", ("lifecycle", "ttl_s"), 2.5, "window_overflow"),
    ("schedule_depends_on_hits", "EX03", "fixed_window", ("spawn", "schedule", "schedule_depends_on_hits"), True, "const"),
    ("extra_opportunity", "EX03", "fixed_window", ("spawn", "schedule", "slots"), 11, "window_schedule_duration"),
    ("window_size_duration", "EX03", "shrinking_window", ("size", "progress_duration_s"), 0.5, "window_size_duration"),
    ("shrink_ratio", "EX03", "shrinking_window", ("size", "diameter_end_deg"), 1.9, "shrink_ratio"),
    ("human_miss_for_render_failure", "EX03", "fixed_window", ("lifecycle", "human_miss_on_nonpresented_opportunity"), True, "const"),
    ("retimed_tracking_exposure", "EX05", "horizontal", ("scoring", "exposure_never_retimed"), False, "const"),
    ("tracking_requires_fire", "EX05", "horizontal", ("scoring", "contact_requires_fire"), True, "const"),
    ("sine_speed", "EX05", "horizontal", ("motion", "omega_rad_s"), 2, "sinusoid_speed"),
    ("ellipse_acceleration", "EX05", "ellipse", ("motion", "acceleration_validation_limit_deg_s2"), 1, "ellipse_acceleration_sample"),
    ("reactive_mixture", "EX06", "reactive", ("motion", "plateau_duration_mixture", 0, "weight"), 0.6, "mixture_weights"),
    ("reactive_event_horizon", "EX06", "reactive", ("motion", "event_tape", "horizon_s"), 10, "event_horizon"),
    ("reactive_braking", "EX06", "reactive", ("motion", "boundary", "trigger_inset_deg"), 0.1, "braking_distance"),
    ("soft_turn_inset", "EX08", "mobile", ("motion", "turn_entry_inset_deg"), 0.1, "soft_reflect_inset"),
    ("bounce_gravity", "EX04", "arcs", ("motion", "pitch_acceleration_deg_s2"), -9.81, "bounce_gravity"),
    ("world_radius", "EX01", "micro", ("size", "world_radius_m"), 0.09, "sphere_radius"),
    ("reversed_spawn_range", "EX01", "micro", ("spawn", "yaw_deg"), [6, -6], "range_order"),
    ("depth_envelope", "EX07", "depth", ("envelope", "center_distance_m"), [4, 4], "apparent_diameter"),
    ("depth_screen_compensation", "EX07", "depth", ("motion", "no_screen_size_compensation"), False, "const"),
    ("switch_ttk", "EX08", "static", ("lifecycle", "ideal_contact_time_to_kill_s"), 0.2, "ideal_ttk"),
    ("switch_hp", "EX08", "static", ("lifecycle", "hp_max"), 41, "score_hp"),
    ("switch_regeneration", "EX08", "static", ("lifecycle", "hp_regeneration_per_s"), 1, "hp_regeneration"),
    ("switch_partial_credit", "EX08", "static", ("scoring", "partial_credit"), "discard", "const"),
    ("unknown_motion", "EX01", "micro", ("motion", "kind"), "teleport", "oneOf"),
)


def contract_mutation_test(case: tuple):
    name, program_id, phase_id, field_path, value, evidence = case

    def run_case(self: AtlasAgreementTests) -> None:
        data = copy.deepcopy(self.atlas.data)
        target = self.phase(data, program_id, phase_id)
        for field in field_path[:-1]:
            target = target[field]
        target[field_path[-1]] = value
        if name == "nonfinite_scalar":
            atlas = importer.ExtractedAtlas(data, b"")
            with self.assertRaisesRegex(importer.AtlasImportError, re.escape(evidence)):
                importer.validate_atlas_agreement(atlas, self.catalogue, self.theme, self.schema, self.reference)
        else:
            with self.assertRaisesRegex(importer.AtlasImportError, re.escape(evidence)):
                self.validate_data(data)

    return run_case


for mutation_case in CONTRACT_MUTATIONS:
    setattr(AtlasAgreementTests, f"test_reject_{mutation_case[0]}", contract_mutation_test(mutation_case))


class ChecksumSyntaxTests(unittest.TestCase):
    def test_valid_checksum_lines(self) -> None:
        self.assertEqual(importer.parse_checksums(("a" * 64 + "  donnees/catalogue.v2.json\n").encode()), {"donnees/catalogue.v2.json": "a" * 64})

    def test_unsafe_checksum_paths(self) -> None:
        for path in ("/etc/passwd", "../outside", "donnees/../outside", "donnees//catalogue", "./catalogue", "donnees\\catalogue", "C:/outside", "https://example.invalid/source", "SHA256SUMS.txt", "donnees/file\x00", "donnees/file\t"):
            with self.subTest(path=path):
                with self.assertRaisesRegex(importer.AtlasImportError, "unsafe"):
                    importer.parse_checksums(("a" * 64 + "  " + path + "\n").encode())

    def test_duplicate_checksum_paths(self) -> None:
        line = ("a" * 64 + "  donnees/catalogue.v2.json\n").encode()
        with self.assertRaisesRegex(importer.AtlasImportError, "duplicate source path"):
            importer.parse_checksums(line + line)

    def test_malformed_and_empty_manifests(self) -> None:
        for raw in (b"", b"\n", b"abcd  file\n", ("a" * 64 + " file\n").encode(), b"\xff"):
            with self.subTest(raw=raw):
                with self.assertRaises(importer.AtlasImportError):
                    importer.parse_checksums(raw)


class KitIntegrityTests(VerifiedKitTestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.copy = self.root / "kit"
        shutil.copytree(KIT_PATH, self.copy, ignore=shutil.ignore_patterns("__pycache__"))

    def test_complete_source_checksum_count(self) -> None:
        self.assertEqual(len(importer.verify_kit(self.copy).hashes), 81)

    def test_every_imported_source_refuses_byte_changes(self) -> None:
        for relative in importer.IMPORT_PATHS:
            source = self.copy / relative
            original = source.read_bytes()
            source.write_bytes(original + b"\n")
            with self.subTest(relative=relative):
                with self.assertRaisesRegex(importer.AtlasImportError, re.escape(relative) + ".*SHA-256 mismatch"):
                    importer.verify_kit(self.copy)
            source.write_bytes(original)

    def test_non_imported_kit_file_also_verified(self) -> None:
        (self.copy / "assets/fonts/LICENSE-DejaVu.txt").write_bytes(b"altered")
        with self.assertRaisesRegex(importer.AtlasImportError, "SHA-256 mismatch"):
            importer.verify_kit(self.copy)

    def test_rewritten_checksums_cannot_authorize_modified_source(self) -> None:
        relative = importer.IMPORT_PATHS[0]
        source = self.copy / relative
        old_sha = importer.sha256(source.read_bytes())
        source.write_bytes(source.read_bytes() + b"\n")
        manifest = self.copy / "SHA256SUMS.txt"
        manifest.write_bytes(manifest.read_bytes().replace(old_sha.encode(), importer.sha256(source.read_bytes()).encode()))
        with self.assertRaisesRegex(importer.AtlasImportError, "pinned original"):
            importer.verify_kit(self.copy)

    def test_missing_required_source(self) -> None:
        (self.copy / importer.SCHEMA_PATH).unlink()
        with self.assertRaisesRegex(importer.AtlasImportError, "required source is missing"):
            importer.verify_kit(self.copy)

    def test_symlinked_file_source(self) -> None:
        source = self.copy / importer.IMPORT_PATHS[0]
        raw = source.read_bytes()
        source.unlink()
        outside = self.root / "outside.json"
        outside.write_bytes(raw)
        source.symlink_to(outside)
        with self.assertRaisesRegex(importer.AtlasImportError, "symlinked kit"):
            importer.verify_kit(self.copy)

    def test_symlinked_directory_source(self) -> None:
        source = self.copy / "schemas"
        source.rename(self.root / "outside-schemas")
        source.symlink_to(self.root / "outside-schemas", target_is_directory=True)
        with self.assertRaisesRegex(importer.AtlasImportError, "symlinked kit"):
            importer.verify_kit(self.copy)

    def test_altered_separate_atlas_is_rejected(self) -> None:
        atlas = self.root / importer.ATLAS_PATH
        atlas.write_bytes(self.kit.files[importer.ATLAS_PATH] + b"\n")
        with self.assertRaisesRegex(importer.AtlasImportError, "Atlas source SHA-256 mismatch"):
            importer.prepare_import(self.copy, atlas)


class ImportOutputTests(VerifiedKitTestCase):
    @classmethod
    def setUpClass(cls) -> None:
        super().setUpClass()
        cls.bundle = importer.prepare_import(KIT_PATH)

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name) / "output"

    def write_outputs(self) -> None:
        importer.save_or_check(self.bundle, self.output)

    def test_imports_are_original_bytes_and_no_derived_catalogue(self) -> None:
        self.write_outputs()
        self.assertEqual(set(path.name for path in self.output.iterdir()), set(self.bundle.artifacts))
        for relative in importer.IMPORT_PATHS:
            self.assertEqual((self.output / Path(relative).name).read_bytes(), self.kit.files[relative])

    def test_manifest_has_portable_complete_provenance(self) -> None:
        manifest = self.bundle.manifest
        self.assertEqual(manifest["checksum_files_verified"], 81)
        self.assertEqual(manifest["phase_count"], 54)
        self.assertEqual(manifest["agreement"]["phase_definitions"], 54)
        self.assertEqual(manifest["missing_required_reference_paths"], [])
        self.assertEqual(manifest["source_sha256"], self.kit.hashes[importer.ATLAS_PATH])
        self.assertEqual(manifest["raw_data_sha256"], importer.sha256(self.atlas.raw_data))
        self.assertEqual(manifest["catalogue_top_level_keys"], list(self.catalogue))
        self.assertFalse(manifest["extraction"]["reconstructed_catalogue_imported"])
        self.assertIn("not AIM-CANON-1", manifest["extraction"]["hash_encoding"])
        self.assertNotIn(str(KIT_PATH), self.bundle.artifacts[importer.MANIFEST_NAME].decode())

    def test_repeatable_import_and_read_only_check(self) -> None:
        self.write_outputs()
        before = {path.name: (path.read_bytes(), path.stat().st_mtime_ns) for path in self.output.iterdir()}
        importer.save_or_check(self.bundle, self.output, check=True)
        after = {path.name: (path.read_bytes(), path.stat().st_mtime_ns) for path in self.output.iterdir()}
        self.assertEqual(before, after)
        importer.save_or_check(self.bundle, self.output)
        self.assertEqual({path.name: path.read_bytes() for path in self.output.iterdir()}, self.bundle.artifacts)

    def test_check_missing_directory_does_not_create_it(self) -> None:
        with self.assertRaisesRegex(importer.AtlasImportError, "missing"):
            importer.save_or_check(self.bundle, self.output, check=True)
        self.assertFalse(self.output.exists())

    def test_check_missing_file(self) -> None:
        self.write_outputs()
        (self.output / "runtime.contract.json").unlink()
        with self.assertRaisesRegex(importer.AtlasImportError, "runtime.contract.json.*missing"):
            importer.save_or_check(self.bundle, self.output, check=True)

    def test_check_all_originals_for_even_whitespace_changes(self) -> None:
        self.write_outputs()
        for relative in importer.IMPORT_PATHS:
            target = self.output / Path(relative).name
            original = target.read_bytes()
            target.write_bytes(original + b"\n")
            with self.subTest(relative=relative):
                with self.assertRaisesRegex(importer.AtlasImportError, "stale or altered"):
                    importer.save_or_check(self.bundle, self.output, check=True)
            target.write_bytes(original)

    def test_check_stale_or_missing_provenance(self) -> None:
        self.write_outputs()
        target = self.output / importer.MANIFEST_NAME
        manifest = copy.deepcopy(self.bundle.manifest)
        manifest["source_sha256"] = "0" * 64
        target.write_bytes(importer.serialized_json(manifest))
        with self.assertRaisesRegex(importer.AtlasImportError, "atlas_source_manifest.json.*stale"):
            importer.save_or_check(self.bundle, self.output, check=True)

    def test_check_sampled_catalogue(self) -> None:
        self.write_outputs()
        target = self.output / "catalogue.v2.json"
        catalogue = copy.deepcopy(self.catalogue)
        catalogue["programs"][0]["phases"][0]["static_positions"] = [[0, 0]]
        target.write_bytes(importer.serialized_json(catalogue))
        with self.assertRaisesRegex(importer.AtlasImportError, "catalogue.v2.json.*stale"):
            importer.save_or_check(self.bundle, self.output, check=True)

    def test_check_duplicate_keys_in_disk_output(self) -> None:
        self.write_outputs()
        (self.output / "interface.theme.json").write_bytes(b'{"schema_version":1,"schema_version":2}')
        with self.assertRaisesRegex(importer.AtlasImportError, "Duplicate JSON key"):
            importer.save_or_check(self.bundle, self.output, check=True)

    def test_derived_artifacts_rejected_in_both_modes(self) -> None:
        self.write_outputs()
        for name in importer.DERIVED_OUTPUT_NAMES:
            target = self.output / name
            target.write_bytes(b"{}")
            for check in (False, True):
                with self.subTest(name=name, check=check):
                    with self.assertRaisesRegex(importer.AtlasImportError, "obsolete derived artifact"):
                        importer.save_or_check(self.bundle, self.output, check=check)
            target.unlink()

    def test_output_symlink_rejected_without_changing_target(self) -> None:
        self.output.mkdir()
        outside = Path(self.temporary.name) / "outside.json"
        outside.write_bytes(b"untouched")
        (self.output / "catalogue.v2.json").symlink_to(outside)
        with self.assertRaisesRegex(importer.AtlasImportError, "symlinked output"):
            importer.save_or_check(self.bundle, self.output)
        self.assertEqual(outside.read_bytes(), b"untouched")

    def test_cli_import_check_and_failed_check_exit_codes(self) -> None:
        command = [sys.executable, "-B", str(TOOL_PATH), "--kit", str(KIT_PATH), "--atlas", str(KIT_PATH / importer.ATLAS_PATH), "--output-dir", str(self.output)]
        imported = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(imported.returncode, 0, imported.stderr)
        self.assertIn("81 SHA-256 entries", imported.stdout)
        checked = subprocess.run(command + ["--check"], capture_output=True, text=True, check=False)
        self.assertEqual(checked.returncode, 0, checked.stderr)
        (self.output / "catalogue.v2.json").write_bytes(b"{}")
        failed = subprocess.run(command + ["--check"], capture_output=True, text=True, check=False)
        self.assertEqual(failed.returncode, 1)
        self.assertIn("stale or altered", failed.stderr)

    def test_cli_refuses_output_in_the_original_kit(self) -> None:
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()) as errors:
            status = importer.main(["--kit", str(KIT_PATH), "--output-dir", str(KIT_PATH / "generated")])
        self.assertEqual(status, 1)
        self.assertIn("outside the original kit", errors.getvalue())


if __name__ == "__main__":
    argument_parser = argparse.ArgumentParser(add_help=False)
    argument_parser.add_argument("--kit", type=Path, default=KIT_PATH)
    arguments, unittest_arguments = argument_parser.parse_known_args()
    KIT_PATH = arguments.kit
    unittest.main(argv=[sys.argv[0], *unittest_arguments])
