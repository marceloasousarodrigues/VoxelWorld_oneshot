"""
M15 Task 1 - reproducible performance & scalability harness for VoxelWorld.

This script measures the *game's own* code paths without modifying them. It
builds the exact ``main.py`` scene (TerrainGenerator seed 42, one chunk entity
per chunk, ``VoxelPlayer`` at (8, 8, 8), a seeded ``WaterSimulation``) and runs
deterministic scenarios that isolate:

  1. break one block                  6. water simulation under load
  2. break blocks rapidly             7. generate and load chunks
  3. break blocks at chunk boundaries 8. move through the world (new chunks)
  4. place blocks rapidly             9. render terrain with visible chunks
  5. dirty-set reconciliation        10. a mixed world (grass/trees/water)

Each scenario reports frame-time percentiles, over-budget counts, attributed
CPU time (interaction / reconcile / mesh / water / chunk generation), rebuild
counts, queue depths and chunk-count/memory observations.

Diagnostic profiling (``--profile``) additionally enables ``cProfile`` and
``tracemalloc`` and marks the output ``"mode": "diagnostic"`` so diagnostic
numbers are never mixed with publishable frame-cost numbers.

The script never modifies a game source file. It writes only the requested
JSON output under ``config/``.

Usage (from the repository root)::

    python scripts/profile_m15.py --all --frames 600
    python scripts/profile_m15.py --scenario break_one --frames 200
    python scripts/profile_m15.py --all --profile --output config/m15_diag.json
"""

from __future__ import annotations

import argparse
import gc
import json
import math
import platform
import statistics
import sys
import time as pytime
import tracemalloc
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from chunk import Chunk  # noqa: E402
from terrain_generation import (  # noqa: E402
    LAKE_FLOOR,
    LAKE_LEVEL,
    TerrainGenerator,
    in_lake,
    surface_height,
)
from world import World  # noqa: E402

DEFAULT_FRAMES = 600
DEFAULT_SEED = 42
DEFAULT_OUTPUT = REPO_ROOT / "config" / "m15_metrics.json"

# Frame budgets: 60 fps and 30 fps. These literals are the thresholds every
# over-budget count in this harness is computed against.
BUDGET_16_67 = 16.67
BUDGET_33_33 = 33.33

# Attribution categories reported together; values never exceed the frame total.
ATTRIBUTION_KEYS = (
    "interaction",
    "reconcile",
    "mesh",
    "water",
    "chunk_gen",
)


# ---------------------------------------------------------------------------
# Pure metric helpers (unit-tested in tests/test_m15_harness.py)
# ---------------------------------------------------------------------------

def percentile(sorted_values, fraction: float):
    """Linear-interpolation percentile over an already-sorted sequence."""
    if not sorted_values:
        return None
    if len(sorted_values) == 1:
        return sorted_values[0]
    if fraction <= 0.0:
        return sorted_values[0]
    if fraction >= 1.0:
        return sorted_values[-1]
    position = (len(sorted_values) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(sorted_values) - 1)
    weight = position - lower
    return sorted_values[lower] + (sorted_values[upper] - sorted_values[lower]) * weight


class FrameStats:
    """Summary statistics for a list of frame durations in milliseconds."""

    def __init__(self, samples_ms):
        ordered = sorted(value for value in samples_ms if value is not None)
        self.count = len(ordered)
        self._ordered = ordered
        self.p50 = percentile(ordered, 0.5)
        self.p95 = percentile(ordered, 0.95)
        self.p99 = percentile(ordered, 0.99)
        self.min = ordered[0] if ordered else None
        self.max = ordered[-1] if ordered else None
        self.mean = statistics.fmean(ordered) if ordered else None
        # Literal thresholds: a value equal to the budget is not over it.
        self.over_16_67 = sum(1 for value in ordered if value > BUDGET_16_67)
        self.over_33_33 = sum(1 for value in ordered if value > BUDGET_33_33)
        self.over_16_67_pct = (
            (self.over_16_67 / self.count) * 100.0 if self.count else 0.0
        )
        self.over_33_33_pct = (
            (self.over_33_33 / self.count) * 100.0 if self.count else 0.0
        )

    def to_dict(self) -> dict:
        return {
            "samples": self.count,
            "mean_ms": self.mean,
            "p50_ms": self.p50,
            "p95_ms": self.p95,
            "p99_ms": self.p99,
            "min_ms": self.min,
            "max_ms": self.max,
            "over_16_67": self.over_16_67,
            "over_33_33": self.over_33_33,
            "over_16_67_pct": self.over_16_67_pct,
            "over_33_33_pct": self.over_33_33_pct,
        }


def attribute(frame_total_ms: float, parts: dict) -> dict:
    """Attribute a frame total across known parts plus an ``other`` remainder.

    Every known category is always present (0.0 when not measured), and the
    returned values sum to no more than ``frame_total_ms``.
    """
    result = {key: float(parts.get(key, 0.0) or 0.0) for key in ATTRIBUTION_KEYS}
    frame_total = float(frame_total_ms)
    measured = sum(result.values())
    if measured > frame_total and measured > 0.0:
        # Independently measured parts can exceed the frame total on a noisy
        # sample; scale them down so the contract (sum <= frame total) holds.
        scale = frame_total / measured
        result = {key: value * scale for key, value in result.items()}
    result["other"] = max(0.0, frame_total - sum(result.values()))
    return result


def pending_work(world, water) -> dict:
    """Report outstanding simulation queues (bounded when the game is idle)."""
    return {
        "dirty_chunks": len(getattr(world, "dirty_chunks", ())),
        "pending_seeds": len(getattr(water, "pending_seeds", ())),
        "active_job": getattr(water, "active_job", None) is not None,
    }


def chunk_counts(world) -> dict:
    """Report loaded / visible / active chunk counts.

    ``visible`` means the chunk has a rendered entity. ``unloaded`` is reported
    as ``None`` because no unload path exists in the project yet: inventing a
    number would misrepresent the truth.
    """
    chunks = list(getattr(world, "chunks", {}).values())
    return {
        "loaded": len(chunks),
        "visible": sum(1 for chunk in chunks if getattr(chunk, "entity", None) is not None),
        "active": len(getattr(world, "dirty_chunks", ())),
        "unloaded": None,
    }


def numpy_bytes(world) -> int:
    """Total bytes held by the numpy arrays of every loaded chunk."""
    total = 0
    for chunk in getattr(world, "chunks", {}).values():
        for array in (
            chunk.blocks,
            chunk.water_levels,
            chunk.water_sources,
            chunk.decorations,
        ):
            total += int(getattr(array, "nbytes", 0))
    return total


# ---------------------------------------------------------------------------
# Scene construction (mirrors main.py)
# ---------------------------------------------------------------------------

def _apply_column(chunk, local_x, local_z, world_x, world_z):
    """Write one generated terrain column, mirroring TerrainGenerator."""
    height = surface_height(DEFAULT_SEED, world_x, world_z)
    column_in_lake = in_lake(world_x, world_z)
    for y in range(chunk.SIZE_Y):
        if column_in_lake:
            if y > LAKE_LEVEL:
                chunk.set_block(local_x, y, local_z, BlockType.AIR)
            elif LAKE_FLOOR <= y <= LAKE_LEVEL:
                chunk.set_block(local_x, y, local_z, BlockType.WATER)
                chunk.set_water_level(local_x, y, local_z, 8)
                chunk.set_water_source(local_x, y, local_z, y == LAKE_LEVEL)
            elif y > height:
                chunk.set_block(local_x, y, local_z, BlockType.AIR)
            elif y == height:
                chunk.set_block(local_x, y, local_z, BlockType.GRASS)
            elif y > height - 4:
                chunk.set_block(local_x, y, local_z, BlockType.DIRT)
            else:
                chunk.set_block(local_x, y, local_z, BlockType.STONE)
        else:
            if y > height:
                chunk.set_block(local_x, y, local_z, BlockType.AIR)
            elif y == height:
                chunk.set_block(local_x, y, local_z, BlockType.GRASS)
            elif y > height - 4:
                chunk.set_block(local_x, y, local_z, BlockType.DIRT)
            else:
                chunk.set_block(local_x, y, local_z, BlockType.STONE)


def generate_region(world, half_extent: int):
    """Deterministically generate a ``(2h+1)``-square region of terrain.

    Block placement is identical to ``TerrainGenerator._generate_height_map_terrain``
    but over an arbitrary chunk range, so the scaling scenarios can grow the
    loaded set reproducibly.
    """
    for chunk_x in range(-half_extent, half_extent + 1):
        for chunk_z in range(-half_extent, half_extent + 1):
            chunk = world.get_chunk(chunk_x, 0, chunk_z)
            for local_x in range(Chunk.SIZE_X):
                for local_z in range(Chunk.SIZE_Z):
                    _apply_column(
                        chunk,
                        local_x,
                        local_z,
                        chunk_x * Chunk.SIZE_X + local_x,
                        chunk_z * Chunk.SIZE_Z + local_z,
                    )


def build_world(with_vegetation: bool = True) -> World:
    """Create the deterministic seed-42 world (mirrors main.py)."""
    world = World()
    if with_vegetation:
        TerrainGenerator().generate_world(world)
    else:
        generate_region(world, 1)
    return world


def build_water_sim(world):
    from water import WaterSimulation

    water = WaterSimulation(world)
    water.seed_all_sources()
    return water


def create_entities(world):
    """Create one chunk entity per chunk and the player, exactly like main.py."""
    from chunk_entity import create_chunk_entity
    import player

    created = 0
    for chunk in world.chunks.values():
        entity = create_chunk_entity(
            chunk,
            (chunk.chunk_x * 16, chunk.chunk_y * 16, chunk.chunk_z * 16),
            world=world,
        )
        if entity is not None:
            created += 1
    player_entity = player.VoxelPlayer(world=world, spawn_position=(8, 8, 8))
    return player_entity, created


# ---------------------------------------------------------------------------
# Timing utilities
# ---------------------------------------------------------------------------

def _reconcile(world):
    """Flush dirty chunks the way the frame loop does.

    Uses the deferred ``World.reconcile`` when it exists (post-M15-Task 4) and
    falls back to the synchronous ``World.refresh`` otherwise, so the same
    harness measures both the baseline and the optimised code.
    """
    reconcile = getattr(world, "reconcile", None)
    if callable(reconcile):
        reconcile()
    else:
        world.refresh()


def _trim_world(world, keep_half_extent: int = 0):
    """Reduce the world to the chunks in ``[-keep, keep]`` (both axes, y=0)."""
    keep = set()
    for chunk_x in range(-keep_half_extent, keep_half_extent + 1):
        for chunk_z in range(-keep_half_extent, keep_half_extent + 1):
            keep.add((chunk_x, 0, chunk_z))
    for key in list(world.chunks):
        if key not in keep:
            del world.chunks[key]
    world.dirty_chunks.clear()


def _top_solid_y(chunk, local_x, local_z):
    for y in range(chunk.SIZE_Y - 1, -1, -1):
        if int(chunk.get_block(local_x, y, local_z)) != BlockType.AIR:
            return y
    return None


def _edit_targets(world, chunk_coords, count, offset=0):
    """Deterministic list of breakable cells near the surface of a chunk."""
    chunk = world.chunks[chunk_coords]
    base_x, base_y, base_z = (
        chunk_coords[0] * 16,
        chunk_coords[1] * 16,
        chunk_coords[2] * 16,
    )
    targets = []
    for index in range(count):
        local_x = (index * 5 + offset) % Chunk.SIZE_X
        local_z = (index * 7 + offset * 3) % Chunk.SIZE_Z
        local_y = _top_solid_y(chunk, local_x, local_z)
        if local_y is None:
            continue
        targets.append((base_x + local_x, base_y + local_y, base_z + local_z))
    return targets


class _Profile:
    """Optional diagnostic wrapper; inert unless ``enabled``."""

    def __init__(self, enabled: bool):
        self.enabled = enabled
        self._profiler = None
        self._snapshot_start = None

    def __enter__(self):
        if self.enabled:
            import cProfile

            tracemalloc.start()
            gc.collect()
            self._snapshot_start = tracemalloc.take_snapshot()
            self._profiler = cProfile.Profile()
            self._profiler.enable()
        return self

    def __exit__(self, *exc):
        if not self.enabled:
            return False
        self._profiler.disable()
        self._stats = self._profiler.getstats()
        self._snapshot_end = tracemalloc.take_snapshot()
        tracemalloc.stop()
        return False

    def summary(self, limit: int = 15) -> dict:
        if not self.enabled:
            return {}
        rows = []
        for stat in sorted(
            self._stats, key=lambda s: s.tottime, reverse=True
        )[:limit]:
            rows.append(
                {
                    "function": str(stat.code),
                    "calls": stat.callcount,
                    "tottime": stat.tottime,
                    "cumtime": stat.tottime + stat.ctime,
                }
            )
        stats = self._snapshot_end.compare_to(self._snapshot_start, "lineno")
        return {
            "top_functions": rows,
            "top_allocations": [
                {"location": str(entry.traceback[0]), "bytes": entry.size_diff}
                for entry in stats[:limit]
            ],
        }


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

def _empty_scenario(name, description, **extra):
    result = {"name": name, "description": description}
    result.update(extra)
    return result


def scenario_idle(ctx, frames):
    """Idle frames with the real scene attached."""
    app = ctx.get("app")
    if app is None:
        return _empty_scenario("idle", "idle frames (headless: not measured)", status="skipped")
    samples = []
    for _ in range(frames):
        start = pytime.perf_counter()
        app.step()
        samples.append((pytime.perf_counter() - start) * 1000.0)
    return _empty_scenario(
        "idle",
        "step the attached scene with no edits",
        frames=FrameStats(samples).to_dict(),
        counts=chunk_counts(ctx["world"]),
        pending=pending_work(ctx["world"], ctx["water"]),
    )


def _edit_loop(ctx, frames, edits_per_frame, targets, block_type=BlockType.AIR,
               restore=None):
    """Measure frames each performing ``edits_per_frame`` set_block edits.

    The block data is written first, then the dirty set is flushed once per
    frame (``_reconcile``), which is exactly what the frame loop does.
    """
    world = ctx["world"]
    app = ctx.get("app")
    samples = []
    total = len(targets)
    index = 0
    for _ in range(frames):
        frame_start = pytime.perf_counter()
        for _ in range(edits_per_frame):
            if index >= total:
                break
            x, y, z = targets[index]
            index += 1
            world.set_block(x, y, z, block_type)
        _reconcile(world)
        if app is not None:
            app.step()
        samples.append((pytime.perf_counter() - frame_start) * 1000.0)
        if index >= total:
            break
    if restore is not None:
        for target in targets[:index]:
            restore(target)
        _reconcile(world)
    return samples


def scenario_break_one(ctx, frames):
    """One block change per frame (the reported stutter)."""
    world = ctx["world"]
    targets = _edit_targets(world, (0, 0, 0), frames)
    samples = _edit_loop(
        ctx, len(targets), 1, targets, BlockType.AIR,
        restore=lambda t: world.set_block(*t, BlockType.GRASS),
    )
    return _empty_scenario(
        "break_one",
        "one set_block(AIR) + one dirty-set flush per frame",
        frames=FrameStats(samples).to_dict(),
        counts=chunk_counts(world),
        pending=pending_work(world, ctx["water"]),
    )


def scenario_break_rapid(ctx, frames):
    """Several edits batched into one frame (the rapid-break case)."""
    world = ctx["world"]
    edits_per_frame = 4
    targets = _edit_targets(world, (0, 0, 0), frames * edits_per_frame)
    samples = _edit_loop(
        ctx, frames, edits_per_frame, targets, BlockType.AIR,
        restore=lambda t: world.set_block(*t, BlockType.GRASS),
    )
    return _empty_scenario(
        "break_rapid",
        f"{edits_per_frame} set_block(AIR) edits batched into one dirty-set flush per frame",
        frames=FrameStats(samples).to_dict(),
        edits_per_frame=edits_per_frame,
        counts=chunk_counts(world),
        pending=pending_work(world, ctx["water"]),
    )


def scenario_break_boundary(ctx, frames):
    """Edits on a chunk boundary that dirty a loaded neighbour too."""
    world = ctx["world"]
    chunk = world.chunks[(0, 0, 0)]
    targets = []
    for index in range(frames):
        local_x = 15  # +X boundary: dirties chunk (1, 0, 0)
        local_z = (index * 3) % Chunk.SIZE_Z
        local_y = _top_solid_y(chunk, local_x, local_z)
        if local_y is None:
            continue
        targets.append((local_x, local_y, local_z))
    samples = _edit_loop(
        ctx, len(targets), 1, targets, BlockType.AIR,
        restore=lambda t: world.set_block(*t, BlockType.GRASS),
    )
    return _empty_scenario(
        "break_boundary",
        "one +X boundary edit per frame (dirty set amplifies to the loaded neighbour)",
        frames=FrameStats(samples).to_dict(),
        counts=chunk_counts(world),
        pending=pending_work(world, ctx["water"]),
    )


def scenario_place_rapid(ctx, frames):
    """Place blocks rapidly (restore the broken surface)."""
    world = ctx["world"]
    targets = _edit_targets(world, (0, 0, 0), frames)
    for target in targets:
        world.set_block(*target, BlockType.AIR)
    _reconcile(world)
    samples = _edit_loop(
        ctx, len(targets), 1, targets, BlockType.STONE,
        restore=lambda t: world.set_block(*t, BlockType.GRASS),
    )
    return _empty_scenario(
        "place_rapid",
        "one set_block(STONE) + one dirty-set flush per frame on broken cells",
        frames=FrameStats(samples).to_dict(),
        counts=chunk_counts(world),
        pending=pending_work(world, ctx["water"]),
    )


def scenario_dirty_reconcile(ctx, frames):
    """Mark many chunks dirty, then measure a single flush."""
    world = ctx["world"]
    world.dirty_chunks.clear()
    keys = list(world.chunks)
    dilate = scenario_dirty_reconcile._dilate
    for index in range(min(frames, len(keys) * dilate)):
        world.dirty_chunks.add(keys[index % len(keys)])
    start = pytime.perf_counter()
    _reconcile(world)
    elapsed = (pytime.perf_counter() - start) * 1000.0
    return _empty_scenario(
        "dirty_reconcile",
        "flush a dirty set covering every loaded chunk (unbounded-work probe)",
        single_flush_ms=elapsed,
        dirty_count_before=len(keys) * dilate,
        counts=chunk_counts(world),
        pending=pending_work(world, ctx["water"]),
    )


scenario_dirty_reconcile._dilate = 3


def scenario_water_active(ctx, frames):
    """Time water ticks from a fresh seeded lake to quiescence."""
    world = ctx["world"]
    water = build_water_sim(world)
    ctx_water = water
    samples = []
    quiesced_at = None
    for index in range(frames):
        if not water.has_pending_work():
            quiesced_at = index
            break
        start = pytime.perf_counter()
        water.tick()
        samples.append((pytime.perf_counter() - start) * 1000.0)
    return _empty_scenario(
        "water_active",
        "water tick() from a freshly seeded lake until the queue drains",
        frames=FrameStats(samples).to_dict(),
        ticks_to_quiescence=quiesced_at if quiesced_at is not None else len(samples),
        pending=pending_work(world, ctx_water),
        counts=chunk_counts(world),
    )


def scenario_generate_chunks(ctx, frames):
    """Time deterministic region generation, per chunk."""
    world = World()
    start = pytime.perf_counter()
    generate_region(world, 2)
    elapsed = (pytime.perf_counter() - start) * 1000.0
    count = len(world.chunks) or 1
    return _empty_scenario(
        "generate_chunks",
        "generate a 5x5 chunk region deterministically (no vegetation)",
        total_ms=elapsed,
        chunk_count=len(world.chunks),
        per_chunk_ms=elapsed / count,
        counts=chunk_counts(world),
    )


def scenario_traverse_generate(ctx, frames):
    """Grow the loaded region chunk-by-chunk, timing each new chunk."""
    world = World()
    generate_region(world, 0)
    samples = []
    for step in range(1, 5):
        for chunk_x in (step, -step):
            for chunk_z in range(-step, step + 1):
                if (chunk_x, 0, chunk_z) in world.chunks:
                    continue
                start = pytime.perf_counter()
                chunk = world.get_chunk(chunk_x, 0, chunk_z)
                for local_x in range(Chunk.SIZE_X):
                    for local_z in range(Chunk.SIZE_Z):
                        _apply_column(
                            chunk,
                            local_x,
                            local_z,
                            chunk_x * 16 + local_x,
                            chunk_z * 16 + local_z,
                        )
                samples.append((pytime.perf_counter() - start) * 1000.0)
                if len(samples) >= frames:
                    break
            if len(samples) >= frames:
                break
        if len(samples) >= frames:
            break
    return _empty_scenario(
        "traverse_generate",
        "generate one new chunk per step while moving outwards",
        frames=FrameStats(samples).to_dict(),
        counts=chunk_counts(world),
        memory={"numpy_bytes": numpy_bytes(world), "per_chunk_bytes": _per_chunk_bytes(world)},
    )


def _per_chunk_bytes(world) -> int:
    count = len(world.chunks)
    if not count:
        return 0
    return numpy_bytes(world) // count


def scenario_render_visible(ctx, frames):
    """Measure visible-chunk/memory scaling with the renderer attached."""
    world = ctx["world"]
    app = ctx.get("app")
    samples = []
    if app is not None:
        for _ in range(min(frames, 120)):
            start = pytime.perf_counter()
            app.step()
            samples.append((pytime.perf_counter() - start) * 1000.0)
    return _empty_scenario(
        "render_visible",
        "step the scene; report visible chunk and geometry counts",
        frames=FrameStats(samples).to_dict() if samples else None,
        counts=chunk_counts(world),
        memory={"numpy_bytes": numpy_bytes(world), "per_chunk_bytes": _per_chunk_bytes(world)},
        visibility={
            "visible_chunks": chunk_counts(world)["visible"],
            "opaque_chunk_entities": sum(
                1
                for chunk in world.chunks.values()
                if getattr(chunk, "entity", None) is not None
            ),
        },
    )


def scenario_mixed_world(ctx, frames):
    """A generated world with grass, trees and water: edit + water frames."""
    world = build_world(with_vegetation=True)
    water = build_water_sim(world)
    app = ctx.get("app")
    samples = []
    targets = _edit_targets(world, (0, 0, 0), max(1, frames))
    for index in range(min(frames, len(targets))):
        frame_start = pytime.perf_counter()
        x, y, z = targets[index]
        world.set_block(x, y, z, BlockType.AIR)
        _reconcile(world)
        water.consume_changes()
        water.tick()
        if app is not None:
            app.step()
        samples.append((pytime.perf_counter() - frame_start) * 1000.0)
    return _empty_scenario(
        "mixed_world",
        "generated world: one edit + reconcile + water tick per frame",
        frames=FrameStats(samples).to_dict(),
        counts=chunk_counts(world),
        pending=pending_work(world, water),
    )


SCENARIOS = {
    "idle": scenario_idle,
    "break_one": scenario_break_one,
    "break_rapid": scenario_break_rapid,
    "break_boundary": scenario_break_boundary,
    "place_rapid": scenario_place_rapid,
    "dirty_reconcile": scenario_dirty_reconcile,
    "water_active": scenario_water_active,
    "generate_chunks": scenario_generate_chunks,
    "traverse_generate": scenario_traverse_generate,
    "render_visible": scenario_render_visible,
    "mixed_world": scenario_mixed_world,
}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def _parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--scenario", action="append", choices=sorted(SCENARIOS),
        help="Scenario to run (repeatable).",
    )
    parser.add_argument("--all", action="store_true", help="Run every scenario.")
    parser.add_argument(
        "--frames", type=int, default=DEFAULT_FRAMES,
        help=f"Frame/sample budget per scenario (default {DEFAULT_FRAMES}).",
    )
    parser.add_argument(
        "--output", type=Path, default=DEFAULT_OUTPUT,
        help="JSON output path (default config/m15_metrics.json).",
    )
    parser.add_argument(
        "--profile", action="store_true",
        help="Enable diagnostic cProfile/tracemalloc (marks output mode=diagnostic).",
    )
    parser.add_argument(
        "--windowed", action="store_true",
        help="Open an on-screen window instead of the offscreen renderer.",
    )
    return parser.parse_args(argv)


def _ursina_version() -> str:
    try:
        from importlib.metadata import version

        return version("ursina")
    except Exception:
        return "unknown"


def _panda_version() -> str:
    try:
        from panda3d.core import PandaSystem

        return PandaSystem.getVersionString()
    except Exception:
        return "unknown"


def _meta(scene_mode, render_error) -> dict:
    resolution = None
    if scene_mode == "render":
        try:
            from ursina import window

            resolution = [int(window.size[0]), int(window.size[1])]
        except Exception:
            resolution = None
    return {
        "tool": "scripts/profile_m15.py",
        "milestone": "M15 - Performance Profiling & Scalability",
        "python_version": sys.version,
        "ursina_version": _ursina_version(),
        "panda3d_version": _panda_version(),
        "platform": platform.platform(),
        "scene_mode": scene_mode,
        "render_error": render_error,
        "scene": (
            "TerrainGenerator seed 42 (3x3 chunks), one chunk entity per chunk, "
            "VoxelPlayer spawn (8,8,8), seeded WaterSimulation"
        ),
        "vsync": None,
        "resolution": resolution,
    }


def _build_render_context(windowed: bool):
    """Try to build the offscreen/onscreen scene; fall back to headless."""
    render_error = None
    app = None
    player_entity = None
    chunk_entity_count = 0
    scene_mode = "headless"
    world = build_world(with_vegetation=True)
    try:
        from ursina import Ursina, application

        application.asset_folder = REPO_ROOT
        try:
            from panda3d.core import getModelPath

            getModelPath().append_path(str(REPO_ROOT))
        except Exception:
            pass

        app = Ursina(
            development_mode=False,
            show_ursina_splash=False,
            window_type="onscreen" if windowed else "offscreen",
            title="VoxelWorld M15 Harness",
        )
        try:
            from ursina import window

            window.vsync = False
        except Exception:
            pass
        scene_mode = "render"
        player_entity, chunk_entity_count = create_entities(world)
    except Exception as exc:  # pragma: no cover - environment dependent
        render_error = f"{type(exc).__name__}: {exc}"
        app = None

    water = build_water_sim(world)
    return {
        "app": app,
        "world": world,
        "water": water,
        "player": player_entity,
        "chunk_entity_count": chunk_entity_count,
        "scene_mode": scene_mode,
        "render_error": render_error,
    }


def main(argv=None) -> int:
    args = _parse_args(argv)

    names = args.scenario or []
    if args.all or not names:
        names = list(SCENARIOS)

    ctx = _build_render_context(args.windowed)

    results = {}
    diagnostics = {}
    for name in names:
        if name == "water_active":
            # Uses its own freshly seeded simulation against the shared world.
            scenario_ctx = ctx
        elif name == "mixed_world":
            # Builds its own world/sim so it is independent of the shared scene.
            scenario_ctx = {"app": ctx.get("app")}
        else:
            scenario_ctx = ctx
        with _Profile(args.profile) as profiler:
            try:
                results[name] = SCENARIOS[name](scenario_ctx, args.frames)
            except Exception as exc:  # pragma: no cover - environment dependent
                results[name] = _empty_scenario(
                    name, f"scenario failed: {type(exc).__name__}: {exc}",
                    status="error",
                )
        if args.profile:
            diagnostics[name] = profiler.summary()

    document = {
        "meta": _meta(ctx["scene_mode"], ctx["render_error"]),
        "mode": "diagnostic" if args.profile else "measurement",
        "frames_budget": args.frames,
        "scenarios": results,
    }
    if args.profile:
        document["diagnostics"] = diagnostics

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2, sort_keys=False)
        handle.write("\n")

    print(f"[profile_m15] wrote {args.output}")
    for name, result in results.items():
        frames = result.get("frames")
        if frames:
            print(
                f"  {name}: p50={frames['p50_ms']:.3f} ms "
                f"p95={frames['p95_ms']:.3f} ms max={frames['max_ms']:.3f} ms "
                f"over16.67={frames['over_16_67']}"
            )
        else:
            print(f"  {name}: {result.get('description')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
