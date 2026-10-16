"""Generate the deterministic, texture-free M17 reference terrain fixture."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SCENARIO = json.loads((ROOT / "scenario.json").read_text(encoding="utf-8"))
SIZE = SCENARIO["chunk_size"][0]
SEED = SCENARIO["seed"]
PALETTE = SCENARIO["block_palette"]
LAKE_X, LAKE_Z = SCENARIO["terrain"]["lake_center_xz"]
LAKE_RX, LAKE_RZ = SCENARIO["terrain"]["lake_radius_xz"]
WATER_Y = SCENARIO["terrain"]["water_level"]


def surface_height(x: int, z: int) -> int:
    """A stable integer hash; intentionally independent of engine PRNGs."""
    mixed = (x * 73856093) ^ (z * 19349663) ^ (SEED * 83492791)
    return SCENARIO["terrain"]["base_height"] + mixed % SCENARIO["terrain"]["height_modulus"] + SCENARIO["terrain"]["height_min_offset"]


def block_at(x: int, y: int, z: int) -> int:
    ground = surface_height(x, z)
    in_lake = ((x - LAKE_X) / LAKE_RX) ** 2 + ((z - LAKE_Z) / LAKE_RZ) ** 2 <= 1.0
    if in_lake:
        ground -= 4
    if y <= ground:
        if y == ground:
            return PALETTE["GRASS"] if not (in_lake and ground < WATER_Y) else PALETTE["DIRT"]
        if y >= ground - 2:
            return PALETTE["DIRT"]
        return PALETTE["STONE"]
    if in_lake and ground < WATER_Y and ground < y <= WATER_Y:
        return PALETTE["WATER"]
    return PALETTE["AIR"]


def chunk_cells(chunk_x: int, chunk_z: int) -> str:
    cells = bytearray(SIZE**3)
    for y in range(SIZE):
        for z in range(SIZE):
            for x in range(SIZE):
                index = x + SIZE * (z + SIZE * y)
                cells[index] = ord("0") + block_at(chunk_x * SIZE + x, y, chunk_z * SIZE + z)
    return cells.decode("ascii")


def main() -> None:
    chunks = []
    for chunk_x, _chunk_y, chunk_z in SCENARIO["chunk_coords"]:
        cells = chunk_cells(chunk_x, chunk_z)
        counts = {name: cells.count(str(block_id)) for name, block_id in PALETTE.items()}
        chunks.append(
            {
                "coord": [chunk_x, 0, chunk_z],
                "cells": cells,
                "sha256": hashlib.sha256(cells.encode("ascii")).hexdigest(),
                "block_counts": counts,
            }
        )
    output = {"schema_version": SCENARIO["schema_version"], "seed": SEED, "chunk_size": SIZE, "chunks": chunks}
    path = ROOT / "fixture" / "world.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(output, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Wrote {path.relative_to(ROOT)} ({len(chunks)} chunks; SHA-256 per chunk).")


if __name__ == "__main__":
    main()
