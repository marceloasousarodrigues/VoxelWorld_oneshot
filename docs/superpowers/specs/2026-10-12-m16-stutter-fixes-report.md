# M16 Gameplay Stutter — Fix Report

**Date:** 2026-10-12
**Diagnosis:** `docs/superpowers/specs/2026-10-12-m16-gameplay-stutter-diagnosis.md`
**Plan:** `docs/superpowers/plans/2026-10-12-m16-stutter-fixes.md`

Scope: the four measured causes from the diagnosis. No M17 work. Nothing committed.

Environment: Windows 11 (10.0.26200), Python 3.14.5, Panda3D 1.10.16, numpy 2.4.4,
onscreen window, `sync-video 0`.

---

## 1. What was changed

| Fix | Files | Change |
|---|---|---|
| F1 GC policy | `gc_tuning.py` (new), `main.py`, `tests/test_m16_gc_tuning.py` (new) | Freeze the startup object graph into the permanent generation once, after the world and its entities exist and before the first frame. The collector is never disabled. |
| F2 transparency scan | `block_data.py`, `chunk.py`, `chunk_entity.py`, `tests/test_m16_transparency_scan.py` (new) | `Chunk.has_transparent_block()` replaces the Python triple loop over all 4096 cells with one vectorised comparison. |
| F3 staged chunk load | `chunk_entity.py`, `world.py`, `chunk_streaming.py`, `tests/test_m16_staged_load.py` (new) | `World.begin_chunk_load` (data) / `World.finish_chunk_load` (mesh) split a streamed load across two frames. `World.load_chunk` keeps its exact previous behaviour. |
| F4 highlight reuse | `highlight.py`, `tests/test_m16_highlight_reuse.py` (new) | The parent and its 12 edge cubes are built once and repositioned; nothing is destroyed or re-created per event. |

Measurement instruments added: `scripts/profile_m16_attribution.py` (new),
`scripts/profile_m16_stutter.py` (extended: GC monitor, ablation flags, animated
walk scenarios, and the shipped GC policy applied by default).

**Tests: 302 → 334 passing, 0 failing, nothing skipped or weakened.**
32 new tests: 6 GC policy, 8 transparency equivalence, 9 highlight reuse, 9 staged load.

---

## 2. Verified results

### Frame-time distributions

Before = worst of 5 GC-on baseline runs (≈2,190 frames per `cross_boundary` run).
After = worst of 3 runs with the shipped GC policy applied. `>33.3` counts are
totals across the runs.

| Scenario | p50 before → after | p99 before → after | max before → after | >33.3 ms before → after | >50 ms before → after |
|---|---|---|---|---|---|
| `stand_still` | 1.27 → 0.90 | 3.81 → 1.86 | 5.11 → 2.18 | 0 → 0 | 0 → 0 |
| `rotate` | 2.61 → 1.41 | 6.23 → 2.97 | 9.20 → 4.37 | 0 → 0 | 0 → 0 |
| `walk_loaded` | 2.96 → 1.32 | 4.95 → 2.72 | 6.14 → 3.04 | 0 → 0 | 0 → 0 |
| `cross_boundary` | 3.07 → 1.19 | 6.86 → 2.97 | **136.43 → 27.88** | **59 → 0** | **6 → 0** |
| `explore` | 3.48 → 1.33 | 15.87 → 3.14 | **78.85 → 32.43** | **134 → 0** | **14 → 0** |
| `boundary_repeat` | 3.33 → 1.22 | 9.33 → 3.18 | **92.13 → 19.41** | **10 → 0** | 1 → 0 |

Over-budget frames across the three movement scenarios: **203 → 0** (over 33.33 ms),
**21 → 0** (over 50 ms). The worst frame in any after-run was 32.43 ms, and 2 of 3
`cross_boundary` runs stayed at or below 28.62 ms.

### Per-operation cost (unprofiled, median per chunk)

| Phase | Before | After |
|---|---|---|
| Cold chunk load total (`World.load_chunk`) | 25.85 ms | 18.32 ms |
| `create_chunk_entity` (incl. mesh + scan) | 16.12 ms | 7.62 ms |
| Inline transparency scan | 6.20 ms | 0.028 ms (standalone bench: 4.33 → 0.028) |
| `Chunk.refresh` (neighbour remesh) | 9.03 ms | 7.64 ms |
| `BlockHighlight.create_highlight` | 2.203 ms (p95 3.573) | **0.004 ms** (p95 0.012) |
| `BlockHighlight.update_highlight` | 0.009 ms | 0.004 ms |

### What a boundary-crossing frame costs now

A load frame is now **≈29–31 ms** worst case, down from 37–56 ms, split as
`reconcile` 13–19 ms (neighbour remesh, 1–2 chunks) + one streamer stage 9–15 ms +
render ≈3 ms. The streamer stage itself is one half of a load (data ≈8.6 ms, or mesh
≈7.6 ms), never both — which is exactly the property `test_streamer_stages_a_load_across_two_updates`
pins.

### The GC policy, isolated

Measured on the real frame loop with the policy on and off, same code, same session
(experiment recorded in the diagnosis report's investigation): the worst full-collection
pause fell from **85–113 ms to 15–56 ms** and the worst frame from **113.1 → 88.6 ms**
and **95.1 → 82.4 ms**. In the end-to-end before/after this shows up as the `cross_boundary`
`by_gen {2:1}` runs going from a 101–104 ms total GC pause to 21.8–25.8 ms.

**Honest trade-off:** full collections become *more frequent* (the collector's growth
heuristic has a smaller denominator once the startup graph is frozen) while each is
several times cheaper. The tail improves sharply; p99 is essentially unchanged by the
policy alone. Raising generation-2's threshold does **nothing** on this Python build, and
driving full collections on a fixed cadence is *worse* (48–114 ms per explicit call) —
both were measured and discarded.

---

## 3. Design decisions worth reviewing

1. **A staged chunk is solid before it is drawn.** Approved semantics: terrain data is
   authoritative and complete at stage A, so collision, raycasts and edits see the chunk
   immediately; only its geometry lags by one frame. This is what makes movement smooth
   without letting a player fall through a chunk.
2. **One entity always exists.** `create_chunk_entity_placeholder` creates the entity (and
   transparent child) with no model at stage A, so the one-entity-per-loaded-chunk
   invariant holds at *every* point in time, not just at quiescence. A frame performs one
   *kind* of load work — stage B or stage A — never both, which is what keeps a boundary
   crossing inside the frame budget.
3. **`create_chunk_entity` and `World.load_chunk` are byte-for-byte behaviourally
   unchanged.** The streamed path is separate. `test_staged_load_matches_a_synchronous_load`
   and `test_staged_load_reproduces_the_surrounding_neighbour_dirtying` compare real
   uploaded geometry (`model.vertices/triangles/uvs`), block arrays, water metadata,
   decorations, dirty sets and the water edit version between the two paths, so they
   cannot drift.
4. **The collector is never disabled.** `apply()` freezes once and is a documented no-op
   afterwards; `test_apply_leaves_the_collector_enabled` and
   `test_reference_cycles_created_after_apply_are_still_collected` pin that.

---

## 4. Not verified / limitations

- **No on-screen visual verification.** This environment cannot inspect rendered pixels.
  The staged placeholder entity is invisible for at most one frame by construction, and
  the geometry produced is compared numerically against the synchronous path, but the
  on-screen appearance was not seen. `main.py` remains runnable by a human for that.
- **The per-frame floor also shifted** (`walk_loaded` p50 2.96 → 1.32 ms), which no
  change here explains: those scenarios perform no loads, no meshes and no full
  collections. That shift is most likely machine state between sessions, so only the
  structural metrics (over-budget counts, maxima, per-operation cost) are claimed as
  the fixes' effect.
- **One unexplained outlier:** `after_3/cross_boundary` had a single 66.64 ms frame with
  `render_ms = 66.58`, `gc_pause_ms = 0.0`, no loads and no mesh work. It is a one-off
  stall in the engine's step/draw path, not streaming and not GC. Its cause was not
  identified.
- **The neighbour remesh still exceeds one frame's budget on a load frame**: `reconcile`
  may rebuild 1–2 chunks at 7.64 ms each in the same frame as a streamer stage, which is
  why the worst load frame is ≈29–31 ms rather than ≈12 ms. Bounding `reconcile` harder
  would mean leaving a boundary face un-rebuilt for an extra frame; that trade was not
  taken without a visual check.
- **GPU/draw-call cost was not measured** (async GPU, vsync off).
- **`explore`'s over-16.67 ms count is unchanged** (45 per run) — those are the ~29–31 ms
  load frames; making them sub-budget needs the `reconcile` change above.
