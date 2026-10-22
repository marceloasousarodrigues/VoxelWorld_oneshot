"""
M9 Task 1 - performance baseline & texture-asset measurement for VoxelWorld.

This script measures, using only existing game code, a reproducible baseline:

  1. FPS / frame timing over a benchmark duration (default 30 s, vsync-limited).
  2. ``World.refresh()`` duration for a fixed break/regenerate workload.
  3. A texture-memory estimate for the legacy atlas and the M9 texture manifest.

It runs the exact same scene as ``main.py`` (``TerrainGenerator`` seed 42, the
9 generated chunks, chunk entities and a ``VoxelPlayer`` spawned at (8, 8, 8))
with a warm-up period, then writes the measured values to
``config/baseline_metrics.json``.

The script never modifies any game source file.  It is safe to re-run; later
milestone tasks compare their post-integration numbers against the JSON this
script produces.

Usage (from the repository root)::

    python scripts/measure_baseline.py
    python scripts/measure_baseline.py --duration 5 --warmup 1
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import statistics
import sys
import time as pytime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from world import World  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402


DEFAULT_DURATION = 30.0
DEFAULT_WARMUP = 2.0
DEFAULT_OUTPUT = REPO_ROOT / "config" / "baseline_metrics.json"
MANIFEST_PATH = REPO_ROOT / "config" / "texture_manifest.json"
LEGACY_ATLAS = REPO_ROOT / "voxel_textures" / "blocks.png"

# Deterministic refresh workload: 16 near-surface columns in chunk (0, 0, 0).
WORKLOAD_COLUMNS = tuple((x, z) for x in (2, 6, 10, 14) for z in (2, 6, 10, 14))


# ---------------------------------------------------------------------------
# Scene construction (mirrors main.py)
# ---------------------------------------------------------------------------

def build_world() -> World:
    """Create the deterministic TerrainGenerator world (seed 42)."""
    world = World()
    TerrainGenerator().generate_world(world)
    return world


def create_scene_entities(world: World):
    """Create one chunk entity per chunk and the player, exactly like main.py."""
    from chunk_entity import create_chunk_entity
    import player

    created = 0
    for chunk in world.chunks.values():
        entity = create_chunk_entity(
            chunk,
            (
                chunk.chunk_x * 16,
                chunk.chunk_y * 16,
                chunk.chunk_z * 16,
            ),
        )
        if entity is not None:
            created += 1

    player_entity = player.VoxelPlayer(world=world, spawn_position=(8, 8, 8))
    return player_entity, created


# ---------------------------------------------------------------------------
# FPS / frame-timing measurement
# ---------------------------------------------------------------------------

def warm_up(app, seconds: float) -> int:
    """Step the app for ``seconds`` to stabilise shaders, window and physics."""
    frames = 0
    start = pytime.perf_counter()
    while pytime.perf_counter() - start < seconds:
        app.step()
        frames += 1
    return frames


def measure_fps(app, duration: float) -> dict:
    """Step the app for ``duration`` seconds and gather frame timing stats."""
    from ursina import time as utime

    frame_times = []
    start = pytime.perf_counter()
    while True:
        app.step()
        dt = getattr(utime, "dt_unscaled", None)
        if dt is None:
            dt = utime.dt
        frame_times.append(dt)
        if pytime.perf_counter() - start >= duration:
            break
    elapsed = pytime.perf_counter() - start

    samples = [dt * 1000.0 for dt in frame_times if dt and dt > 0]
    samples.sort()
    if not samples:
        return {
            "duration_seconds": elapsed,
            "frames": len(frame_times),
            "average_fps": None,
            "frame_time_ms": {},
        }

    mean_ms = statistics.fmean(samples)
    return {
        "duration_seconds": elapsed,
        "frames": len(frame_times),
        "measured_frames": len(samples),
        "average_fps": len(samples) / elapsed,
        "average_fps_from_frame_time": 1000.0 / mean_ms if mean_ms else None,
        "frame_time_ms": {
            "mean": mean_ms,
            "median": statistics.median(samples),
            "min": samples[0],
            "max": samples[-1],
            "p5": _percentile(samples, 0.05),
            "p95": _percentile(samples, 0.95),
        },
    }


def _percentile(sorted_values, fraction: float):
    if not sorted_values:
        return None
    if len(sorted_values) == 1:
        return sorted_values[0]
    position = (len(sorted_values) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(sorted_values) - 1)
    weight = position - lower
    return sorted_values[lower] + (sorted_values[upper] - sorted_values[lower]) * weight


# ---------------------------------------------------------------------------
# World.refresh() workload
# ---------------------------------------------------------------------------

def _top_solid_y(chunk, local_x: int, local_z: int):
    """Return the topmost solid block Y in a chunk column, or None."""
    for y in range(chunk.SIZE_Y - 1, -1, -1):
        if int(chunk.get_block(local_x, y, local_z)) != BlockType.AIR:
            return y
    return None


def _mesh_stats(chunk) -> dict:
    return {
        "vertices": len(getattr(chunk, "_mesh_vertices", [])) // 3,
        "triangles": len(getattr(chunk, "_mesh_triangles", [])) // 3,
    }


def measure_refresh_workload(world: World, chunk_coords=(0, 0, 0)) -> dict:
    """Break then regenerate a fixed set of near-surface blocks, timing refresh."""
    from chunk_mesh import generate_chunk_mesh

    chunk = world.chunks[chunk_coords]

    workload = []
    for local_x, local_z in WORKLOAD_COLUMNS:
        local_y = _top_solid_y(chunk, local_x, local_z)
        if local_y is not None:
            workload.append((local_x, local_y, local_z))

    originals = {
        (x, y, z): world.get_block(x, y, z) for (x, y, z) in workload
    }

    initial_verts, initial_tris, _ = generate_chunk_mesh(chunk, world=world)
    initial_mesh = {
        "vertices": len(initial_verts) // 3,
        "triangles": len(initial_tris) // 3,
    }

    break_samples = []
    for (x, y, z) in workload:
        world.set_block(x, y, z, BlockType.AIR)
        start = pytime.perf_counter()
        world.refresh()
        break_samples.append(pytime.perf_counter() - start)
    after_break_mesh = _mesh_stats(chunk)

    regen_samples = []
    for (x, y, z) in workload:
        world.set_block(x, y, z, originals[(x, y, z)])
        start = pytime.perf_counter()
        world.refresh()
        regen_samples.append(pytime.perf_counter() - start)
    after_regen_mesh = _mesh_stats(chunk)

    return {
        "description": (
            "Break then restore the topmost solid block of 16 columns "
            "(x,z in {2,6,10,14}) of chunk (0, 0, 0); one World.refresh() per "
            "single-block change."
        ),
        "chunk": list(chunk_coords),
        "block_count": len(workload),
        "blocks": [list(b) for b in workload],
        "mesh_initial": initial_mesh,
        "mesh_after_break": after_break_mesh,
        "mesh_after_regenerate": after_regen_mesh,
        "break": _timing_stats(break_samples),
        "regenerate": _timing_stats(regen_samples),
        "combined_total_seconds": sum(break_samples) + sum(regen_samples),
    }


def _timing_stats(samples) -> dict:
    if not samples:
        return {"samples": 0}
    ordered = sorted(samples)
    return {
        "samples": len(samples),
        "total_seconds": sum(samples),
        "mean_ms": statistics.fmean(samples) * 1000.0,
        "median_ms": statistics.median(samples) * 1000.0,
        "min_ms": ordered[0] * 1000.0,
        "max_ms": ordered[-1] * 1000.0,
        "p95_ms": _percentile(ordered, 0.95) * 1000.0,
        "per_call_seconds": list(samples),
    }


# ---------------------------------------------------------------------------
# Texture memory + manifest audit
# ---------------------------------------------------------------------------

def _image_stats(path: Path) -> dict:
    from PIL import Image

    with Image.open(path) as image:
        width, height = image.size
        bands = len(image.getbands())
    gpu_bytes = width * height * 4  # RGBA8 upload
    return {
        "path": _relative(path),
        "width": width,
        "height": height,
        "bands": bands,
        "decoded_bytes": width * height * bands,
        "gpu_rgba8_bytes": gpu_bytes,
        "gpu_rgba8_bytes_with_mipmaps": int(gpu_bytes * 4 / 3),
    }


def _relative(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def audit_manifest(manifest: dict) -> dict:
    """Verify every non-null manifest path exists; fail clearly otherwise."""
    entries = []
    missing = []
    for block_name, faces in manifest.get("blocks", {}).items():
        for face in ("top", "side", "bottom"):
            rel = faces.get(face)
            if not rel:
                continue
            absolute = REPO_ROOT / rel
            exists = absolute.is_file()
            entries.append(
                {
                    "block": block_name,
                    "face": face,
                    "path": rel,
                    "exists": exists,
                }
            )
            if not exists:
                missing.append(rel)

    if missing:
        raise RuntimeError(
            "texture_manifest.json references missing files: "
            + ", ".join(sorted(set(missing)))
        )

    return {
        "all_present": True,
        "checked_count": len(entries),
        "missing_files": [],
        "entries": entries,
    }


def measure_texture_memory(manifest: dict) -> dict:
    """Estimate texture memory for the legacy atlas and manifest textures."""
    result = {
        "method": (
            "PNG dimensions decoded with Pillow; GPU estimate assumes RGBA8 "
            "(4 bytes/pixel); with_mipmaps = base * 4/3."
        ),
        "legacy_atlas": None,
        "manifest_textures": {
            "unique_files": 0,
            "total_gpu_rgba8_bytes": 0,
            "total_gpu_rgba8_bytes_with_mipmaps": 0,
            "files": [],
        },
    }

    if LEGACY_ATLAS.is_file():
        result["legacy_atlas"] = _image_stats(LEGACY_ATLAS)

    seen = set()
    total_base = 0
    total_mips = 0
    files = []
    for faces in manifest.get("blocks", {}).values():
        for face in ("top", "side", "bottom"):
            rel = faces.get(face)
            if not rel or rel in seen:
                continue
            seen.add(rel)
            absolute = REPO_ROOT / rel
            if not absolute.is_file():
                continue
            stats = _image_stats(absolute)
            files.append(stats)
            total_base += stats["gpu_rgba8_bytes"]
            total_mips += stats["gpu_rgba8_bytes_with_mipmaps"]

    files.sort(key=lambda item: item["path"])
    result["manifest_textures"] = {
        "unique_files": len(files),
        "total_gpu_rgba8_bytes": total_base,
        "total_gpu_rgba8_bytes_with_mipmaps": total_mips,
        "files": files,
    }
    return result


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def _parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--duration",
        type=float,
        default=float(os.environ.get("VLW_BENCH_SECONDS", DEFAULT_DURATION)),
        help="FPS measurement duration in seconds (default 30).",
    )
    parser.add_argument(
        "--warmup",
        type=float,
        default=float(os.environ.get("VLW_BENCH_WARMUP", DEFAULT_WARMUP)),
        help="Warm-up duration in seconds (default 2).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="Output JSON path (default config/baseline_metrics.json).",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = _parse_args(argv)

    world = build_world()

    render_error = None
    player_entity = None
    chunk_entity_count = 0
    fps_metrics = None
    warmup_frames = 0
    scene_mode = "headless"

    try:
        from ursina import Ursina, application, window

        application.asset_folder = REPO_ROOT
        try:
            from panda3d.core import getModelPath

            getModelPath().append_path(str(REPO_ROOT))
        except Exception:
            pass

        app = Ursina(
            development_mode=False,
            show_ursina_splash=False,
            title="VoxelWorld M9 Baseline",
        )
        scene_mode = "render"

        player_entity, chunk_entity_count = create_scene_entities(world)

        warmup_frames = warm_up(app, args.warmup)

        ground_y = player_entity.find_ground_y()
        if ground_y is not None:
            player_entity.y = ground_y
        player_entity.velocity_y = 0.0

        fps_metrics = measure_fps(app, args.duration)
    except Exception as exc:  # pragma: no cover - environment dependent
        render_error = f"{type(exc).__name__}: {exc}"
        print(f"[measure_baseline] renderer unavailable, running headless: {render_error}")

    refresh_metrics = measure_refresh_workload(world)

    manifest = {}
    manifest_audit = {"all_present": False, "checked_count": 0, "missing_files": [], "entries": []}
    texture_memory = None
    if MANIFEST_PATH.is_file():
        with open(MANIFEST_PATH, encoding="utf-8") as handle:
            manifest = json.load(handle)
        manifest_audit = audit_manifest(manifest)
        texture_memory = measure_texture_memory(manifest)

    resolution = None
    if scene_mode == "render":
        try:
            resolution = [int(window.size[0]), int(window.size[1])]
        except Exception:
            resolution = None

    metrics = {
        "meta": {
            "tool": "scripts/measure_baseline.py",
            "milestone": "M9 Task 1 - Performance Baseline & Asset Audit",
            "python_version": sys.version,
            "ursina_version": _ursina_version(),
            "platform": platform.platform(),
            "scene_mode": scene_mode,
            "render_error": render_error,
            "scene": (
                "TerrainGenerator(seed=42) chunks x/z in [-1,1], y=0; "
                "one chunk entity per chunk; VoxelPlayer spawn (8,8,8)"
            ),
            "chunk_entity_count": chunk_entity_count,
            "vsync": True,
            "resolution": resolution,
            "duration_seconds": args.duration,
            "warmup_seconds": args.warmup,
            "warmup_frames": warmup_frames,
        },
        "fps": fps_metrics,
        "refresh": refresh_metrics,
        "texture_memory": texture_memory,
        "texture_manifest_audit": manifest_audit,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(metrics, handle, indent=2, sort_keys=False)
        handle.write("\n")

    _print_summary(metrics, args.output)
    return 0


def _ursina_version() -> str:
    try:
        from importlib.metadata import version

        return version("ursina")
    except Exception:
        return "unknown"


def _print_summary(metrics: dict, output: Path) -> None:
    print(f"[measure_baseline] wrote {_relative(output)}")
    fps = metrics.get("fps")
    if fps:
        print(
            f"  average_fps={fps.get('average_fps'):.2f} "
            f"frames={fps.get('frames')} "
            f"mean_frame_ms={fps.get('frame_time_ms', {}).get('mean'):.3f}"
        )
    else:
        print("  average_fps=unavailable (headless)")
    refresh = metrics["refresh"]
    print(
        f"  refresh break mean={refresh['break'].get('mean_ms'):.3f} ms "
        f"regenerate mean={refresh['regenerate'].get('mean_ms'):.3f} ms "
        f"({refresh['block_count']} blocks)"
    )
    audit = metrics["texture_manifest_audit"]
    print(
        f"  texture manifest: {audit['checked_count']} face entries, "
        f"all_present={audit['all_present']}"
    )


if __name__ == "__main__":
    raise SystemExit(main())
