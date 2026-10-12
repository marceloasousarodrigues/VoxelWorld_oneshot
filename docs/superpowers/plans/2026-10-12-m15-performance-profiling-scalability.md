# M15 Performance Profiling & Scalability Implementation Plan

**Status:** IMPLEMENTED. This plan was approved on 2026-10-11 and executed. Results are
reported in the "M15 Completion Report" section of `MILESTONES.md`.

**Companion spec:** `docs/superpowers/specs/2026-10-12-m15-performance-profiling-scalability-design.md`

This plan follows the repository's established Superpowers workflow (see
`docs/superpowers/plans/2026-10-11-m14-natural-world-generation.md`): sequential
tasks, each written tests-first with an explicit "confirm failure" step, an
implementation step, a verification step and a commit step. Tasks are executed
**sequentially**; do not launch parallel subagents.

---

## Global constraints

- **Do not modify existing tests.** Baseline is `python -m pytest tests -q` →
  **212 passed** at `main` HEAD `45d3ca0`. The acceptance run must report ≥212 passed
  with nothing skipped, weakened or deleted.
- **Do not change gameplay behaviour** while profiling. Tasks 1 and 2 add measurement
  only.
- **Preserve the M1–M14 architecture invariants:** logical Chunk is authoritative; one
  combined terrain mesh and one Ursina Entity per rendered chunk; `Chunk` dimensions
  16×16×16; negative-coordinate floor semantics; rendering is never the authoritative
  block store; entry point stays minimal.
- **Preserve M13 water correctness and determinism.** No change to levels, spread
  rules, `set_water` semantics or the external-edit invalidation contract.
- **Preserve M14 generation** (tufts, trees, determinism, interaction non-interference).
- **Do not change** textures, `config/texture_manifest.json`, atlas assets, or
  dependencies.
- **Do not refactor M1–M14** beyond the minimum each task requires.
- **Keep diagnostic profiling out of the shipped game** (spec D1/D8).
- **No optimisation is kept without a before/after measurement.** Record JSON, compare,
  and revert if the improvement is not demonstrated (spec D9).
- **No destructive commands, no discarding user changes, no commit unless the
  established workflow requires it.** This plan's Task steps include a commit step;
  each is a separate, self-contained commit on the milestone branch.

---

## Review focus

The reviewer should verify, independently of these claims:

1. That the harness measures through the same code paths the game uses (imports game
   modules unchanged, builds the `main.py` scene) and that diagnostic mode cannot
   contaminate gameplay-measurement mode.
2. That `World.refresh()` still behaves exactly as before and every existing test that
   calls it still passes unmodified.
3. That after batching/budgeting, breaking and placing a block still updates the
   rendered mesh within one frame, including at chunk boundaries.
4. That mesh output is unchanged by Task 6 (golden equality, not just "looks right").
5. That water's final state is cell-for-cell identical after the scheduling change.
6. That no new per-frame allocation, timer or I/O was added to shipped code paths.
7. That every performance number in the completion report is traceable to a harness
   JSON artifact that the reviewer can re-run.

---

## File structure

### Create

- `scripts/profile_m15.py` — M15 benchmark harness (scenarios, metrics, JSON output,
  diagnostic mode). Tasks 1, 7, 8, 11.
- `tests/test_m15_harness.py` — unit tests for metric computation (percentiles,
  over-budget counts, attribution, queue reporting). Task 1.
- `tests/test_m15_atlas_cache.py` — cached atlas map behaviour and reset hook. Task 3.
- `tests/test_m15_reconcile.py` — batching, deduplication, per-frame budget, priority
  ordering, no-unbounded-accumulation. Tasks 4, 5.
- `tests/test_m15_mesh_golden.py` — byte-identical mesh output for a fixed chunk set
  (the correctness gate for Task 6). Task 6.
- `tests/test_m15_water_equivalence.py` — final-state equivalence under new scheduling.
  Task 7.
- `tests/test_m15_memory_growth.py` — bounded growth / no-leak assertions. Task 9.
- `config/m15_baseline_metrics.json` — recorded pre-change baseline. Task 2.
- `config/m15_post_metrics.json` — recorded post-change metrics. Tasks 3–9, 11.

### Modify

- `texture_config.py` — `lru_cache` on `load_atlas_map` + reset hook. Task 3 (small).
- `world.py` — deferred reconcile entry point, bounded budget, priority ordering,
  cheap counters. Tasks 4, 5, 9. `refresh()` behaviour unchanged.
- `player.py` — `break_block` / `place_block` no longer call `world.refresh()` inline;
  they mark dirty and let the frame reconcile. Tasks 4, 5.
- `water.py` — `tick()` time budget and scheduling priority only. Task 7.
- `main.py` — call the reconcile (and keep the water tick) in `update()`. Tasks 4, 7.
- `chunk_mesh.py` — hoisting/precompute in `generate_chunk_mesh_split` and its helpers;
  output preserved. Task 6.
- `block_data.py` — precomputed per-block-type lookups used by the mesher. Task 6.
- `MILESTONES.md` — register M15 as PLANNED — NOT IMPLEMENTED (done during this
  planning step, not during implementation).

### Not modified

- `chunk.py` (unless a task proves it necessary; `Chunk.refresh` semantics preserved).
- `coordinate_system.py`, `raycast.py`, `highlight.py`, `inventory.py`,
  `inventory_ui.py`, `terrain_generation.py`, `vegetation.py`, `debug_main.py`,
  `main_original.py`, `test_world.py`.
- Any file under `tests/` that already exists.
- Any texture/atlas asset, `config/texture_manifest.json`, `opencode.json`, `.github/`.

---

## Task 1 — Profiling harness (diagnostic only)

### Step 1 — Write failing tests

Create `tests/test_m15_harness.py` asserting the pure metric helpers of
`scripts/profile_m15.py`:

- `percentile(sorted_values, f)` matches a hand-computed linear-interpolation value and
  handles the single-sample case.
- `FrameStats(samples_ms)` exposes `p50`, `p95`, `p99`, `max`, `over_16_67`,
  `over_33_33` and `over_16_67_pct`, computed against the literal thresholds
  **16.67** and **33.33**.
- `attribute(...)` produces an attribution mapping whose values sum to no more than the
  measured frame total (interaction, reconcile/world update, mesh generation, water
  tick, chunk generation, other).
- `pending_work(world, water)` reports `dirty_chunks`, `pending_seeds`, `active_job`.
- `chunk_counts(world)` reports loaded / visible (entity is not None) / active
  (`dirty_chunks`), so an unloaded count is derivable and honestly reported as `null`
  while no unload path exists.

These tests must import the harness module without starting an Ursina application.

### Step 2 — Confirm failure

`python -m pytest tests/test_m15_harness.py -q` → collection error / ImportError
(`scripts/profile_m15.py` does not exist). Record the output.

### Step 3 — Implement

Create `scripts/profile_m15.py`:

- Mirrors `scripts/measure_baseline.py`'s structure: `argparse`, `Path`-based
  `application.asset_folder`, JSON output, `--duration`/`--frames`/`--output`, and the
  existing percentile helper convention.
- Scene builder replicating `main.py` exactly: `World`, `TerrainGenerator(seed=42)`,
  one `create_chunk_entity` per chunk, `VoxelPlayer` at `(8, 8, 8)`, and a
  `WaterSimulation` with `seed_all_sources()`.
- Scenario registry implementing spec §5.1 items 1–10, each `run_<name>()` returning a
  metrics dict, selectable via `--scenario NAME` (repeatable) or `--all`.
- Deterministic: fixed seed, fixed edit coordinates, documented multi-chunk fill for
  scenarios 6–10 so they can grow the active region reproducibly.
- Mode separation: default mode measures frames with `cProfile`/`tracemalloc` **off**;
  `--profile` enables them for diagnosis only and marks the output
  `"mode": "diagnostic"` so results are never mixed.
- Records per-run `meta`: Python/Ursina/Panda3D/NumPy versions, platform, resolution,
  scene description, window type (`offscreen`/`onscreen`), vsync state.
- Never writes anywhere except the requested `config/*.json` output.

### Step 4 — Verify

- `python -m pytest tests/test_m15_harness.py -q` → passes.
- `python -m pytest tests -q` → still **212 + new** passed, no existing test changed.
- `python scripts/profile_m15.py --all --frames 600 --output config/m15_smoke_metrics.json`
  runs to completion offscreen and writes JSON.
- Sanity-check the harness against the spec's independent numbers: a single
  break-and-refresh scenario must land in the same tens-of-milliseconds band as the
  spec §2.2 figure (≈45 ms), and an idle scenario must show 0 frames > 16.67 ms. A
  large disagreement is a harness bug, not a finding.

### Step 5 — Commit

`test(m15): add reproducible performance profiling harness`

---

## Task 2 — Establish and record the pre-change baseline

**No source change in this task.** This task produces the numbers every later
acceptance criterion is measured against.

### Step 1 — Run the harness three times

```
python scripts/profile_m15.py --all --frames 600 --output config/m15_baseline_metrics.json
```

Repeat 3× and record run-to-run spread per scenario. Keep the run whose scene matches
`main.py` (9 chunks) plus a documented multi-chunk variant for scenarios 6–10.

### Step 2 — Fix the numerical targets

Replace every "to be established after Task 2" placeholder in the spec's §6 table with
a concrete number derived from the recorded baseline, specifically:

- the per-frame mesh-work budget (provisional ≤8 ms);
- the p95 frame-time target during a rapid-break session;
- the minimum acceptable reduction in the count of frames > 16.67 ms attributable to
  mesh rebuilds (provisional ≥80 %);
- the water per-frame budget while active;
- the active-region memory budget (start from 28 KB × active chunks, measured).

**Stop for approval of these targets and of spec §9.1–§9.5 before continuing.**

### Step 3 — Verify

- `config/m15_baseline_metrics.json` exists, is valid JSON, and carries `meta`.
- The recorded single-edit frame cost is consistent with the existing
  `config/baseline_metrics.json` (`break mean_ms` 39.08, `regenerate mean_ms` 40.28,
  max frame 83.71 ms) — a cross-check against a pre-existing project artifact.

### Step 4 — Commit

`docs(m15): record pre-change performance baseline`

---

## Task 3 — Cache the atlas map (small, low risk)

### Step 1 — Write failing tests

`tests/test_m15_atlas_cache.py`:

- `load_atlas_map()` returns a stable object (same identity) across repeated calls when
  the atlas assets exist.
- `load_atlas_map()` returns `None` when assets are unavailable (patch the availability
  check) and does not cache that negative result in a way that breaks a later successful
  load.
- `texture_config.reset_cache()` clears the atlas-map cache too, preserving the existing
  test-isolation contract of `tests/test_texture_config.py`.

### Step 2 — Confirm failure

Run the new test file; the identity/cache assertions fail because
`texture_config.load_atlas_map` re-reads the file on every call
(`texture_config.py:72-76`).

### Step 3 — Implement

- Add `functools.lru_cache(maxsize=1)` to `load_atlas_map`, mirroring `load_manifest`.
- Extend `reset_cache()` to clear it.
- Do not change the returned structure (callers index `["tiles"]`).

### Step 4 — Verify

- New tests pass; `tests/test_texture_config.py`, `tests/test_m14_textures.py`,
  `tests/test_m11_texture_quality.py`, `tests/test_atlas_generator.py` pass unmodified.
- Harness before/after: expect a small improvement only (spec measured 0.18 ms against
  a ≈42 ms rebuild). **Report it as small.** If the harness shows no measurable change,
  keep the change for hygiene (it removes per-rebuild disk I/O) and say so plainly
  rather than claiming a speed-up.
- Full suite ≥212 passed.

### Step 5 — Commit

`perf(m15): cache the atlas map instead of re-reading it per mesh rebuild`

---

## Task 4 — Deferred, batched mesh reconciliation

Implements spec D2 and D3.

### Step 1 — Write failing tests

`tests/test_m15_reconcile.py`:

- Editing one block via the player path does **not** rebuild meshes inline: after
  `break_block()` / `place_block()` succeed, the block data is already changed and the
  chunk is in `world.dirty_chunks`, but no `Mesh` has been constructed yet.
- One reconcile step makes the rendered mesh reflect the change (chunk entity model is
  not `None` / geometry changed) — i.e. rendering catches up within one frame.
- N edits in the same frame to the same chunk produce **one** rebuild, not N
  (instrumented rebuild counter).
- N edits to N different chunks produce N rebuilds (no over-batching that would drop a
  change).
- A boundary edit still dirties the loaded neighbour chunk(s) and the neighbour's
  rebuild happens too (M7 chunk-boundary contract preserved).
- Repeating the edit→reconcile cycle many times leaves `world.dirty_chunks` empty
  (no unbounded accumulation).
- Blocking-data visibility is immediate: a `raycast` / `world.get_block` immediately
  after the edit sees the new value before any reconcile.

### Step 2 — Confirm failure

Run the new file. The inline-rebuild assertions fail because `player.break_block`
(`player.py:940`) and `player.place_block` (`player.py:1008`) call
`self.world.refresh()` synchronously.

### Step 3 — Implement

- Add a reconcile entry point on `World` (name to be settled in review; e.g.
  `World.reconcile()`), which rebuilds only the currently dirty chunks and clears them,
  reusing the existing `refresh()` body so behaviour is identical.
- Keep `World.refresh()` public and synchronous — its existing callers and all
  existing tests are unchanged.
- `VoxelPlayer.break_block` / `place_block`: drop the inline `refresh()`; the existing
  `world.set_block` already marks the chunk and its loaded boundary neighbours dirty
  (`world.py:113-131`), so no new invalidation logic is needed.
- Call reconcile from `main.py:update()` (which already runs the water tick).
- If `WaterSimulation._commit` (`water.py:477`) calls `refresh()` inline, route it
  through the same deferred path so a water commit cannot block the frame. Keep the
  commit atomic: all `set_water` writes still land before any rebuild.

### Step 4 — Verify

- New tests pass; **`tests/test_break_block.py`, `tests/test_place_block.py`,
  `tests/test_chunk_refresh.py`, `tests/test_world_dirty_tracking.py`,
  `tests/test_vegetation_interaction.py`, `tests/test_water_chunk_integration.py`,
  `tests/test_water_transparency.py` pass unmodified** (they call `world.refresh()`
  directly and must be unaffected).
- Full suite ≥212 passed.
- Harness: the 4-edits-in-one-frame scenario must drop from the baseline
  (spec: 174.70 ms → 44.77 ms). Single-edit frames are expected to be roughly unchanged
  at ≈45 ms until Task 5/6 — report that honestly.
- Runtime check: run the game, break and place blocks, confirm the change appears and
  no boundary artifact persists.

### Step 5 — Commit

`perf(m15): batch dirty-chunk mesh rebuilds into a once-per-frame reconcile`

---

## Task 5 — Bound per-frame mesh work and prioritise the player's edit

Implements spec D4.

### Step 1 — Write failing tests

- With M chunks dirty and a budget of N < M, one reconcile step rebuilds at most N and
  leaves the rest queued; `dirty_chunks` never grows while the player is idle-editing.
- The chunk containing the most recent edit is rebuilt first (recorded rebuild order).
- Repeated reconcile steps drain the queue to empty (budget is a rate limit, not a
  loss).
- The budget is respected under a large dirty set (e.g. mark all 25 chunks dirty: total
  rebuild time across frames equals the unbatched total, but **no single frame exceeds
  the budget**).
- Boundary correctness is preserved: after the queue drains, every dirty chunk —
  including boundary neighbours — has been rebuilt exactly once.

### Step 2 — Confirm failure

With Task 4 in place, a reconcile with a large dirty set still rebuilds everything in
one step, so the "at most N per step" and "budget respected" assertions fail.

### Step 3 — Implement

- Order the dirty set: recent-edit chunk first, then remaining chunks in a deterministic
  order (e.g. by distance from the player, tie-broken by coordinate) so behaviour is
  reproducible across runs.
- Track a per-frame budget. The spec offers **millisecond cap** or **count cap**; the
  choice and value are fixed in Task 2's approval step. Prefer the simpler, more
  deterministic option for the small dirty sets the game produces, and record which was
  chosen.
- Expose cheap counters (rebuilds, µs) for the harness. These are integers on an
  already-taken path — no timers, no allocation, no I/O in the shipped loop.

### Step 4 — Verify

- New tests pass; full suite ≥212 passed unmodified.
- Harness: boundary-edit scenario frame time must be bounded by the budget instead of
  scaling with the dirty count (baseline: 3 chunks, 120.21 ms); dirty-set-drain total
  must match the unbounded total within noise (no work lost or duplicated).
- Runtime check: rapid breaking near a chunk corner must not produce a visible hitch and
  must not leave a stale boundary face beyond the allowed staleness.

### Step 5 — Commit

`perf(m15): bound per-frame mesh rebuilds and prioritise the edited chunk`

---

## Task 6 — Reduce mesh-generation cost without changing output

Implements spec D5. This is the largest absolute win and the highest correctness risk,
so it is deliberately ordered after the safety net of Tasks 4–5.

### Step 1 — Write the golden-output test first

`tests/test_m15_mesh_golden.py`:

- For a fixed set of chunks (including the 3×3 generated set, a chunk with decorations,
  a chunk with water, and a chunk with trees), capture the exact
  `generate_chunk_mesh_split` output and assert **byte-identical** vertices, triangles
  and UV lists after the refactor.
- Store the golden data generated from the pre-change commit as a fixture so the test
  fails loudly if geometry or UVs shift by even one value.
- Assert the M12 face-orientation guarantees still hold for every face index.

### Step 2 — Confirm the test passes before the change

Run the golden test against unmodified `chunk_mesh.py`; it must pass (that is the point
— it is a regression gate, not a red test). Record the baseline output hashes.

### Step 3 — Implement (in this order, committing after each sub-step)

1. Hoist the per-block `faces` list literal and neighbour/UV tables out of
   `_add_exposed_faces_to_split` (`chunk_mesh.py:238`) into module-level constants.
2. Precompute per-block-type face UV rectangles and `is_solid`/`is_transparent` flags
   once, so the ≈13.6k `is_block_solid` calls and ≈5.9k `get_block_face_textures` calls
   per rebuild collapse to indexed lookups. Keep `block_data`'s public functions
   (`is_block_solid`, `is_block_transparent`, `get_block_face_textures`) intact for
   every existing caller.
3. Collect decorations only when the chunk has any (`chunk.decorations.any()`), skipping
   the second 4,096-cell pass for the common decoration-free case.
4. Reduce `_get_neighbor_block`'s double work for boundary faces (it converts
   coordinates once via `is_loaded` and again via `world.get_block`).
5. Only if measurements still justify it **and** spec §9.4 is approved: a
   numpy-vectorised visibility pass, still gated by the golden test.

### Step 4 — Verify

- Golden test passes after every sub-step (identical output).
- `tests/test_m12_face_orientation.py`, `tests/test_chunk_mesh.py`,
  `tests/test_water_mesh_culling.py`, `tests/test_vegetation_mesh.py`,
  `tests/test_water_integration.py` pass unmodified.
- Full suite ≥212 passed.
- Harness: report the new `generate_chunk_mesh_split` duration against the baseline
  (spec measured 41.74 ms with a preloaded atlas). Report the achieved reduction and the
  resulting single-edit frame time; if a sub-step shows no benefit, revert that
  sub-step rather than keeping it.

### Step 5 — Commit (one per sub-step)

`perf(m15): hoist mesh face tables out of the per-block loop`
`perf(m15): precompute per-block-type mesh lookups`
`perf(m15): skip the decoration pass for decoration-free chunks`

---

## Task 7 — Water update scheduling

Implements spec D6. **Solver semantics are not changed.**

### Step 1 — Write failing tests

`tests/test_m15_water_equivalence.py`:

- Final-state equivalence: run a fixed water scenario to quiescence under old and new
  scheduling and compare every chunk's `blocks`, `water_levels` and `water_sources`
  arrays cell-by-cell — must be identical.
- Water does not run on a frame where the caller reports the budget already consumed
  (per spec §9.5, subject to approval).
- `tick()` honours a time budget: with an artificially small budget it returns having
  made progress without exceeding it, and `has_pending_work()` stays `True` until the
  region is complete.
- No partial commit: a region is still applied atomically after the scheduling change.
- Water-driven rebuilds go through the bounded reconcile (Task 5), not an inline
  unbounded `refresh()`.

### Step 2 — Confirm failure

Run the new file: equivalence/budget assertions fail because
`water.WaterSimulation.tick` uses a fixed cell budget
(`DEFAULT_MAX_CELLS_PER_TICK = 65536`) with no time bound, and `_commit` calls
`world.refresh()` inline.

### Step 3 — Implement

- Add a time budget (and/or scheduling priority) to `tick()`; the internal cell budget
  and the 0-1 BFS stay exactly as they are.
- Route the commit's rebuild through the Task 5 reconcile so a water commit cannot block
  a frame.
- Do not change `set_water`, the external-edit log, `water_edit_version`, or the
  version-gated stale-job invalidation.
- Call order in `main.py:update()`: reconcile interaction work first, water second, so
  the player's edit always wins the budget.

### Step 4 — Verify

- New tests pass; **`tests/test_water_rules.py` (18 KB, the exhaustive M13 suite),
  `tests/test_water_chunk_integration.py`, `tests/test_water_mesh_culling.py`,
  `tests/test_water_transparency.py`, `tests/test_water_texture_compatibility.py`,
  `tests/test_water_integration.py` pass unmodified.**
- Full suite ≥212 passed.
- Harness: water-active per-frame cost must fall from the baseline (spec measured
  9.11 ms mean / 13.16 ms max over 113 frames) and no frame that combines an edit with
  a water tick may exceed the fixed budget. Also report the run's time-to-quiescence so
  any slowdown in reaching the final state is visible, not hidden.

### Step 5 — Commit

`perf(m15): give water updates a time budget and lower scheduling priority`

---

## Task 8 — Attribute the remaining mesh cost and chunk-generation cost

Diagnosis only; no gameplay change.

### Step 1 — Extend the harness

Add a `--profile` diagnostic report that attributes, per scenario:

- mesh generation time split between the block pass, the decoration pass, neighbour
  lookups and UV construction;
- allocation/GC pressure during rebuilds (`gc` counters, `tracemalloc` deltas) as
  distinct from raw CPU time (the open question in spec §8);
- chunk generation cost per chunk (baseline ≈8.5 ms/chunk) and its distribution;
- water tick cost split between traversal and view/lookup overhead (spec §8 open
  question);
- whether the lazy imports inside `Chunk.refresh` (`chunk.py:85,105,133`) are
  measurable.

### Step 2 — Record and triage

Write the attribution into `config/m15_post_metrics.json`. For each finding, decide:
(a) fix in M15 if cheap and safe, or (b) record as a follow-up with the measurement.

### Step 3 — Verify

`--profile` output is clearly labelled diagnostic and separate from the gameplay
numbers; running the harness in default mode is unaffected.

### Step 4 — Commit

`chore(m15): add diagnostic attribution reports to the profiling harness`

---

## Task 9 — Chunk lifecycle measurement and the bounded active-region contract

Implements spec D7. **This task measures and defines; it does not introduce streaming
unless spec §9.1 is approved.**

### Step 1 — Write tests

`tests/test_m15_memory_growth.py`:

- Per-chunk numpy storage is 28,672 B (`blocks` 16,384 + `water_levels` 4,096 +
  `water_sources` 4,096 + `decorations` 4,096), asserted from the real arrays.
- Growing loaded chunks scales storage linearly with loaded count, and the harness can
  report loaded / visible / dirty counts and numpy bytes over time.
- Deterministic traversal does not duplicate chunk objects or retain removed ones —
  asserting what is true today: with no unload path, the loaded set is the active set
  and the harness's `unloaded` count is reported as `null`, not fabricated.
- After a traversal-plus-edit session ends, pending work returns to zero (no leak of
  dirty flags or water seeds).

### Step 2 — Confirm state

Run the tests to record the current, honest behaviour (this step documents the baseline
contract rather than failing).

### Step 3 — Implement (measurement + contract only)

- Expose the counts through the harness and record them in `config/m15_post_metrics.json`.
- State the bounded active-region budget explicitly as **28 KB × active chunks** and
  record the measured trajectory.
- Document the contract: reads never create (`World.get_block`), water never creates
  (`set_water`), `player._chunk_exists` never creates; only `World.get_chunk` creates,
  and nothing unloads. Note `player.get_block_at`'s latent creating fallbacks
  (`player.py:768,779`) as documented-but-unreachable.

### Step 4 — Verify

- Tests pass; full suite ≥212 passed.
- Memory report over a sustained session shows no growth beyond the active-region
  budget, and no monotonic growth with a fixed active set.

### Step 5 — Commit

`test(m15): assert bounded chunk storage and document the active-region contract`

---

## Task 10 — Rollback / comparison procedure (documentation)

### Step 1 — Record the procedure in the plan

For each optimisation (Tasks 3–7):

1. The pre-change harness JSON is retained before the change.
2. The post-change JSON must be produced in the same session on the same machine.
3. The improvement must be visible in the specific scenario(s) the change targets.
4. If the improvement is not demonstrated, or any regression appears in the full suite
   or the interaction/boundary checks, the change is reverted and recorded as
   "measured, no benefit" in the completion report.

### Step 2 — Verify

Every task's commit is independently revertible (separate commits, listed in Task 5 of
each task).

### Step 3 — Commit

`docs(m15): document the optimisation comparison and rollback procedure`

---

## Task 11 — Final verification and M15 completion report

### Step 1 — Automated test evidence

- `python -m pytest tests -q` — record the literal output. Must be ≥212 passed with no
  existing test modified, skipped or weakened. Confirm with `git diff --stat` that no
  file under `tests/` that existed at baseline was changed.

### Step 2 — Performance evidence

- Re-run the full harness on the final state and write
  `config/m15_post_metrics.json`.
- Produce the acceptance table: baseline vs post per criterion A1–A11, with the
  scenario and JSON artifact named for each row. Any criterion that cannot be verified
  must be reported as unverified with the reason.

### Step 3 — Runtime verification

- Launch the real game; break and place blocks rapidly, including at chunk boundaries;
  observe water; traverse the generated world.
- Record measured frame times from the harness rather than asserting smoothness from a
  successful start-up. Where a display is unavailable, use the offscreen path and state
  clearly that GPU-side cost and human-visible smoothness were **not** verified.

### Step 4 — Memory verification

- Run a sustained session (fixed active set and growing active set) and report the
  measured memory trajectory against the active-region budget.

### Step 5 — Write the completion report

In `MILESTONES.md`, following the M14 report format, report:

- what was implemented;
- what was tested and the literal command/result;
- what was directly verified (runtime/measured) vs. source-inspected only;
- what was **not** verified (GPU cost, human-visible smoothness, other machines);
- remaining failures and limitations;
- the final milestone status.

Do not mark M15 complete unless every mandatory criterion in the spec's §6 is either
satisfied with evidence or explicitly reported as unverified.

### Step 6 — Commit

`docs(m15): report profiling results, adopted optimisations and remaining limitations`

---

## Final self-review checklist

- [ ] Harness measures game code unmodified, and diagnostic mode is separate from
      gameplay measurements.
- [ ] Baseline recorded **before** any optimisation, with 3 repetitions.
- [ ] Every numerical target in the spec's §6 table was fixed from the recorded
      baseline, not invented.
- [ ] `World.refresh()` semantics unchanged; all existing refresh-based tests pass
      unmodified.
- [ ] Block data changes are immediately observable (raycast/collision/water) after the
      deferred-reconcile change.
- [ ] Rendered mesh updates within one frame after a break/place, including boundaries.
- [ ] One rebuild per dirty chunk per reconcile; N edits in a frame do not produce N
      rebuilds.
- [ ] No single frame exceeds the approved mesh budget regardless of dirty-chunk count.
- [ ] Mesh output is byte-identical after Task 6 (golden test), and M12 face orientation
      tests pass.
- [ ] Water final state is cell-for-cell identical after Task 7; the full M13 suite
      passes unmodified.
- [ ] M14 generation, decorations and interaction non-interference tests pass
      unmodified.
- [ ] M6 player boundary tests pass unmodified.
- [ ] `python -m pytest tests -q` ≥212 passed, nothing skipped or weakened.
- [ ] No profiling code, timer, allocation or I/O added to the shipped per-frame path.
- [ ] Every optimisation either demonstrated its improvement or was reverted and
      reported as "measured, no benefit".
- [ ] Memory growth reported as measured, against the 28 KB × active-chunks budget.
- [ ] `MILESTONES.md` registers M15 as PLANNED — NOT IMPLEMENTED and is not marked
      complete.
- [ ] Untouched: textures, `config/texture_manifest.json`, dependencies, M1–M14
      gameplay code beyond the files listed above, and the pre-existing untracked files
      reported in the spec §2.1.
