"""Function-level attribution for the M16 chunk-load and mesh-rebuild cost.

The frame-level profiler (``profile_m16_stutter.py``) answers *which frame*
stutters and how that frame splits across coarse operations (terrain, entity,
mesh, reconcile). It cannot say where the milliseconds go *inside* one of those
operations.

This script answers that second question in two independent ways:

1. **Phase timings** - unprofiled wall-clock time per real phase of a cold chunk
   load (terrain blocks, vegetation, mesh generation, mesh lists, the inline
   transparency scan, full entity creation) and for one mesh rebuild. These are
   the numbers to trust for magnitude.
2. **cProfile shares** - which functions dominate, so the phase numbers can be
   attributed to real code. ``cProfile`` inflates absolute times, so compare
   *shares*, never the raw profiler milliseconds.

Both run against a real Ursina application (offscreen by default) so mesh and
entity creation costs are the real ones.

Usage::

    python scripts/profile_m16_attribution.py --count 12 --repeats 3
    python scripts/profile_m16_attribution.py --windowed --output config/m16_attribution.json
"""

from __future__ import annotations

import argparse
import cProfile
import json
import pstats
import statistics
import sys
import time as pytime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from terrain_generation import TerrainGenerator  # noqa: E402
from world import World  # noqa: E402

DEFAULT_OUTPUT = REPO_ROOT / "config" / "m16_attribution.json"

# Chunk coordinates are drawn from far-away blocks that a fresh world never
# generates, so every measured chunk is a genuine cold chunk instead of a
# registry hit. Each repeat uses its own block so no phase ever re-measures an
# already-loaded chunk.
PHASE_ORIGIN = 200
BLOCK_SIZE = 40
WARMUP_ORIGIN = 60
# The cProfile section must not touch any chunk block the phase or warm-up
# sections already loaded, or every profiled "load" is a registry hit and the
# whole section measures nothing.
PROFILE_ORIGIN = 1000


def fresh_chunk_keys(count: int, origin: int) -> list[tuple[int, int, int]]:
    """Return ``count`` distinct ground-layer chunk keys in a far-away block."""
    keys = []
    chunk_x = origin
    chunk_z = origin
    while len(keys) < count:
        keys.append((chunk_x, 0, chunk_z))
        chunk_z += 1
        if chunk_z > origin + 24:
            chunk_z = origin
            chunk_x += 1
    return keys


def build_world():
    """Return ``(world, generator)`` with the initial region generated."""
    generator = TerrainGenerator()
    world = World()
    generator.generate_world(world)
    return world, generator


def init_app(windowed: bool):
    """Initialise a real Ursina application so entity and mesh costs are real."""
    from ursina import Ursina, application

    application.asset_folder = REPO_ROOT
    try:
        from panda3d.core import getModelPath

        getModelPath().append_path(str(REPO_ROOT))
    except Exception:
        pass
    return Ursina(
        window_type="onscreen" if windowed else "offscreen",
        development_mode=False,
        show_ursina_splash=False,
        title="VoxelWorld M16 attribution",
    )


def create_initial_entities(world) -> int:
    from chunk_entity import create_chunk_entity
    from coordinate_system import chunk_to_world_coords

    created = 0
    for (chunk_x, chunk_y, chunk_z), chunk in list(world.chunks.items()):
        entity = create_chunk_entity(
            chunk, chunk_to_world_coords(chunk_x, chunk_y, chunk_z), world=world
        )
        if entity is not None:
            created += 1
    return created


def _transparent_scan_current(chunk) -> bool:
    """Replica of the inline scan in ``chunk_entity.create_chunk_entity``.

    Kept literally identical (same iteration order, same early exits) so its
    timing is the timing of the real code path.
    """
    from block_data import is_block_transparent

    has_any_transparent_block = False
    for x in range(chunk.SIZE_X):
        for y in range(chunk.SIZE_Y):
            for z in range(chunk.SIZE_Z):
                if is_block_transparent(chunk.blocks[x, y, z]):
                    has_any_transparent_block = True
                    break
            if has_any_transparent_block:
                break
        if has_any_transparent_block:
            break
    return has_any_transparent_block


def time_phases(generator, world, counts, repeats) -> dict:
    """Unprofiled wall-clock time per phase of a cold load and one rebuild."""
    from block_data import is_block_transparent  # noqa: F401  (used by replica)
    from chunk_entity import _mesh_from_lists, create_chunk_entity
    from chunk_mesh import generate_chunk_mesh_split
    from coordinate_system import chunk_to_world_coords
    from texture_config import load_atlas_map
    from vegetation import generate_vegetation_for_chunk

    atlas = load_atlas_map()
    samples: dict[str, list[float]] = {}

    def record(name, started):
        samples.setdefault(name, []).append((pytime.perf_counter() - started) * 1000.0)

    for rep in range(repeats):
        origin = PHASE_ORIGIN + rep * BLOCK_SIZE
        for key in fresh_chunk_keys(counts, origin):
            chunk_x, chunk_y, chunk_z = key

            started = pytime.perf_counter()
            chunk = generator.generate_chunk_terrain(world, chunk_x, chunk_y, chunk_z)
            record("terrain_blocks", started)

            started = pytime.perf_counter()
            generate_vegetation_for_chunk(chunk, generator.seed)
            record("vegetation", started)

            started = pytime.perf_counter()
            vertices_o, triangles_o, uvs_o, vertices_t, triangles_t, uvs_t = (
                generate_chunk_mesh_split(chunk, world=world, atlas_map=atlas)
            )
            record("mesh_split", started)

            started = pytime.perf_counter()
            if vertices_o and triangles_o:
                _mesh_from_lists(vertices_o, triangles_o, uvs_o)
            if vertices_t and triangles_t:
                _mesh_from_lists(vertices_t, triangles_t, uvs_t)
            record("mesh_lists", started)

            started = pytime.perf_counter()
            _transparent_scan_current(chunk)
            record("transparent_scan", started)

            started = pytime.perf_counter()
            create_chunk_entity(
                chunk, chunk_to_world_coords(chunk_x, chunk_y, chunk_z), world=world
            )
            record("entity_full", started)

            started = pytime.perf_counter()
            chunk.refresh(world=world)
            record("refresh", started)

    summary = {}
    for name, values in samples.items():
        ordered = sorted(values)
        summary[name] = {
            "calls": len(values),
            "median_ms": statistics.median(values),
            "mean_ms": statistics.fmean(values),
            "p95_ms": ordered[min(len(ordered) - 1, int(0.95 * len(ordered)))],
            "min_ms": min(values),
            "max_ms": max(values),
            "total_ms": sum(values),
        }
    return summary


def time_highlight(repeats=40) -> dict:
    """Unprofiled cost of one highlight create/remove event.

    ``BlockHighlight.create_highlight`` builds 13 cube entities and
    ``remove_highlight`` destroys them. A camera swinging across a chunk
    boundary makes the raycast alternate between "something" and "nothing",
    so this cost lands on exactly the frames a rotating player produces.
    """
    from highlight import BlockHighlight

    highlight = BlockHighlight()
    create_samples = []
    remove_samples = []
    update_samples = []

    def position(index):
        return (float(index % 16), 8.0, float((index * 7) % 16))

    for index in range(repeats):
        started = pytime.perf_counter()
        highlight.create_highlight(position(index))
        create_samples.append((pytime.perf_counter() - started) * 1000.0)

        started = pytime.perf_counter()
        highlight.update_highlight(position(index + 1))
        update_samples.append((pytime.perf_counter() - started) * 1000.0)

        started = pytime.perf_counter()
        highlight.remove_highlight()
        remove_samples.append((pytime.perf_counter() - started) * 1000.0)

    def row(values):
        ordered = sorted(values)
        return {
            "calls": len(values),
            "median_ms": statistics.median(values),
            "mean_ms": statistics.fmean(values),
            "p95_ms": ordered[min(len(ordered) - 1, int(0.95 * len(ordered)))],
            "min_ms": min(values),
            "max_ms": max(values),
            "total_ms": sum(values),
        }

    return {
        "create_highlight": row(create_samples),
        "update_highlight": row(update_samples),
        "remove_highlight": row(remove_samples),
    }


def measure_cold_load_wall(generator, world, counts, repeats) -> dict:
    """Unprofiled wall-clock ms per cold ``World.load_chunk``, fresh chunks.

    Every repeat loads its own chunk block, so no repeat measures a registry hit
    (the mistake that made an earlier version of this script report 0.00 ms).
    """
    from chunk_entity import create_chunk_entity  # noqa: F401
    from coordinate_system import chunk_to_world_coords  # noqa: F401

    totals = []
    for rep in range(repeats):
        keys = fresh_chunk_keys(counts, WARMUP_ORIGIN + rep * BLOCK_SIZE)
        started = pytime.perf_counter()
        for key in keys:
            world.load_chunk(key[0], key[1], key[2], terrain_generator=generator)
        totals.append((pytime.perf_counter() - started) * 1000.0 / len(keys))
    return {
        "ms_per_call_median": statistics.median(totals),
        "ms_per_call_min": min(totals),
        "ms_per_call_max": max(totals),
        "samples": totals,
    }


def profile_calls(callable_factory, keys) -> dict:
    """Profile ``callable_factory(key)`` once per key under ``cProfile``."""
    profiler = cProfile.Profile()
    profiler.enable()
    started = pytime.perf_counter()
    for key in keys:
        callable_factory(key)
    profiled_total_ms = (pytime.perf_counter() - started) * 1000.0
    profiler.disable()
    return {
        "calls": len(keys),
        "profiled_total_ms": profiled_total_ms,
        "profiled_ms_per_call": profiled_total_ms / max(1, len(keys)),
        "stats": pstats.Stats(profiler),
    }


def top_functions(stats, count=22, sort_by="tottime_ms") -> list[dict]:
    """Return the heaviest functions as plain JSON-serialisable rows."""
    rows = []
    for (filename, lineno, name), (cc, nc, tt, ct, _callers) in stats.stats.items():
        rows.append(
            {
                "function": name,
                "location": f"{Path(filename).name}:{lineno}",
                "ncalls": nc,
                "tottime_ms": tt * 1000.0,
                "cumtime_ms": ct * 1000.0,
                "tottime_per_call_us": (tt * 1_000_000.0 / nc) if nc else 0.0,
            }
        )
    rows.sort(key=lambda row: row[sort_by], reverse=True)
    return rows[:count]


def report_profile(title, result, calls) -> None:
    print()
    print("=" * 100)
    print(f"{title}  ({calls} calls)")
    print(
        f"  under cProfile: {result['profiled_total_ms']:.1f} ms total, "
        f"{result['profiled_ms_per_call']:.2f} ms/call (inflated; compare shares)"
    )
    print("-" * 100)
    print(
        f"  {'function':<32} {'location':<22} {'ncalls':>7} "
        f"{'tottime_ms':>11} {'us/call':>9} {'cumtime_ms':>11}"
    )
    for row in top_functions(result["stats"]):
        print(
            f"  {row['function'][:32]:<32} {row['location'][:22]:<22} "
            f"{row['ncalls']:>7} {row['tottime_ms']:>11.2f} "
            f"{row['tottime_per_call_us']:>9.1f} {row['cumtime_ms']:>11.2f}"
        )


def report_phases(phases, load_wall) -> None:
    print()
    print("=" * 100)
    print("PHASE TIMINGS (unprofiled wall clock, ms per chunk)")
    print("-" * 100)
    print(
        f"  {'phase':<20} {'calls':>6} {'median':>9} {'mean':>9} {'p95':>9} "
        f"{'min':>9} {'max':>9}"
    )
    for name, row in phases.items():
        print(
            f"  {name:<20} {row['calls']:>6} {row['median_ms']:>9.2f} "
            f"{row['mean_ms']:>9.2f} {row['p95_ms']:>9.2f} {row['min_ms']:>9.2f} "
            f"{row['max_ms']:>9.2f}"
        )
    print(
        f"  {'COLD LOAD TOTAL':<20} {load_wall.get('calls', 0):>6} "
        f"{load_wall['ms_per_call_median']:>9.2f} "
        f"{'':>9} {'':>9} {load_wall['ms_per_call_min']:>9.2f} "
        f"{load_wall['ms_per_call_max']:>9.2f}"
    )


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="M16 attribution profiler")
    parser.add_argument("--count", type=int, default=8, help="chunks per repeat")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--windowed", action="store_true")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    args = parser.parse_args(argv)

    world, generator = build_world()
    init_app(args.windowed)
    initial_entities = create_initial_entities(world)
    print(f"initial chunks: {len(world.chunks)}  initial entities: {initial_entities}")

    # --- phase timings (the numbers to trust for magnitude) --------------
    phases = time_phases(generator, world, args.count, args.repeats)
    load_wall = measure_cold_load_wall(generator, world, args.count, args.repeats)
    load_wall["calls"] = args.count * args.repeats
    report_phases(phases, load_wall)

    highlight = time_highlight()
    print()
    print("=" * 100)
    print("HIGHLIGHT EVENT (unprofiled wall clock, ms per event)")
    print("-" * 100)
    for name, row in highlight.items():
        print(
            f"  {name:<20} {row['calls']:>6} median={row['median_ms']:>7.3f} "
            f"mean={row['mean_ms']:>7.3f} p95={row['p95_ms']:>7.3f} "
            f"max={row['max_ms']:>7.3f}"
        )

    # --- cProfile shares (which functions, not how big) ------------------
    load_keys = fresh_chunk_keys(args.count, PROFILE_ORIGIN)
    load_result = profile_calls(
        lambda key: world.load_chunk(key[0], key[1], key[2], terrain_generator=generator),
        load_keys,
    )
    report_profile("COLD CHUNK LOAD  World.load_chunk (cProfile shares)", load_result, len(load_keys))

    rebuild_keys = list(world.chunks)[: args.count]
    rebuild_result = profile_calls(
        lambda key: world.chunks[key].refresh(world=world), rebuild_keys
    )
    report_profile("MESH REBUILD  Chunk.refresh (cProfile shares)", rebuild_result, len(rebuild_keys))

    payload = {
        "meta": {
            "windowed": bool(args.windowed),
            "count": args.count,
            "repeats": args.repeats,
            "note": (
                "phase timings are unprofiled wall clock and are the magnitudes to "
                "trust; the cProfile sections are for attributing those magnitudes "
                "to functions and inflate absolute times."
            ),
        },
        "phases": phases,
        "highlight": highlight,
        "cold_load_wall": load_wall,
        "cold_load_profile": {
            "profiled_total_ms": load_result["profiled_total_ms"],
            "profiled_ms_per_call": load_result["profiled_ms_per_call"],
            "top_tottime": top_functions(load_result["stats"], count=30),
            "top_cumtime": top_functions(
                load_result["stats"], count=20, sort_by="cumtime_ms"
            ),
        },
        "mesh_rebuild_profile": {
            "profiled_total_ms": rebuild_result["profiled_total_ms"],
            "profiled_ms_per_call": rebuild_result["profiled_ms_per_call"],
            "top_tottime": top_functions(rebuild_result["stats"], count=30),
            "top_cumtime": top_functions(
                rebuild_result["stats"], count=20, sort_by="cumtime_ms"
            ),
        },
    }
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print()
    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
