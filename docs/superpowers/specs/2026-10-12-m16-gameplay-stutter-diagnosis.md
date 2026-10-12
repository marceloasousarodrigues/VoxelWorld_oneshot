# M16 Gameplay Stutter — Diagnosis Report

**Date:** 2026-10-12
**Scope:** investigation only. No production code was changed to produce this report.
**Milestone context:** M16 (Chunk Streaming and World Management) is complete and its
302-test suite passes. This report investigates the stutter felt during real gameplay
in the shipped M16 build.

**Environment measured:** Windows 11 (10.0.26200), Python 3.14.5, Panda3D 1.10.16,
Ursina (installed), numpy 2.4.4. Onscreen window, `sync-video 0` (vsync disabled) so
frame times reflect work rather than the 60 Hz cap.

---

## 1. Method

Two instruments were used, because neither alone is sufficient.

| Tool | Answers | Evidence class |
|---|---|---|
| `scripts/profile_m16_stutter.py` | *Which frame stutters*, and how that frame splits across coarse operations | runtime (real window, real `app.step()`) |
| `scripts/profile_m16_attribution.py` | *Where the milliseconds go inside* a chunk load and a mesh rebuild | runtime + cProfile shares |

Both are repeatable and both were run against the unmodified M16 build.

```bash
# baseline: 6 gameplay scenarios, real window, vsync off
python scripts/profile_m16_stutter.py --all --windowed --output config/m16_stutter_base_tele_1.json

# GC A/B (the experiment that isolated cause #1)
python scripts/profile_m16_stutter.py --all --windowed --gc-disable --output config/m16_stutter_nogc_1.json

# per-phase attribution + cProfile function shares
python scripts/profile_m16_attribution.py --count 8 --repeats 3 --output config/m16_attribution.json
```

**Limits of this evidence.** Frame time is CPU-side wall time around the frame's work
plus the engine's per-frame step. The GPU runs asynchronously with vsync off, so pure
GPU time is not captured; `fps_throughput` is the effective (GPU-inclusive) rate. The
profiler drives the camera itself, so it measures the cost of the resulting rotation,
not the input-device path. No rendered-pixel inspection is possible in this
environment, so **no visual claim is made anywhere in this report.**

### Baseline scenarios

| Scenario | What it exercises |
|---|---|
| `stand_still` | nothing moving — the floor cost |
| `rotate` | camera rotation only, no translation (the user's second complaint) |
| `walk_loaded` | real physics/collision walking inside the already-loaded region, no streaming |
| `cross_boundary` | crossing chunk boundaries at walking speed |
| `explore` | continuous travel through previously unexplored terrain |
| `boundary_repeat` | repeatedly crossing the same chunk boundary (load/unload hysteresis) |

The walk scenarios advance the player at walking speed (`player.speed * dt`) while
following the terrain surface. This is deliberate: there is no auto-step, so a 2-block
terrain rise wedges a real-physics player permanently, which silently turned an earlier
version of these scenarios into idle tests. `walk_loaded` is the scenario that keeps real
physics, so collision and ground-detection cost is still measured.

---

## 2. Measured baseline

Median across 5 GC-enabled runs; `max` is the worst observed and the counts are summed
over the runs. ~2,190 frames per `cross_boundary` run, ~4,100 per `explore` run.

### Cyclic GC enabled (the shipped configuration)

| Scenario | p50 | p95 | p99 | max | >16.67 ms | >33.33 ms | >50 ms | loads | unloads |
|---|---|---|---|---|---|---|---|---|---|
| `stand_still` | 1.27 | 3.36 | 3.81 | 5.11 | 0 | 0 | 0 | 0 | 0 |
| `rotate` | 2.61 | 4.85 | 6.23 | 9.20 | 0 | 0 | 0 | 0 | 0 |
| `walk_loaded` | 2.96 | 4.37 | 4.95 | 6.14 | 0 | 0 | 0 | 0 | 0 |
| `cross_boundary` | 3.07 | 4.97 | 6.86 | **136.43** | 88 | 59 | 6 | 72 | 8 |
| `explore` | 3.48 | 5.76 | 15.87 | **78.85** | 197 | 134 | 14 | 149 | 85 |
| `boundary_repeat` | 3.33 | 5.55 | 9.33 | **92.13** | 21 | 10 | 1 | 17 | 0 |

### Cyclic GC disabled (`--gc-disable`, 2 runs) — the control

| Scenario | p50 | p95 | p99 | max | >16.67 ms | >33.33 ms | >50 ms | loads |
|---|---|---|---|---|---|---|---|---|
| `stand_still` | 1.63 | 4.03 | 4.56 | 5.18 | 0 | 0 | 0 | 0 |
| `rotate` | 2.95 | 5.26 | 7.17 | 9.94 | 0 | 0 | 0 | 0 |
| `walk_loaded` | 3.51 | 5.04 | 5.41 | 5.94 | 0 | 0 | 0 | 0 |
| `cross_boundary` | 3.43 | 5.14 | 13.96 | 51.05 | 35 | 24 | 1 | 30 |
| `explore` | 3.68 | 6.09 | 21.52 | 54.31 | 98 | 61 | 5 | 72 |
| `boundary_repeat` | 4.13 | 6.70 | 22.16 | 47.15 | 8 | 5 | 0 | 8 |

### The two symptoms are quantitatively different

1. **Movement stutter is deterministic and load-bound.** The count of over-33.33 ms
   frames tracks the chunk-load count almost 1:1 (`cross_boundary`: 59 over-33.33 ms
   frames against 72 loads; `explore`: 134 against 149). Every chunk boundary crossing
   produces a 37–56 ms frame. This is the stutter a player feels *while walking*.
2. **Camera rotation does not produce an over-budget frame at all on this machine.**
   `rotate` peaks at 9.20 ms with zero frames over 16.67 ms. What rotation does is *raise
   the per-frame floor*: `stand_still` costs 1.27 ms median (1.55 ms in the step/render
   component) and `rotate` costs 2.61 ms median (2.97 ms), i.e. **rotation adds
   ~1.4 ms/frame**, plus a discrete ~2.2 ms event (cause #4). Rotation is a contributing
   factor, not an independent stall source.

---

## 3. Root causes, ranked by measured impact

### RC1 — Full (generation-2) cyclic GC collections: 60–105 ms, intermittent

**This is the largest single stall and it is intermittent, which is why it is easy to
mistake for "random" hitching.**

The GC monitor installed through `gc.callbacks` separates the two populations perfectly
across every baseline run. Of the 11 scenario-runs whose maximum exceeded 45 ms:

| Run | Scenario | max frame | gen-2 collections | GC pause total |
|---|---|---|---|---|
| `baseline_1` | `cross_boundary` | **136.43 ms** | **1** | 101.0 ms |
| `base_tele_2` | `cross_boundary` | **104.29 ms** | **1** | 104.0 ms |
| `baseline_2` | `boundary_repeat` | **92.13 ms** | **1** | 61.3 ms |
| `base_tele_1` | `explore` | **78.85 ms** | **1** | 113.4 ms |
| `baseline_1` | `explore` | 48.59 ms | 0 | 23.5 ms |
| `baseline_2` | `explore` | 51.37 ms | 0 | 28.3 ms |
| `baseline` | `explore` | 51.62 ms | 0 | 50.2 ms |
| `baseline` | `cross_boundary` | 45.05 ms | 0 | 15.0 ms |
| `baseline_2` | `cross_boundary` | 48.38 ms | 0 | 12.7 ms |
| `base_tele_1` | `cross_boundary` | 55.67 ms | 0 | 12.1 ms |
| `base_tele_2` | `explore` | 53.55 ms | 0 | 49.7 ms |

**Every run containing at least one gen-2 collection has a maximum above 78 ms. No run
with zero gen-2 collections exceeds 55.67 ms.** There is a clean gap between 55.67 ms and
78.85 ms, and the GC-disabled control never exceeds 54.31 ms.

The spike frame itself confirms the attribution. In `base_tele_1/explore` the worst frame
reports `reconcile_ms = 71.95` of which `mesh_ms = 71.94` — but a mesh rebuild costs only
9 ms — and `gc_pause_ms = 64.69` with exactly **1** collection. The pause fired *inside*
the timed operation, inflating whatever function happened to be running. The GC pause is
the stall; the mesh rebuild is only where it landed.

Generation-0 and generation-1 collections are cheap and are *not* the problem: a run with
21 GC frames cost 15.0 ms in total (~0.7 ms each).

**Mechanism.** Gen-2 collection cost is proportional to the number of surviving tracked
objects, so it grows as streaming accumulates long-lived container objects. Streaming
allocates heavily: the cold-load profile shows 109,527 `list.extend` calls per 8 chunk
loads — **13,691 per load** — plus one Python tuple per mesh vertex and a full Ursina
`Entity`/`Mesh` object graph per rendered chunk.

### RC2 — A chunk-load frame is ~26 ms, plus ~14 ms of neighbour mesh rebuilds ≈ 37–56 ms

Deterministic, on **every** boundary crossing. Unprofiled per-chunk phases
(`scripts/profile_m16_attribution.py`, medians over 24 chunks):

| Phase (function) | median ms | share of load |
|---|---|---|
| Terrain blocks (`TerrainGenerator.generate_chunk_terrain`) | 1.6 | 6% |
| Vegetation, incl. tree search (`generate_vegetation_for_chunk`) | 7.2 | 28% |
| Mesh generation (`chunk_mesh.generate_chunk_mesh_split`) | 6.1 | 24% |
| Mesh lists → Panda3D mesh (`chunk_entity._mesh_from_lists`) | 2.3 | 9% |
| **Inline transparency scan** (`chunk_entity.create_chunk_entity`) | **6.2** | **24%** |
| Entity + overlay + neighbour dirtying + water version bump | ~2.5 | 10% |
| **Cold `World.load_chunk` total (measured, not summed)** | **25.9** | 100% |

`World.reconcile` then rebuilds ~1.7 dirty neighbours per load at **9.0 ms** each
(`Chunk.refresh`), adding ~14 ms. 25.9 + 14 ≈ 40 ms, matching the observed 37–56 ms peak.
Bounded-1-load-per-frame limits the *count*; nothing limits the *work per chunk*.

### RC3 — The O(4096) Python-level transparency scan: 6.2 ms of a 26 ms load (24%)

`chunk_entity.py:93-103` decides whether the chunk needs an empty child entity by
scanning all 4096 cells with a Python triple loop over numpy scalar reads:

```python
for x in range(Chunk.SIZE_X):
    for y in range(Chunk.SIZE_Y):
        for z in range(Chunk.SIZE_Z):
            if is_block_transparent(chunk.blocks[x, y, z]):
```

cProfile confirms 32,768 calls to `is_block_transparent` per 8 loads — **exactly 4096 per
load** — at 1.9 µs/call, making it the single largest `tottime` entry in the cold-load
profile (61.29 ms of 411.90 ms inflated, 15%). This is the biggest *pure waste* item
inside a load: the question ("does this chunk contain any transparent block?") is a
one-line numpy reduction.

### RC4 — `BlockHighlight` entity churn: 2.20 ms median (p95 3.57 ms) per event

`highlight.py:16` `create_highlight` destroys and rebuilds **13 cube entities** every time
the raycast target changes between "something" and "nothing":

| Operation | median | p95 | max |
|---|---|---|---|
| `create_highlight` | **2.203 ms** | 3.573 ms | 3.959 ms |
| `update_highlight` | 0.009 ms | 0.018 ms | 0.021 ms |
| `remove_highlight` | 0.058 ms | 0.111 ms | 0.211 ms |

The `rotate` scenario triggers 11 such events in 240 frames (one per ~22 frames).
Repositioning is free; only creation is expensive. A player swinging the camera across
blocks and gaps produces exactly this pattern.

### RC5 — Camera rotation raises the per-frame floor by ~1.4 ms

`stand_still` step/render component: 1.53–1.55 ms/frame. `rotate`: 2.82–2.97 ms/frame.
This is the Panda3D cull/draw path over the newly visible geometry, on the main thread.
It is a real cost but not, on this machine, a stall source by itself.

### Measured and *refuted* — do not "fix" these

The M16 limitations listed as suspects were each checked and each is not a cause here:

- **Water jobs invalidated/restarted on load/unload:** `water_ms` total 4.7–9.2 ms across
  15–36 loads (≈0.3 ms/load) and `water_pending_frames == 0` in **every** scenario. The
  restarts are correct and cheap; they are not a stutter source in these conditions.
- **`World.apply_overrides` O(total edits):** `load_ms` (26.4 ms) equals terrain (10.5) +
  entity (15.9) to within 0.2 ms, so overlay replay is negligible at the current sparse
  edit count. It remains O(total edits) and is a *hypothesis* for edit-heavy sessions, not
  an observed cause.
- **Chunk unload:** 0.4–4.6 ms total for 4–25 unloads (≈0.15 ms each). Negligible.
- **Entity destruction:** `remove_highlight` 0.058 ms; unload path negligible.

---

## 4. Contributing factors: confirmed vs. hypothesis

| Factor | Status |
|---|---|
| Gen-2 GC pause is the worst stall | **Confirmed** (controls: gen-2 count separates maxima cleanly; GC-disabled run caps at 54.31 ms) |
| Every chunk-load frame is 37–56 ms | **Confirmed** (unprofiled phases + spike records) |
| The 4096-cell scan is ~6 ms of that | **Confirmed** (phase timing + 4096 calls/load in cProfile) |
| Highlight create churn is ~2.2 ms/event | **Confirmed** (direct unprofiled micro-measurement) |
| Rotation adds ~1.4 ms/frame | **Confirmed** (component comparison) |
| Water restarts, unload cost | **Refuted** for these conditions |
| `apply_overrides` scaling with edit count | **Hypothesis** — unmeasured, no edit-heavy scenario exists yet |
| GPU/draw-call bound rotation stutter | **Not measured** — async GPU with vsync off is not captured by this harness |
| Neighbour re-cull exposing a missing face after unload | **Not visually verified** (impossible in this environment) |

---

## 5. Recommended fixes, in measured-impact order

**F1. Bound or amortise cyclic GC.** Attack the 60–105 ms tail. Candidate mechanisms:
raise the generation-2 threshold so full collections become rare, and/or `gc.freeze()`
after the initial region is built. **GC must not simply be disabled** — the Ursina/
Panda3D object graph contains reference cycles, so disabling it would leak entities and
break the one-entity-per-loaded-chunk invariant. Verify with `gc_by_gen` plus the M15
memory-growth test.

**F2. Vectorise the transparency scan.** `chunk_entity.py:93-103` → one numpy reduction.
6.2 ms → ~0.1 ms per load (≈24% of a load) for no behaviour change.

**F3. Split one chunk load across frames.** The largest structural win for movement
smoothness: stage terrain+vegetation (≈8.8 ms) and mesh+entity (≈8.4 ms) into separate
frames so no frame carries the whole 26 ms. Target: no load frame over ~16.7 ms.

**F4. Reuse the highlight entities.** Create the 13 cube children once and reposition/
toggle them (`highlight.py:16`). 2.2 ms → ~0 per event.

**F5. Reduce per-load allocation** (13,691 list `extend`s per load; one tuple per vertex).
Lower allocation churn makes gen-2 fire less often — this supports F1 rather than
replacing it.

---

## 6. Trade-offs and correctness risks

| Fix | Benefit (measured) | Complexity | Correctness risk |
|---|---|---|---|
| **F1** | Removes the 60–105 ms tail | Low code, environment-sensitive tuning | Must not leak cycles (M15 memory test). Thresholds are not portable between machines/Python versions. `gc.freeze()` only protects objects present at that moment |
| **F2** | −6.2 ms per load (24%) | Very low | Must preserve the exact "any transparent block ⇒ empty transparent child slot" semantics. Existing coverage: `tests/test_transparency_child_entity.py` |
| **F3** | −20 ms per load frame peak | **Highest** | A chunk could become "registered but not rendered" or visible without an entity. Must preserve: one entity per loaded chunk, logical data authoritative, no double load, water-version bump timing, neighbour dirtying, `apply_overrides` ordering |
| **F4** | −2.2 ms per highlight event | Low | Highlight must still follow the target and vanish when nothing is targeted. Existing coverage: `tests/test_highlight.py` |
| **F5** | Fewer gen-2 collections | Medium | Touches the mesh upload path shared with `Chunk.refresh`; must keep `tests/test_m15_mesh_golden.py` green |

### What must not regress

One rendered chunk entity per loaded chunk; logical chunk data authoritative;
deterministic terrain generation; correct cross-chunk boundary faces; correct water
propagation and invalidation; player movement and collision; player edits surviving
unload/reload. F3 is the fix most likely to threaten the first of these.

---

## 7. Reproduce

```bash
python scripts/profile_m16_stutter.py --all --windowed           # baseline (config/m16_stutter_metrics.json)
python scripts/profile_m16_stutter.py --all --windowed --gc-disable   # GC control
python scripts/profile_m16_attribution.py --count 8 --repeats 3  # phase timings + cProfile shares
python -m pytest tests -q                                        # 302 passed at the time of writing
```

Machine-readable results: `config/m16_stutter_base_tele_*.json`,
`config/m16_stutter_nogc_*.json`, `config/m16_attribution.json`.
