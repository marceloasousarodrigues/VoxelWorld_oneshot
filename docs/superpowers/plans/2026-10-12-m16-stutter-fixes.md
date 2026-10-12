# M16 Gameplay Stutter — Implementation Plan

**Status:** IMPLEMENTED. Approved 2026-10-12 with "all four, staged load last" and
"data authoritative, only rendering lags" for Task 3. Results are reported in
`docs/superpowers/specs/2026-10-12-m16-stutter-fixes-report.md`.

**Deviations from this plan, each forced by a measurement or an existing test:**

- **Task 1** implemented `gc.freeze()` only. Raising generation-2's threshold was
  measured to change nothing (1 full collection either way), and driving collections on a
  cadence was measured to be worse (48–114 ms per explicit call). The measured trade-off
  (more frequent, much cheaper collections) is documented in the module and the report.
- **Task 3** creates a geometry-free entity at stage A instead of leaving the chunk
  entity-less, so the one-entity-per-loaded-chunk invariant holds at every instant rather
  than only at quiescence. A frame also performs one *kind* of load work, never both.
- **Task 3** could not make `create_chunk_entity` a composition of the two staged
  functions: `tests/test_vegetation_mesh.py` asserts the literal
  `apply_foliage_cutout(entity)` appears in that function's source. That function is
  therefore left byte-for-byte behaviourally unchanged and the staged path is separate,
  with a new equivalence test pinning the two.
- **Task 5 was not needed** and was not started.

**Companion diagnosis:** `docs/superpowers/specs/2026-10-12-m16-gameplay-stutter-diagnosis.md`

This plan follows the repository's established Superpowers workflow (see
`docs/superpowers/plans/2026-10-12-m15-performance-profiling-scalability.md`): sequential
tasks, each written tests-first with an explicit "confirm failure" step, an implementation
step and a verification step. Tasks are executed **sequentially**; do not launch parallel
subagents.

---

## Global constraints

- **Do not modify existing tests.** Baseline is `python -m pytest tests -q` → **302
  passed** at HEAD `9a3177a`. The acceptance run must report ≥302 passed with nothing
  skipped, weakened or deleted. If an existing test must change, that is a red flag to
  stop and report, not to work around.
- **No optimisation is kept without a before/after measurement.** Each task records JSON
  with `scripts/profile_m16_stutter.py` and/or `scripts/profile_m16_attribution.py`,
  compares against the baseline in `config/`, and is **reverted** if the improvement is
  not demonstrated.
- **Preserve the M1–M16 architecture invariants:** logical `Chunk` is authoritative; one
  rendered chunk entity per loaded chunk; 16×16×16 chunks; negative-coordinate floor
  semantics; deterministic terrain generation; correct cross-chunk boundary faces;
  correct water propagation and invalidation; player movement and collision unchanged;
  player edits survive unload/reload during the session.
- **Do not change** textures, `config/texture_manifest.json`, atlas assets, or
  dependencies.
- **Do not start M17.** Do not implement scoring, persistence-to-disk, biomes, or any
  future-milestone feature.
- **Never disable cyclic GC in shipped code.** Ursina/Panda3D object graphs contain
  reference cycles; disabling the collector leaks entities and breaks the
  one-entity-per-loaded-chunk invariant. `gc.disable()` stays a measurement-only flag of
  the profiler.
- **Do not commit or push without explicit user authorization.** This plan has no commit
  steps.

---

## Review focus

The reviewer should verify, independently:

1. That the new regression tests fail against the pre-change code (not merely pass after).
2. That a chunk which is "registered but not yet meshed" (if Task 3 lands) can never be
   observed by a player as collidable, raycastable or solid, and always converges to
   exactly one entity.
3. That mesh output is byte-identical after Task 2 (`tests/test_m15_mesh_golden.py`).
4. That the transparency-scan change returns the same boolean for chunks that do contain
   transparent blocks (lake water, leaves, tufts) as for those that do not.
5. That `BlockHighlight` still follows the target and still disappears when nothing is
   targeted, with no orphaned entities.
6. That every performance number in the completion report traces to a re-runnable
   artifact in `config/`.

---

## Evidence base (from the diagnosis)

| Rank | Cause | Measured | Fix |
|---|---|---|---|
| 1 | Gen-2 GC collections | 60–105 ms, intermittent | Task 1 |
| 2 | Chunk-load frame | 25.9 ms + ~14 ms neighbours | Task 3 |
| 3 | O(4096) transparency scan | 6.2 ms of a load (24%) | Task 2 |
| 4 | Highlight create churn | 2.20 ms/event (p95 3.57) | Task 4 |

---

## Task 1 — Bound realistic cyclic-GC behaviour

**Why:** the worst observed stall (136.43 ms) is one generation-2 collection; every run
with a gen-2 collection exceeded 78 ms, and no run without one exceeded 55.67 ms.

**Step 1 (tests first).** Add `tests/test_m16_gc_tuning.py` asserting the *policy* rather
than a magic number:

- After `gc_tuning.apply()`, `gc.get_threshold()` generation-2 is strictly greater than
  Python's default, and generations 0/1 are unchanged.
- `apply()` is idempotent.
- `gc.isenabled()` is still `True` after `apply()` (the collector is never disabled).
- With the threshold policy in place, a streamed simulation (simulate N chunk loads +
  mesh rebuilds through the real `World`/`ChunkStreamer` API) records **fewer** gen-2
  collections than the same simulation with default thresholds, restored via
  `gc.set_threshold(*defaults)`.

**Step 2.** Confirm the new tests fail.

**Step 3.** Add `gc_tuning.py` exposing `apply()` / `reset()` and call `apply()` once from
`main.py` before the frame loop. Consider `gc.freeze()` after the initial region is built
(measure with and without; keep only if it helps).

**Step 4 (measurement).**
```bash
python scripts/profile_m16_stutter.py --all --windowed --output config/m16_after_gc_1.json
```
Require: `gc_by_gen["2"] == 0` across the combined scenarios, no frame over 60 ms, and the
p50/p95 of every scenario within noise of baseline.

**Step 5 (leak gate).** `python -m pytest tests/test_m15_memory_growth.py tests -q` must
stay green — a too-rare gen-2 must not grow memory without bound.

**Revert criterion:** if gen-2 collections cannot be reduced without the M15 memory test
failing, revert and report F1 as unresolved with the measurement that shows why.

---

## Task 2 — Vectorise the transparency scan

**Why:** 6.2 ms per load, 4096 Python-level numpy scalar reads at 1.9 µs each — the
largest pure waste inside a cold load.

**Step 1 (tests first).** Add `tests/test_m16_transparency_scan.py`:

- A chunk containing a `WATER` block reports "has transparent block" `True`.
- A chunk containing only `STONE`/`DIRT`/`GRASS`/`AIR` reports `False`.
- Equivalence: for a generated set of chunks (lake chunk, tree chunk, plain chunk), the
  new predicate equals the old triple-loop result.
- The empty-child behaviour is unchanged: a chunk with a transparent block but no
  transparent geometry still ends up with a disabled child entity.

**Step 2.** Confirm failure (the predicate does not exist yet).

**Step 3.** Add the vectorised predicate (a `Chunk` method or a `block_data` helper using
one numpy reduction over the transparent block types) and use it in
`chunk_entity.create_chunk_entity` (currently `chunk_entity.py:93-103`).

**Step 4 (measurement).**
```bash
python scripts/profile_m16_attribution.py --count 8 --repeats 3 --output config/m16_after_scan.json
```
Require: `transparent_scan` median ≤ 0.3 ms (from 6.2 ms) and `entity_full` median ≤ 10.5 ms
(from 16.1 ms), with `cold_load_wall` median ≤ 20 ms (from 25.9 ms).

---

## Task 3 — Split one chunk load across frames

**Why:** the load frame is 25.9 ms plus ~14 ms of neighbour rebuilds — over budget on
every single boundary crossing. This is the fix that makes *movement* smooth.

**Step 1 (design).** Introduce an explicit staged load in the streaming path, e.g. a
`PendingChunkLoad` record the streamer advances one stage per frame:

1. **Stage A:** register + generate terrain and vegetation (≈8.8 ms).
2. **Stage B:** build the mesh, create the entity, dirty loaded neighbours (≈8.4 ms).

Design questions to settle before coding, each with a written answer in the plan's
companion notes: Is a Stage-A chunk collidable? (recommended: yes — terrain data is
authoritative and already correct, so only rendering lags.) Is it raycastable? Does
`ChunkStreamer.has_pending_work()` account for incomplete loads? Does an unload of a
Stage-A chunk behave correctly? Does `apply_overrides` run in Stage A (data) — yes.

**Step 2 (tests first).** Add `tests/test_m16_staged_load.py`:

- After stage 1, the chunk is registered, terrain-complete and `generated is True`, and
  has no entity.
- After stage 2, exactly one entity exists and the chunk is not re-registered.
- A full staged drain produces the same world state as `World.load_chunk` (block-for-block
  and entity-for-entity) — the equivalence gate.
- `has_pending_work()` is `True` while a load is staged.
- Unloading a stage-A chunk leaves no entity and no registry entry, and does not raise.
- Player edits applied before a staged load are present afterwards.

**Step 3.** Confirm failure.

**Step 4.** Implement, keeping `World.load_chunk` as the synchronous single-call API for
every existing caller and test.

**Step 5 (measurement).** Re-run all six scenarios. Require: `cross_boundary` and
`explore` counts over 33.33 ms drop to ≈0, no frame over 25 ms, and p99 within noise.
Also require the full suite green, especially `tests/test_m16_load_unload.py`,
`tests/test_m16_player_exploration.py`, `tests/test_world_dirty_tracking.py`,
`tests/test_m15_reconcile.py`.

**Revert criterion:** if a staged load cannot be made equivalent to a synchronous load
under the existing suite, revert and report the smallest remaining honest gain (Task 2
alone).

---

## Task 4 — Reuse the highlight entities

**Why:** 2.203 ms median (p95 3.573 ms) per event, creating and destroying 13 entities,
triggered ~11 times per 240 rotating frames.

**Step 1 (tests first).** Extend highlight coverage in `tests/test_m16_highlight_reuse.py`:

- `create_highlight` leaves exactly 13 child entities, and calling it twice leaves exactly
  13 (no accumulation).
- `update_highlight` moves the parent and does not add children.
- `remove_highlight` hides the highlight; a subsequent `create_highlight` re-shows it, and
  the child count never exceeds 13 across many create/update/remove cycles.
- The parent entity identity changes only when the target position changes (no per-frame
  churn), and the visible position matches the target block centre.

**Step 2.** Confirm failure against the current destroy-and-rebuild implementation.

**Step 3.** Build the 13 cubes once (lazily) and reposition/enable/disable thereafter.

**Step 4 (measurement).**
```bash
python scripts/profile_m16_attribution.py --count 2 --repeats 1   # highlight section
```
Require `create_highlight` median ≤ 0.1 ms (from 2.203 ms) with the visible result
unchanged. Also re-run the `rotate` scenario and require p99 within noise of baseline or
better.

---

## Task 5 — Reduce per-load allocation (only if Tasks 1–4 leave work)

**Why:** 13,691 `list.extend` calls per load plus one Python tuple per vertex feed gen-2
frequency. This supports Task 1 rather than replacing it.

**Step 1 (tests first).** Count allocation-relevant calls over a fixed load set (an
existing harness counter is enough) and assert the count decreases from the recorded
baseline, with mesh output byte-identical.

**Step 2.** Only pursue directions that keep `tests/test_m15_mesh_golden.py` green:
a flat-list → array upload path, and fewer intermediate lists. Do **not** convert the
mesh builder to fully vectorised numpy unless the golden test still proves byte equality.

---

## Final verification

```bash
python -m pytest tests -q                                            # ≥302 passed
python scripts/profile_m16_stutter.py --all --windowed --output config/m16_after_all_1.json
python scripts/profile_m16_stutter.py --all --windowed --output config/m16_after_all_2.json
python scripts/profile_m16_attribution.py --count 8 --repeats 3 --output config/m16_after_attribution.json
```

Report before/after for: p50/p95/p99, counts over 16.67/33.33/50 ms, maximum frame time,
chunk-load latency, gen-2 collection count, and memory behaviour. Then update
`MILESTONES.md` with an M16 follow-up section and, if the chunk-lifecycle invariants
change, `ARCHITECTURE.md`.

**Completion is not claimed from passing tests or a higher average FPS.** Success means
the over-33.33 ms frame count and the 60–105 ms tail are demonstrably gone, with the full
suite green.
