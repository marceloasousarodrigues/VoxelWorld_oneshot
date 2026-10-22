"""M15 follow-up: measure the water *commit phase* cost separately.

The M15 harness measures whole frame/tick costs.  Its `water_active` scenario
seeds an already-equilibrated lake, so every tick it measures commits **zero**
occupancy changes and never exercises the commit path at all.  This script
fills an unsupported water blob that must be drained, so the commit path really
runs.

What is measured now (resumable commit):

* `commit slice` - one `WaterSimulation._advance_commit` call, i.e. the batches
  applied within a single tick. This is the per-frame publication cost.
* `prepare slice` - one `_advance_prepare` call, the budgeted pass that groups
  the solved region into per-chunk batches.
* whole tick, and how many ticks exceeded the per-tick budget.
* batches applied per slice and frames needed to finish.

Historical note: `water.py` used to publish the whole region in one atomic
`_commit` call (a per-cell `World.set_water` loop followed by a synchronous
`world.reconcile()`). On the cases below that call took 19.0-19.95 ms with
committing ticks up to 24-93 ms. Those numbers came from the previous revision
of this script, which timed `_commit`; that method no longer exists because the
commit is now fragmented by the tick budget.

It is renderer-free (no Ursina window, no chunk entities), so it is fast and
reproducible; a real frame adds the chunk mesh/entity reassignment that
`World.reconcile` performs for each dirty chunk, so on-screen spikes are larger
than the numbers below.

Usage:
    python scripts/measure_water_commit.py [--repeat 3]

Exit status is 0 even when a slice exceeds the budget: this is a measurement,
not a gate (`--fail-over-budget` turns it into one).
"""

import argparse
import inspect
import statistics
import sys
import time
import types
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from water import WaterSimulation  # noqa: E402
from world import World  # noqa: E402

# Read the shipped per-tick budget from the simulation itself so this harness
# cannot drift away from what the game actually configures.
_sig = inspect.signature(WaterSimulation.__init__).parameters["max_milliseconds_per_tick"]
DEFAULT_BUDGET_MS = float(_sig.default) if _sig.default else 8.0
CELL_BUDGET = 65536


def build_world():
    """The same deterministic seed-42 world the M15 harness builds."""
    world = World()
    TerrainGenerator().generate_world(world)
    world.dirty_chunks.update(world.chunks)
    world.refresh()
    world.dirty_chunks.clear()
    return world


def fill_blob(world, x0, x1, z0, z1, y0, y1, level=8):
    """Write WATER cells with levels but no sources, so the solver drains them."""
    cells = 0
    for x in range(x0, x1):
        for z in range(z0, z1):
            chunk = world.chunks.get((x // 16, 0, z // 16))
            if chunk is None:
                continue
            for y in range(y0, y1):
                chunk.set_block(x % 16, y, z % 16, BlockType.WATER)
                chunk.set_water_level(x % 16, y, z % 16, level)
                cells += 1
    return cells


def percentile(values, fraction):
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    weight = position - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * weight


def instrument(sim, world):
    """Time each resumable commit slice, prepare slice and batch application."""
    record = {
        "commit": [],
        "prepare": [],
        "batches": [],
        "batch_cells": [],
    }

    for name, key in (("_advance_commit", "commit"), ("_advance_prepare", "prepare")):
        original = getattr(sim, name)

        def timed(self, *args, _original=original, _key=key, **kwargs):
            start = time.perf_counter()
            try:
                return _original(*args, **kwargs)
            finally:
                record[_key].append((time.perf_counter() - start) * 1000.0)

        setattr(sim, name, types.MethodType(timed, sim))

    original_batch = world.apply_water_batch

    def timed_batch(chunk_key, cells):
        start = time.perf_counter()
        try:
            return original_batch(chunk_key, cells)
        finally:
            record["batches"].append((time.perf_counter() - start) * 1000.0)
            record["batch_cells"].append(len(cells) if hasattr(cells, "__len__") else -1)

    world.apply_water_batch = timed_batch
    return record


def run_case(name, blob, y=(8, 16), budget_ms=DEFAULT_BUDGET_MS,
             cell_budget=CELL_BUDGET):
    world = build_world()
    sim = WaterSimulation(
        world, max_cells_per_tick=cell_budget, max_milliseconds_per_tick=budget_ms
    )
    cells = fill_blob(world, blob[0], blob[1], blob[2], blob[3], y[0], y[1])
    world.dirty_chunks.clear()
    sim.enqueue(blob[0] + 1, y[1] - 1, blob[2] + 1)
    record = instrument(sim, world)

    tick_ms = []
    frames = 0
    changes = 0
    ticks_with_commit = []
    while (sim.has_pending_work() or world.dirty_chunks) and frames < 2000:
        sim.consume_changes()
        start = time.perf_counter()
        changes += sim.tick()
        duration = (time.perf_counter() - start) * 1000.0
        tick_ms.append(duration)
        if len(record["commit"]) > len(ticks_with_commit):
            ticks_with_commit.append(duration)
        world.reconcile()
        frames += 1

    commits = record["commit"]
    prepares = record["prepare"]
    batches = record["batches"]
    over_commits = [value for value in commits if budget_ms and value > budget_ms]
    over_ticks = [value for value in tick_ms if budget_ms and value > budget_ms]

    print(f"\n{name}")
    print(f"  blob cells written      : {cells}")
    print(f"  occupancy changes       : {changes}")
    print(f"  frames to complete      : {frames}")
    print(f"  budget                  : "
          f"{'unbounded' if not budget_ms else f'{budget_ms:.1f} ms/tick'}"
          f", cell budget {cell_budget}")
    print(f"  commit slices           : {len(commits)}  "
          f"(batches applied: {len(batches)}, "
          f"cells per batch p50={percentile(record['batch_cells'], 0.5):.0f})")
    print(f"  prepare slices          : {len(prepares)}")
    if commits:
        print(f"  commit slice            : p50={percentile(commits,0.5):7.2f} "
              f"p95={percentile(commits,0.95):7.2f} max={max(commits):8.2f} ms")
        print(f"  commit slices over budget: {len(over_commits)}/{len(commits)}")
    if batches:
        print(f"  single batch apply      : p50={percentile(batches,0.5):7.2f} "
              f"max={max(batches):8.2f} ms")
    print(f"  whole tick              : p50={percentile(tick_ms,0.5):7.2f} "
          f"p95={percentile(tick_ms,0.95):7.2f} max={max(tick_ms):8.2f} ms")
    print(f"  ticks over budget       : {len(over_ticks)}/{len(tick_ms)}")
    if ticks_with_commit:
        worst = max(ticks_with_commit)
        print(f"  worst committing tick   : {worst:7.2f} ms"
              + (f"  ({worst / budget_ms:.1f}x the budget)" if budget_ms else ""))
    return {
        "frames": frames,
        "commits": len(commits),
        "commit_p50": percentile(commits, 0.5) if commits else 0.0,
        "commit_max": max(commits) if commits else 0.0,
        "over_budget": len(over_commits),
        "over_ticks": len(over_ticks),
        "tick_max": max(tick_ms) if tick_ms else 0.0,
        "bounded": bool(budget_ms),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repeat", type=int, default=1,
                        help="Repeat every case and report the median of the runs.")
    parser.add_argument("--fail-over-budget", action="store_true",
                        help="Exit non-zero when any bounded case exceeds the "
                             "per-tick budget (commit slice or whole tick).")
    args = parser.parse_args(argv)

    budget = DEFAULT_BUDGET_MS
    cases = [
        ("one chunk, 2048 cells (the case the M15 review measured)",
         (0, 16, 0, 16), (8, 16), budget, CELL_BUDGET),
        ("four chunks, 7168 cells",
         (0, 32, 0, 28), (8, 16), budget, CELL_BUDGET),
        ("four chunks, 7168 cells, tiny 256-cell budget",
         (0, 32, 0, 28), (8, 16), budget, 256),
        ("nine chunks, 18432 cells",
         (0, 48, 0, 48), (8, 16), budget, CELL_BUDGET),
        ("four chunks, 7168 cells, unbounded time (reference)",
         (0, 32, 0, 28), (8, 16), None, CELL_BUDGET),
    ]

    print("=" * 78)
    print("Water commit-phase measurement (renderer-free CPU; no Ursina window)")
    print("=" * 78)

    results = []
    for name, blob, y, budget_ms, cell_budget in cases:
        runs = [
            run_case(name, blob, y=y, budget_ms=budget_ms, cell_budget=cell_budget)
            for _ in range(max(1, args.repeat))
        ]
        if len(runs) > 1:
            median = {
                key: statistics.median([run[key] for run in runs])
                for key in runs[0]
            }
            print(f"  median of {len(runs)} runs: commit p50={median['commit_p50']:.2f} ms "
                  f"max={median['commit_max']:.2f} ms, "
                  f"over-budget commits={median['over_budget']:.0f}, "
                  f"over-budget ticks={median['over_ticks']:.0f}, "
                  f"frames={median['frames']:.0f}")
        results.append(runs[0])

    bounded = [result for result in results if result["bounded"]]
    worst_commit = max(result["commit_max"] for result in bounded) if bounded else 0.0
    worst_tick = max(result["tick_max"] for result in bounded) if bounded else 0.0
    print()
    print("=" * 78)
    print(f"Worst bounded commit slice: {worst_commit:.2f} ms "
          f"({worst_commit / budget:.1f}x the {budget:.0f} ms per-tick budget)")
    print(f"Worst bounded tick        : {worst_tick:.2f} ms "
          f"({worst_tick / budget:.1f}x the {budget:.0f} ms per-tick budget)")
    print("The commit is fragmented by the tick budget: publication resumes across "
          "ticks, one chunk batch at a time.")
    print("=" * 78)

    if args.fail_over_budget and any(
        result["over_budget"] or result["over_ticks"] for result in bounded
    ):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
