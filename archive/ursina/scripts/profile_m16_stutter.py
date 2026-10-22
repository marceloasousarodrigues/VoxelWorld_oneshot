"""
M16 stutter investigation & profiling harness (diagnostic, opt-in).

This is a *measurement* tool. It builds the exact ``main.py`` scene, opens a real
window (vsync disabled so frame times reflect work rather than the 60 Hz cap) and
drives the six gameplay scenarios from the stutter investigation:

  1. stand_still        - no input
  2. rotate             - fast camera rotation, standing still
  3. walk_loaded        - walking inside an already-loaded region (no chunk loads)
  4. cross_boundary      - walking across chunk boundaries at normal speed
  5. explore            - walking continuously through unexplored terrain
  6. boundary_repeat    - crossing the same boundary back and forth

The walk scenarios run until a target number of chunk-boundary crossings (or
direction turns) is reached, so they exercise the intended behaviour regardless of
the machine's frame rate, and every scenario starts from the same converged
condition (the desired 7x7 set at spawn, water quiescent).

For every frame it records the total frame cost and the cost of each stage
(reconcile, streamer, water, render+player) plus counters from low-overhead
wrappers around terrain generation, entity creation, mesh rebuilds, chunk
load/unload and highlight creation. That correlation is what attributes a spike
to an operation.

``--skip-water/--skip-reconcile/--skip-streamer/--skip-render`` produce ablation
runs for attribution.

It writes ``config/m16_stutter_baseline.json`` (or the requested path) and never
modifies a game source file.

Usage (from the repository root)::

    python scripts/profile_m16_stutter.py --all --windowed
    python scripts/profile_m16_stutter.py --scenario cross_boundary --windowed
    python scripts/profile_m16_stutter.py --all --windowed --skip-water --output config/x.json
"""

from __future__ import annotations

import argparse
import gc
import json
import platform
import statistics
import sys
import time as pytime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

# Disable vsync before the engine starts, so measured frame time is the cost of
# the frame's work rather than the refresh-rate cap.
from panda3d.core import loadPrcFileData  # noqa: E402

loadPrcFileData("", "sync-video 0")

from chunk_streaming import ChunkStreamer  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from world import World  # noqa: E402

THRESHOLDS = (16.67, 33.33, 50.0)
DEFAULT_OUTPUT = REPO_ROOT / "config" / "m16_stutter_baseline.json"

# Scenario specs. ``stop`` is (kind, target): "frames" stops after N frames,
# "crossings" after the player's chunk coordinates change N times, "turns" after
# N direction reversals. ``cap`` bounds the run regardless.
SCENARIOS = {
    "stand_still": {"stop": ("frames", 240), "cap": 240, "action": "noop"},
    "rotate": {"stop": ("frames", 240), "cap": 240, "action": "rotate"},
    "walk_loaded": {"stop": ("frames", 240), "cap": 240, "action": "walk_loaded"},
    "cross_boundary": {"stop": ("crossings", 3), "cap": 9000, "action": "teleport_forward"},
    "explore": {"stop": ("crossings", 6), "cap": 16000, "action": "teleport_forward"},
    "boundary_repeat": {"stop": ("turns", 4), "cap": 7000, "action": "teleport_repeat"},
}


# ---------------------------------------------------------------------------
# Low-overhead instrumentation
# ---------------------------------------------------------------------------

class _Counters:
    """Per-frame accumulators filled by the wrapper functions."""

    def __init__(self):
        self.reset()

    def reset(self):
        self.terrain_ms = 0.0
        self.terrain_calls = 0
        self.entity_ms = 0.0
        self.entity_calls = 0
        self.mesh_ms = 0.0
        self.mesh_calls = 0
        self.load_ms = 0.0
        self.load_calls = 0
        self.unload_ms = 0.0
        self.unload_calls = 0
        self.highlight_ms = 0.0
        self.highlight_calls = 0


COUNTERS = _Counters()


def _instrument(target, name, ms_attr, calls_attr=None):
    """Wrap ``target.name`` so its wall time accumulates into COUNTERS."""
    original = getattr(target, name)

    def wrapper(*args, **kwargs):
        started = pytime.perf_counter()
        try:
            return original(*args, **kwargs)
        finally:
            ms = (pytime.perf_counter() - started) * 1000.0
            setattr(COUNTERS, ms_attr, getattr(COUNTERS, ms_attr) + ms)
            if calls_attr is not None:
                setattr(COUNTERS, calls_attr, getattr(COUNTERS, calls_attr) + 1)

    setattr(target, name, wrapper)


class _GcMonitor:
    """Accumulate garbage-collector pause time via ``gc.callbacks``.

    The callback fires at the start and stop of every collection, so the
    difference is the wall time the interpreter spent collecting. This is how a
    stall that is really a GC pause gets attributed to GC instead of to whatever
    function happened to be running when it fired.
    """

    def __init__(self):
        self.reset()

    def reset(self):
        self.pause_ms = 0.0
        self.collections = 0
        self.by_gen = {0: 0, 1: 0, 2: 0}
        self._start = None

    def __call__(self, phase, info):
        if phase == "start":
            self._start = pytime.perf_counter()
            return
        if self._start is not None:
            self.pause_ms += (pytime.perf_counter() - self._start) * 1000.0
            self._start = None
        self.collections += 1
        generation = info.get("generation", 0) if isinstance(info, dict) else 0
        self.by_gen[generation] = self.by_gen.get(generation, 0) + 1


GC = _GcMonitor()


def install_instrumentation():
    import chunk_entity
    from chunk import Chunk
    from highlight import BlockHighlight

    _instrument(World, "load_chunk", "load_ms", "load_calls")
    _instrument(World, "unload_chunk", "unload_ms", "unload_calls")
    _instrument(TerrainGenerator, "generate_chunk", "terrain_ms", "terrain_calls")
    _instrument(Chunk, "refresh", "mesh_ms", "mesh_calls")
    _instrument(chunk_entity, "create_chunk_entity", "entity_ms", "entity_calls")
    _instrument(BlockHighlight, "create_highlight", "highlight_ms", "highlight_calls")

    if GC not in gc.callbacks:
        gc.callbacks.append(GC)


# ---------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------

class Context:
    def __init__(self):
        self.app = None
        self.world = None
        self.generator = None
        self.water = None
        self.streamer = None
        self.player = None
        self.scene_mode = "headless"
        self.render_error = None
        self.initial_entities = 0
        self.start_position = (8.0, 8.0, 8.0)
        # Set by main(): the shipped GC policy is applied unless disabled, so the
        # default measurement is the configuration the game actually runs.
        self.no_gc_tuning = False
        self.gc_tuning_applied = False


def build_context(windowed: bool, no_gc_tuning: bool = False) -> Context:
    ctx = Context()
    ctx.generator = TerrainGenerator()
    ctx.world = World()
    ctx.generator.generate_world(ctx.world)

    try:
        from ursina import Ursina, application, mouse

        application.asset_folder = REPO_ROOT
        try:
            from panda3d.core import getModelPath

            getModelPath().append_path(str(REPO_ROOT))
        except Exception:
            pass

        ctx.app = Ursina(
            window_type="onscreen" if windowed else "offscreen",
            development_mode=False,
            show_ursina_splash=False,
            title="VoxelWorld M16 stutter profile",
        )
        # Keep the profiler deterministic and the real cursor free: this harness
        # drives the camera itself instead of reading raw mouse motion.
        try:
            mouse.locked = False
            mouse.visible = True
        except Exception:
            pass
        ctx.scene_mode = "windowed" if windowed else "offscreen"
    except Exception as exc:  # pragma: no cover - environment dependent
        ctx.render_error = f"{type(exc).__name__}: {exc}"
        ctx.app = None

    from chunk_entity import create_chunk_entity

    for chunk in ctx.world.chunks.values():
        entity = create_chunk_entity(
            chunk,
            (chunk.chunk_x * 16, chunk.chunk_y * 16, chunk.chunk_z * 16),
            world=ctx.world,
        )
        if entity is not None:
            ctx.initial_entities += 1

    from water import WaterSimulation

    ctx.water = WaterSimulation(ctx.world)
    ctx.water.seed_all_sources()
    ctx.streamer = ChunkStreamer(
        ctx.world, terrain_generator=ctx.generator, water_sim=ctx.water
    )

    import player as player_module

    ctx.player = player_module.VoxelPlayer(ctx.world, spawn_position=(8, 8, 8))

    # Apply the shipped cyclic-GC policy here, after the whole startup graph
    # exists, exactly where main.py applies it. Without this the harness would
    # measure a configuration the game never runs: unfrozen, so the collector's
    # full pass traces the startup graph and costs 60-105 ms instead of ~15 ms.
    if not no_gc_tuning:
        import gc_tuning

        ctx.gc_tuning_applied = bool(gc_tuning.apply())
    return ctx


def _idle(ctx: Context) -> None:
    """One settle frame: advance the same systems main.py does, unmeasured."""
    ctx.world.reconcile()
    ctx.streamer.update((ctx.player.x, ctx.player.y, ctx.player.z))
    ctx.water.consume_changes()
    ctx.water.tick()
    if ctx.app is not None:
        ctx.app.step()


def _settle(ctx: Context, position, cap=900) -> bool:
    """Run frames until streaming, mesh and water work have all drained."""
    ctx.player.keys.update({"w": False, "a": False, "s": False, "d": False})
    ctx.player.velocity_y = 0.0
    ctx.player.position = position
    for _ in range(cap):
        _idle(ctx)
        if (
            not ctx.streamer.has_pending_work()
            and not ctx.world.dirty_chunks
            and not ctx.water.has_pending_work()
        ):
            return True
    return False


def reset_world(ctx: Context):
    """Return the world to the same converged starting condition."""
    for key in list(ctx.world.chunks):
        ctx.world.unload_chunk(*key)
    ctx.streamer.rendered.clear()
    ctx.streamer._last_player_chunk = None
    ctx.water.pending_seeds.clear()
    ctx.water.pending_seeds_set.clear()
    ctx.water.active_job = None
    ctx.player.rotation_y = 0.0
    ctx.player.camera_pitch = 0.0
    converged = _settle(ctx, ctx.start_position)
    return {
        "converged": converged,
        "loaded": len(ctx.world.chunks),
        "water_pending": ctx.water.has_pending_work(),
    }


# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------

def run_frame(ctx: Context, options) -> dict:
    COUNTERS.reset()
    gc_pause_before = GC.pause_ms
    gc_collections_before = GC.collections
    position = (ctx.player.x, ctx.player.y, ctx.player.z)
    dirty_before = len(ctx.world.dirty_chunks)
    started = pytime.perf_counter()

    mark = pytime.perf_counter()
    if not options["skip_reconcile"]:
        ctx.world.reconcile()
    reconcile_ms = (pytime.perf_counter() - mark) * 1000.0

    mark = pytime.perf_counter()
    if options["skip_streamer"]:
        stats = {"loaded": 0, "unloaded": 0}
    else:
        stats = ctx.streamer.update(position)
    streamer_ms = (pytime.perf_counter() - mark) * 1000.0

    mark = pytime.perf_counter()
    if not options["skip_water"]:
        ctx.water.consume_changes()
        ctx.water.tick()
    water_ms = (pytime.perf_counter() - mark) * 1000.0

    mark = pytime.perf_counter()
    if ctx.app is not None and not options["skip_render"]:
        ctx.app.step()
    render_ms = (pytime.perf_counter() - mark) * 1000.0

    total_ms = (pytime.perf_counter() - started) * 1000.0
    return {
        "total_ms": total_ms,
        "reconcile_ms": reconcile_ms,
        "streamer_ms": streamer_ms,
        "water_ms": water_ms,
        "render_ms": render_ms,
        "terrain_ms": COUNTERS.terrain_ms,
        "terrain_calls": COUNTERS.terrain_calls,
        "entity_ms": COUNTERS.entity_ms,
        "entity_calls": COUNTERS.entity_calls,
        "mesh_ms": COUNTERS.mesh_ms,
        "mesh_calls": COUNTERS.mesh_calls,
        "load_ms": COUNTERS.load_ms,
        "load_calls": COUNTERS.load_calls,
        "unload_ms": COUNTERS.unload_ms,
        "unload_calls": COUNTERS.unload_calls,
        "highlight_ms": COUNTERS.highlight_ms,
        "highlight_calls": COUNTERS.highlight_calls,
        "loads": stats["loaded"],
        "unloads": stats["unloaded"],
        "dirty_before": dirty_before,
        "loaded_chunks": len(ctx.world.chunks),
        "water_pending": bool(ctx.water.has_pending_work()),
        "gc_pause_ms": GC.pause_ms - gc_pause_before,
        "gc_collections": GC.collections - gc_collections_before,
    }


# ---------------------------------------------------------------------------
# Scenario actions
# ---------------------------------------------------------------------------

def _maybe_jump(ctx, state):
    """Jump when forward progress stalls, the way a player clears a step.

    Without this the profiler's player can wedge against a one-block terrain
    rise (there is no auto-step), which silently turns a movement scenario into
    an idle one.
    """
    position = (ctx.player.x, ctx.player.z)
    last = state.get("last_pos")
    if last is not None and abs(position[0] - last[0]) < 0.02 and abs(position[1] - last[1]) < 0.02:
        state["stuck"] = state.get("stuck", 0) + 1
    else:
        state["stuck"] = 0
    state["last_pos"] = position
    if state.get("stuck", 0) >= 4 and ctx.player.on_ground:
        ctx.player.jump()
        state["stuck"] = 0


def _action_noop():
    def action(ctx, index, state):
        ctx.player.keys.update({"w": False, "a": False, "s": False, "d": False})
    return action


def _action_rotate(frames_per_swing=12):
    def action(ctx, index, state):
        ctx.player.rotation_y += 18.0
        ctx.player.camera_pitch = 30.0 if (index // frames_per_swing) % 2 == 0 else -30.0
    return action


def _action_walk_loaded():
    """Oscillate a few blocks inside the already-loaded region (no loads)."""

    def action(ctx, index, state):
        _maybe_jump(ctx, state)
        forward = (index % 20) < 10
        ctx.player.keys["w"] = forward
        ctx.player.keys["s"] = not forward
        ctx.player.rotation_y = 0.0
    return action


def _teleport_step(ctx, state, direction):
    """Advance the player at walking speed, following the terrain surface.

    The walk scenarios must guarantee repeated chunk-boundary crossings to
    exercise streaming. Real physics cannot: there is no auto-step, so a 2-block
    terrain rise wedges the player permanently. This drives the same distance per
    unit time as a walking player (``speed * dt``) while teleporting, so the cost
    measured is the streaming cost, not terrain traversal. ``walk_loaded`` keeps
    real physics for the collision/ground-detection cost.
    """
    try:
        from ursina import time as ursina_time

        dt = float(ursina_time.dt)
    except Exception:
        dt = 1.0 / 60.0
    dt = max(1e-4, min(0.1, dt))

    ctx.player.keys.update({"w": False, "a": False, "s": False, "d": False})
    ctx.player.z += direction * ctx.player.speed * dt
    ctx.player.velocity_y = 0.0
    ground = ctx.player.find_ground_y()
    if ground is not None:
        ctx.player.y = ground
    state["direction"] = direction


def _action_teleport_forward():
    def action(ctx, index, state):
        _teleport_step(ctx, state, 1.0)
    return action


def _action_teleport_repeat():
    """Walk forward, reversing direction each time a new chunk is entered."""

    def action(ctx, index, state):
        if state.get("flip_at", -1) != state["crossings"]:
            state["flip_at"] = state["crossings"]
            if state["crossings"] > 0:
                state["turns"] += 1
        direction = 1.0 if state["turns"] % 2 == 0 else -1.0
        _teleport_step(ctx, state, direction)
    return action


ACTIONS = {
    "noop": _action_noop,
    "rotate": _action_rotate,
    "walk_loaded": _action_walk_loaded,
    "teleport_forward": _action_teleport_forward,
    "teleport_repeat": _action_teleport_repeat,
}


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------

def _percentile(ordered, fraction):
    if not ordered:
        return 0.0
    if len(ordered) == 1:
        return float(ordered[0])
    position = (len(ordered) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    weight = position - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def summarise(frames, wall_seconds):
    totals = sorted(frame["total_ms"] for frame in frames)
    over = {
        threshold: sum(1 for value in totals if value > threshold)
        for threshold in THRESHOLDS
    }
    return {
        "frames": len(totals),
        "wall_seconds": wall_seconds,
        "fps_throughput": (len(totals) / wall_seconds) if wall_seconds else 0.0,
        "total_ms": {
            "mean": statistics.fmean(totals) if totals else 0.0,
            "p50": _percentile(totals, 0.50),
            "p95": _percentile(totals, 0.95),
            "p99": _percentile(totals, 0.99),
            "max": totals[-1] if totals else 0.0,
        },
        "over": {str(threshold): over[threshold] for threshold in THRESHOLDS},
        "components_ms_sum": {
            key: sum(frame[key] for frame in frames)
            for key in (
                "reconcile_ms",
                "streamer_ms",
                "water_ms",
                "render_ms",
                "terrain_ms",
                "entity_ms",
                "mesh_ms",
                "highlight_ms",
                "load_ms",
                "unload_ms",
            )
        },
        "counts_sum": {
            key: sum(frame[key] for frame in frames)
            for key in (
                "loads",
                "unloads",
                "mesh_calls",
                "terrain_calls",
                "entity_calls",
                "highlight_calls",
                "load_calls",
                "unload_calls",
            )
        },
        "loaded_chunks_mean": (
            statistics.fmean(frame["loaded_chunks"] for frame in frames)
            if frames
            else 0.0
        ),
        "loaded_chunks_max": max((frame["loaded_chunks"] for frame in frames), default=0),
        "dirty_before_mean": (
            statistics.fmean(frame["dirty_before"] for frame in frames) if frames else 0.0
        ),
        "water_pending_frames": sum(1 for frame in frames if frame["water_pending"]),
        "frames_with_load": sum(1 for frame in frames if frame["loads"] > 0),
        "frames_with_unload": sum(1 for frame in frames if frame["unloads"] > 0),
        "frames_with_mesh": sum(1 for frame in frames if frame["mesh_calls"] > 0),
        "frames_with_highlight": sum(
            1 for frame in frames if frame["highlight_calls"] > 0
        ),
        "gc_pause_ms_sum": sum(frame["gc_pause_ms"] for frame in frames),
        "gc_collections_sum": sum(frame["gc_collections"] for frame in frames),
        "frames_with_gc": sum(1 for frame in frames if frame["gc_collections"] > 0),
        "gc_by_gen": dict(GC.by_gen),
    }


def _top_spikes(frames, count=8):
    ordered = sorted(frames, key=lambda frame: frame["total_ms"], reverse=True)
    return [
        {
            "total_ms": round(frame["total_ms"], 2),
            "reconcile_ms": round(frame["reconcile_ms"], 2),
            "streamer_ms": round(frame["streamer_ms"], 2),
            "water_ms": round(frame["water_ms"], 2),
            "render_ms": round(frame["render_ms"], 2),
            "loads": frame["loads"],
            "unloads": frame["unloads"],
            "mesh_calls": frame["mesh_calls"],
            "terrain_ms": round(frame["terrain_ms"], 2),
            "entity_ms": round(frame["entity_ms"], 2),
            "mesh_ms": round(frame["mesh_ms"], 2),
            "highlight_calls": frame["highlight_calls"],
            "gc_pause_ms": round(frame["gc_pause_ms"], 2),
            "gc_collections": frame["gc_collections"],
            "dirty_before": frame["dirty_before"],
        }
        for frame in ordered[:count]
    ]


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def _should_stop(spec, state, index):
    kind, target = spec["stop"]
    if kind == "frames":
        return (index + 1) >= target
    if kind == "crossings":
        return state["crossings"] >= target
    if kind == "turns":
        return state["turns"] >= target
    return False


def run_scenario(ctx: Context, name, options):
    spec = SCENARIOS[name]
    action = ACTIONS[spec["action"]]()
    reset = reset_world(ctx)
    GC.reset()

    player_chunk = ctx.streamer.player_chunk_coords(
        (ctx.player.x, ctx.player.y, ctx.player.z)
    )
    state = {"crossings": 0, "turns": 0, "last_chunk": player_chunk, "flip_at": -1}
    start_position = (ctx.player.x, ctx.player.y, ctx.player.z)

    samples = []
    started = pytime.perf_counter()
    for index in range(spec["cap"]):
        action(ctx, index, state)
        samples.append(run_frame(ctx, options))

        chunk = ctx.streamer.player_chunk_coords(
            (ctx.player.x, ctx.player.y, ctx.player.z)
        )
        if chunk != state["last_chunk"]:
            state["crossings"] += 1
            state["last_chunk"] = chunk

        if _should_stop(spec, state, index):
            break
    wall = pytime.perf_counter() - started

    result = summarise(samples, wall)
    result["reset"] = reset
    result["crossings"] = state["crossings"]
    result["turns"] = state["turns"]
    result["distance_travelled"] = round(
        abs(ctx.player.z - start_position[2]) + abs(ctx.player.x - start_position[0]),
        2,
    )
    result["final_player_position"] = [round(ctx.player.x, 2), round(ctx.player.y, 2), round(ctx.player.z, 2)]
    result["final_loaded_chunks"] = len(ctx.world.chunks)
    result["top_spikes"] = _top_spikes(samples)
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="VoxelWorld M16 stutter profiler")
    parser.add_argument("--scenario", action="append", default=None)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--windowed", action="store_true", default=False)
    parser.add_argument("--offscreen", action="store_true", default=False)
    parser.add_argument("--frames", type=int, default=None, help="override frames/crossing caps (smoke test)")
    parser.add_argument("--skip-water", action="store_true")
    parser.add_argument("--skip-reconcile", action="store_true")
    parser.add_argument("--skip-streamer", action="store_true")
    parser.add_argument("--skip-render", action="store_true")
    parser.add_argument("--gc-disable", action="store_true", help="experiment: disable cyclic GC")
    parser.add_argument(
        "--no-gc-tuning",
        action="store_true",
        help="experiment: skip the shipped gc_tuning policy (unfrozen control)",
    )
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--label", default="baseline")
    args = parser.parse_args(argv)

    windowed = args.windowed and not args.offscreen
    names = args.scenario or list(SCENARIOS)
    if args.frames is not None:
        for name in names:
            SCENARIOS[name] = {
                **SCENARIOS[name],
                "stop": ("frames", args.frames),
                "cap": args.frames,
            }

    options = {
        "skip_water": args.skip_water,
        "skip_reconcile": args.skip_reconcile,
        "skip_streamer": args.skip_streamer,
        "skip_render": args.skip_render,
    }

    install_instrumentation()
    if args.no_gc_tuning:
        import gc_tuning

        gc_tuning.reset()

    if args.gc_disable:
        gc.disable()
    ctx = build_context(windowed=windowed, no_gc_tuning=args.no_gc_tuning)

    results = {
        "meta": {
            "milestone": "M16-stutter",
            "label": args.label,
            "scene_mode": ctx.scene_mode,
            "render_error": ctx.render_error,
            "windowed": windowed,
            "vsync": False,
            "gc_tuning": ctx.gc_tuning_applied,
            "ablation": {key: value for key, value in options.items() if value},
            "initial_entities": ctx.initial_entities,
            "streaming_distance": ctx.streamer.streaming_distance,
            "retention_distance": ctx.streamer.retention_distance,
            "max_loads_per_frame": ctx.streamer.max_loads_per_frame,
            "max_unloads_per_frame": ctx.streamer.max_unloads_per_frame,
            "player_speed": ctx.player.speed,
            "platform": platform.platform(),
            "python": platform.python_version(),
            "ursina": _version("ursina"),
            "panda3d": _version("panda3d"),
            "numpy": _version("numpy"),
        },
        "limitations": [
            "Frame time is CPU-side wall time around the frame's work plus the "
            "engine's per-frame step; the GPU runs asynchronously with vsync off, "
            "so pure GPU time is not captured. fps_throughput is the effective "
            "(GPU-inclusive) rate over the scenario.",
            "This profiler drives the camera itself; it does not read raw mouse "
            "motion, so it measures the cost of the resulting rotation, not the "
            "input device path.",
        ],
        "scenarios": {},
    }

    for name in names:
        result = run_scenario(ctx, name, options)
        results["scenarios"][name] = result
        print(
            f"{name:16s} frames={result['frames']:5d} cross={result['crossings']:2d} "
            f"dist={result['distance_travelled']:6.1f} "
            f"p50={result['total_ms']['p50']:6.2f} p95={result['total_ms']['p95']:6.2f} "
            f"p99={result['total_ms']['p99']:7.2f} max={result['total_ms']['max']:7.2f} "
            f">16.67={result['over']['16.67']:4d} >33.33={result['over']['33.33']:4d} "
            f"loads={result['counts_sum']['loads']:3d} unloads={result['counts_sum']['unloads']:3d} "
            f"gc={result['gc_pause_ms_sum']:7.1f}ms/{result['gc_collections_sum']}x",
            flush=True,
        )

    output_path = Path(args.output)
    output_path.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(f"\nWrote {output_path}")
    return 0


def _version(distribution):
    """Version of an installed distribution, read from package metadata.

    Ursina exposes no ``__version__`` attribute, so an attribute lookup recorded
    "unavailable" for it even though it was installed; ``importlib.metadata``
    reports the installed distribution version without importing the package.
    """
    try:
        from importlib.metadata import version

        return version(distribution)
    except Exception:
        return "unavailable"


if __name__ == "__main__":
    raise SystemExit(main())
