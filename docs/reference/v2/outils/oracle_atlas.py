"""Oracle Python local pour valider_atlas.js ; requête/réponse JSON sur stdio.

Lit les états livrés et interroge les références Python existantes. Aucun export
d'image ni réécriture du catalogue. Ne simule ni input humain ni score.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE / "outils"))

from construire_visuels import rebuild_motion, targets_at
from geometrie_reference import sphere_contour
from mouvements_reference import COMPILER_VERSION


def main():
    request = json.load(sys.stdin)
    data = json.loads((BASE / "donnees/atlas.etats.json").read_text(encoding="utf-8"))
    cache = {}

    def phase(query):
        return data["configs"][query["c"]]["phases"][query["p"]]

    def sample(query):
        key = query["c"], query["p"], query["s"]
        if key not in cache:
            cache[key] = rebuild_motion(phase(query)["states"][query["s"]])
        return cache[key].sample(query["t"])

    def targets(query):
        # Le helper targets_at évalue une phase. La fermeture de programme est
        # une règle de son appelant ; l'atlas applique cette règle à t=60.
        if query["global_t"] >= 60:
            return []
        return targets_at(phase(query), query["t"])

    contours = []
    for query in request["contours"]:
        available = targets(query)
        if not available:
            raise ValueError("CONTOUR_QUERY_REQUIRES_ACTIVE_TARGET")
        args = list(available[query.get("target", 0)][:4])
        contours.append({"args": args, "points": sphere_contour(*args)})
    result = {
        "compiler_version": COMPILER_VERSION,
        "samples": [sample(q) for q in request["samples"]],
        "targets": [targets(q) for q in request["targets"]],
        "contours": contours,
    }
    json.dump(result, sys.stdout, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


if __name__ == "__main__":
    main()
