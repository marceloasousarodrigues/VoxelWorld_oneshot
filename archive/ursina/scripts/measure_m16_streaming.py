"""
M16 runtime verification and measurement harness.

Builds the real ``main.py`` scene (TerrainGenerator seed 42, one entity per
chunk, ``VoxelPlayer`` at (8, 8, 8), a seeded ``WaterSimulation`` and the M16
``ChunkStreamer``) and drives it through the same per-frame sequence
``main.py:update`` uses:

    world.reconcile(); streamer.update(position); water.consume_changes()/tick()

It then:

* walks the player across chunk boundaries in the positive and negative
  directions and records the active set against the configured distances;
* audits the world for duplicate chunks or duplicated rendered entities;
* proves re-entry restores a player edit after the chunk unloaded;
* times streaming frames against idle frames (p50/p95/p99/max and over-budget
  counts) and records per-chunk memory and overlay sizes.

It never modifies a game source file and never starts a real interactive
window; it writes only ``config/m16_streaming_metrics.json``.

Usage (from the repository root)::

    python scripts/measure_m16_streaming.py
    python scripts/measure_m16_streaming.py --output config/m16_metrics.json
"""

from __future__ import annotations

import argparse
import json
import platform
import statistics
import sys
import time as pytime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from chunk_streaming import ChunkStreamer  # noqa: E402
from terrain_generation import (  # noqa: E402
    TerrainGenerator,
    in_lake,
    surface_height,
)
from world import World  # noqa: E402

DEFAULT_OUTPUT = REPO_ROOT / "config" / "m16_streaming_metrics.json"
BUDGET_16_67 = 16.67
BUDGET_33_33 = 33.33


# ---------------------------------------------------------------------------
# Metrics helpers
# ---------------------------------------------------------------------------

def percentile(sorted_values, fraction):
    """Linear-interpolation percentile of an ascending list."""
    if not sorted_values:
        return 0.0
    if len(sorted_values) == 1:
        return float(sorted_values[0])
    position = (len(sorted_values) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(sorted_values) - 1)
    weight = position - lower
    return sorted_values[lower] * (1 - weight) + sorted_values[upper] * weight


def frame_stats(samples_ms):
    """Frame-time percentiles and over-budget counts for one phase."""
    ordered = sorted(float(value) for value in samples_ms)
    if not ordered:
        return {
            "frames": 0,
            "p50": 0.0,
            "p95": 0.0,
            "p99": 0.0,
            "max": 0.0,
            "over_16_67": 0,
            "over_33_33": 0,
            "mean": 0.0,
        }
    return {
        "frames": len(ordered),
        "p50": percentile(ordered, 0.50),
        "p95": percentile(ordered, 0.95),
        "p99": percentile(ordered, 0.99),
        "max": ordered[-1],
        "mean": statistics.fmean(ordered),
        "over_16_67": sum(1 for value in ordered if value > BUDGET_16_67),
        "over_33_33": sum(1 for value in ordered if value > BUDGET_33_33),
    }


def numpy_bytes(world) -> int:
    """Bytes held by the numpy arrays of every loaded chunk."""
    return sum(
        int(array.nbytes)
        for chunk in world.chunks.values()
        for array in (
            chunk.blocks,
            chunk.water_levels,
            chunk.water_sources,
            chunk.decorations,
        )
    )


def overlay_sizes(world) -> dict:
    return {
        "block_overrides": len(world.block_overrides),
        "decoration_overrides": len(world.decoration_overrides),
    }


def entity_audit(world, streamer) -> dict:
    """Check for duplicate chunks and duplicated rendered entities."""
    ids = [
        id(chunk.entity)
        for chunk in world.chunks.values()
        if getattr(chunk, "entity", None) is not None
    ]
    rendered_keys = set(streamer.rendered)
    return {
        "loaded_chunks": len(world.chunks),
        "unique_chunk_keys": len(set(world.chunks)),
        "rendered_registry": len(streamer.rendered),
        "rendered_subset_of_loaded": rendered_keys <= set(world.chunks),
        "entities_with_geometry": len(ids),
        "unique_entities": len(set(ids)),
        "no_duplicate_entities": len(set(ids)) == len(ids),
        "rendered_missing_entities": [
            key for key, entity in streamer.rendered.items() if entity is None
        ],
    }


# ---------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------

class Context:
    def __init__(self):
        self.app = None
        self.scene_mode = "headless"
        self.render_error = None
        self.world = None
        self.generator = TerrainGenerator()
        self.water = None
        self.streamer = None
        self.player = None
        self.entity_count = 0
        self._last_position = (8.0, 8.0, 8.0)

    # -- frame -----------------------------------------------------------
    def step(self, position):
        """Run one frame exactly like main.py:update, returning its cost in ms."""
        self._last_position = position
        started = pytime.perf_counter()
        self.world.reconcile()
        self.streamer.update(position)
        self.water.consume_changes()
        if not self.world.dirty_chunks:
            self.water.tick()
        return (pytime.perf_counter() - started) * 1000.0


def build_context(windowed=False) -> Context:
    ctx = Context()
    ctx.world = World()
    ctx.generator.generate_world(ctx.world)

    from chunk_entity import create_chunk_entity

    try:
        from ursina import Ursina, application

        application.asset_folder = REPO_ROOT
        try:
            from panda3d.core import getModelPath

            getModelPath().append_path(str(REPO_ROOT))
        except Exception:
            pass

        ctx.app = Ursina(
            development_mode=False,
            show_ursina_splash=False,
            window_type="onscreen" if windowed else "offscreen",
            title="VoxelWorld M16 Harness",
        )
        try:
            from ursina import window

            window.vsync = False
        except Exception:
            pass
        ctx.scene_mode = "render"
    except Exception as exc:  # pragma: no cover - environment dependent
        ctx.render_error = f"{type(exc).__name__}: {exc}"
        ctx.app = None

    for chunk in ctx.world.chunks.values():
        entity = create_chunk_entity(
            chunk,
            (chunk.chunk_x * 16, chunk.chunk_y * 16, chunk.chunk_z * 16),
            world=ctx.world,
        )
        if entity is not None:
            ctx.entity_count += 1

    try:
        import player

        ctx.player = player.VoxelPlayer(world=ctx.world, spawn_position=(8, 8, 8))
    except Exception as exc:  # pragma: no cover
        ctx.render_error = (ctx.render_error or "") + f" player:{exc}"

    from water import WaterSimulation

    ctx.water = WaterSimulation(ctx.world)
    ctx.water.seed_all_sources()
    ctx.streamer = ChunkStreamer(
        ctx.world, terrain_generator=ctx.generator, water_sim=ctx.water
    )
    return ctx


def walk(ctx, targets, step=1.0, samples=None):
    """Move through ``targets`` in 1-block increments, running a frame per step."""
    x, z = ctx._last_position[0], ctx._last_position[2]
    for target in targets:
        target_x, target_z = target[0], target[-1]
        while abs(x - target_x) > 1e-6 or abs(z - target_z) > 1e-6:
            dx = max(-step, min(step, target_x - x))
            dz = max(-step, min(step, target_z - z))
            x += dx
            z += dz
            cost = ctx.step((x, 8.0, z))
            if samples is not None:
                samples.append(cost)


def settle(ctx, position, limit=200):
    """Run frames until streaming converges at ``position``."""
    for _ in range(limit):
        ctx.step(position)
        if not ctx.streamer.has_pending_work() and not ctx.world.dirty_chunks:
            return True
    return False


def find_grass_cell(ctx, chunk_key):
    chunk = ctx.world.chunks.get(chunk_key)
    if chunk is None:
        return None
    base_x = chunk.chunk_x * 16
    base_z = chunk.chunk_z * 16
    for local_x in range(16):
        for local_z in range(16):
            gx, gz = base_x + local_x, base_z + local_z
            if in_lake(gx, gz):
                continue
            surface = surface_height(ctx.generator.seed, gx, gz)
            if surface + 1 >= 16:
                continue
            if chunk.get_block(local_x, surface, local_z) == BlockType.GRASS:
                return (gx, surface, gz)
    return None


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

def measure(output_path, windowed=False):
    ctx = build_context(windowed=windowed)
    results = {
        "meta": {
            "milestone": "M16",
            "scene": "TerrainGenerator seed 42 (3x3), one entity per chunk, "
            "VoxelPlayer at (8, 8, 8), streamed with config/world_config.json",
            "platform": platform.platform(),
            "python": platform.python_version(),
            "ursina": _version("ursina"),
            "panda3d": _version("panda3d"),
            "numpy": _version("numpy"),
            "scene_mode": ctx.scene_mode,
            "render_error": ctx.render_error,
            "startup_entity_count": ctx.entity_count,
            "streaming_distance": ctx.streamer.streaming_distance,
            "retention_distance": ctx.streamer.retention_distance,
            "max_loads_per_frame": ctx.streamer.max_loads_per_frame,
            "max_unloads_per_frame": ctx.streamer.max_unloads_per_frame,
        },
        "limitations": [
            "Offscreen/headless CPU timing only; no GPU cost or draw-call attribution.",
            "The agent environment cannot inspect rendered pixels, so no on-screen "
            "visual confirmation is claimed.",
            "One chunk's generation + combined-mesh build is the irreducible "
            "streaming unit and can exceed a frame budget; only the load COUNT is "
            "bounded per frame.",
        ],
    }

    # Idle frames once converged at the spawn.
    settle(ctx, (8.0, 8.0, 8.0))
    idle = [ctx.step((8.0, 8.0, 8.0)) for _ in range(60)]
    results["idle_frames_ms"] = frame_stats(idle)

    # Explore across +X and +Z boundaries.
    positive = []
    walk(ctx, [(8.0, 8.0, 8.0), (72.0, 8.0, 8.0), (72.0, 8.0, 72.0)], samples=positive)
    settle(ctx, (72.0, 8.0, 72.0))
    results["explore_positive_frames_ms"] = frame_stats(positive)

    # Explore back across the origin into negative coordinates.
    negative = []
    walk(ctx, [(-72.0, 8.0, -72.0)], samples=negative)
    settle(ctx, (-72.0, 8.0, -72.0))
    results["explore_negative_frames_ms"] = frame_stats(negative)

    # The active set must match the configured distances once converged.
    position = (-72.0, 8.0, -72.0)
    desired = ctx.streamer.desired_chunk_keys(position)
    retained = ctx.streamer.retained_chunk_keys(position)
    loaded = set(ctx.world.chunks)
    results["active_set"] = {
        "position": position,
        "player_chunk": ctx.streamer.player_chunk_coords(position),
        "desired": len(desired),
        "retained": len(retained),
        "loaded": len(loaded),
        # The loaded set must cover the streaming radius and stay inside the
        # retention radius (M16: the active set follows both distances).
        "contains_desired": desired <= loaded,
        "within_retention": loaded <= retained,
        "all_ground_layer": all(key[1] == 0 for key in loaded),
    }

    # Re-entry restores a player edit after the chunk has unloaded.
    reentry = {"performed": False}
    target_chunk = ctx.streamer.player_chunk_coords(position)
    cell = find_grass_cell(ctx, (target_chunk[0], 0, target_chunk[1]))
    if cell is not None:
        world_x, world_y, world_z = cell
        ctx.world.set_block(world_x, world_y, world_z, BlockType.AIR)
        ctx.step(position)  # reconcile the edit frame

        # Walk far away so the edited chunk leaves the retention radius.
        far = (position[0] + 40 * 16, position[2] + 40 * 16)
        walk(ctx, [far], samples=None)
        settle(ctx, (far[0], 8.0, far[1]))
        unloaded = (target_chunk[0], 0, target_chunk[1]) not in ctx.world.chunks

        walk(ctx, [position], samples=None)
        settle(ctx, position)
        restored = ctx.world.get_block(world_x, world_y, world_z) == BlockType.AIR
        present = (target_chunk[0], 0, target_chunk[1]) in ctx.world.chunks
        reentry = {
            "performed": True,
            "cell": list(cell),
            "chunk": list(target_chunk),
            "chunk_unloaded": unloaded,
            "chunk_present_again": present,
            "edit_restored": restored,
        }
    results["reentry"] = reentry

    results["entity_audit"] = entity_audit(ctx.world, ctx.streamer)
    results["overlay"] = overlay_sizes(ctx.world)
    results["memory"] = {
        "numpy_bytes": numpy_bytes(ctx.world),
        "numpy_bytes_per_chunk": (
            numpy_bytes(ctx.world) // len(ctx.world.chunks)
            if ctx.world.chunks
            else 0
        ),
        "loaded_chunks": len(ctx.world.chunks),
    }

    return results


def _version(distribution):
    """Version of an installed distribution, read from package metadata.

    Ursina exposes no ``__version__`` attribute, so an attribute lookup recorded
    "unknown" for it even though it was installed; ``importlib.metadata``
    reports the installed distribution version without importing the package.
    """
    try:
        from importlib.metadata import version

        return version(distribution)
    except Exception:
        return "unknown"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="VoxelWorld M16 streaming harness")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--windowed", action="store_true")
    args = parser.parse_args(argv)

    results = measure(Path(args.output), windowed=args.windowed)
    output_path = Path(args.output)
    output_path.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results, indent=2))
    print(f"\nWrote {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
