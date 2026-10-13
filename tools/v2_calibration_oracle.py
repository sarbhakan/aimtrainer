import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys


def encode_binary64(value):
    if isinstance(value, float):
        return "f64be:" + struct.pack(">d", value).hex()
    if isinstance(value, dict):
        return {key: encode_binary64(element) for key, element in value.items()}
    if isinstance(value, list):
        return [encode_binary64(element) for element in value]
    return value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kit", type=Path, default=Path(__file__).resolve().parents[1] / "docs/reference/v2")
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    source_root = arguments.kit / "outils"
    sys.path.insert(0, str(source_root))
    specification = importlib.util.spec_from_file_location("calibration_reference", source_root / "calibration_v2_reference.py")
    reference = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(reference)
    gain_cases = [("A", 35.0, 800), ("A", 5.0, 800), ("A", 150.0, 800), ("A", 5.1, 1600), ("A", 149.0, 400), ("A", 35.0, 1), ("A", 35.0, 9007199254740991)]
    grids = []
    for candidate_id, nominal_cm, dpi in gain_cases:
        baseline = reference.make_gain(candidate_id, nominal_cm, dpi)
        for ratio in (1.25, 1.5):
            try:
                gains = reference.candidate_grid(baseline, ratio)
                grids.append({"baseline": baseline, "ratio": ratio, "gains": gains})
            except ValueError as error:
                grids.append({"baseline": baseline, "ratio": ratio, "error": str(error)})
    decks = []
    for seed in ("5a02072603bc40c786d1f934d300005e", "60f8768b30509bfe1775272a1f248b94"):
        for difficulty in ("novice", "standard", "advanced"):
            for task in reference.TASKS:
                arguments_tuple = [seed, "confirmation", "1", "0", "0", task, difficulty]
                decks.append({"arguments": arguments_tuple, "deck": reference.make_deck(*arguments_tuple)})
    for task in reference.TASKS:
        arguments_tuple = ["60f8768b30509bfe1775272a1f248b94", "confirmation", "2", "1", "1", task, "standard"]
        decks.append({"arguments": arguments_tuple, "deck": reference.make_deck(*arguments_tuple)})
    sources = {}
    for relative_path in ("AIM_LOCAL_SPECIFICATIONS_V2.md", "outils/calibration_v2_reference.py", "outils/mouvements_reference.py", "outils/empreintes_reference.py", "donnees/calibration_v2_protocol.json", "donnees/catalogue.v2.json", "donnees/calibration_v2_comparison_examples.json", "donnees/calibration_v2_plan_negative_fixtures.json"):
        sources[relative_path] = hashlib.sha256((arguments.kit / relative_path).read_bytes()).hexdigest()
    fixtures = json.loads((arguments.kit / "donnees/calibration_v2_comparison_examples.json").read_text(encoding="utf-8"))
    output = {"schema_version": "aimlocal.calibration.development_oracle.v2", "source_sha256": sources,
              "protocol_sha256": reference.protocol_hash(), "protocol": reference.protocol(), "grids": grids, "decks": decks,
              "comparisons": fixtures, "example_plan": reference.example_plan(),
              "negative_plans": reference.negative_plan_fixtures(reference.example_plan())}
    arguments.output.write_text(json.dumps(encode_binary64(output), ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(arguments.output), "protocol_sha256": output["protocol_sha256"], "grids": len(grids), "decks": len(decks)}))


if __name__ == "__main__":
    main()
