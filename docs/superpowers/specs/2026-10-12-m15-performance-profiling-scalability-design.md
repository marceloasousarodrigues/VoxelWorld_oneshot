# M15 — Performance Profiling & Scalability: Design Spec

**Status:** IMPLEMENTED. Results, evidence and limitations are reported in the
"M15 Completion Report" section of `MILESTONES.md`. Targets in §6 were fixed from the recorded baseline
(`config/m15_baseline_metrics.json`) and the §9 decisions below were approved by the
user: §9.1 measure + contract only (no streaming), §9.2 fixed millisecond cap (≤8 ms),
§9.3 `World.reconcile()` called from `main.py:update()`, §9.4 low-risk hoisting and
precompute only (no numpy rewrite), §9.5 water runs after reconcile and is skipped when
reconcile has already consumed the budget.

**Date on the filename:** `2026-10-12`. The repository's established convention is
`docs/superpowers/{specs,plans}/YYYY-MM-DD-m<N>-<slug>.md` and the most recent
milestone documents are dated `2026-10-11`. The date in these two M15 filenames was
requested explicitly; the remaining convention (directory, slug, `-design` suffix on
the spec) matches the repository. See §9.6.

---

## 1. Objective

Diagnose the reported stutter when breaking blocks rapidly, establish a reproducible
performance baseline for VoxelWorld, and prepare a prioritised, evidence-based
optimisation plan for M15 that also addresses how the game scales as the world grows
towards a Minecraft-like size.

The milestone must:

1. Measure before it changes anything.
2. Distinguish *confirmed* bottlenecks from *unconfirmed* hypotheses.
3. Preserve the M1–M14 architecture and contracts, in particular:
   - the logical Chunk is the authoritative block store;
   - one combined terrain mesh and one Ursina Entity per rendered Chunk;
   - M13 water correctness and determinism;
   - M14 natural generation (grass tufts, trees) and its non-interference guarantees;
   - M6 player boundary behaviour and M7 chunk-boundary update behaviour.
4. Keep diagnostic profiling separate from code that ships in the final game.

M15 does **not** assume a cause. The cause identified below was measured on the
actual repository at commit `45d3ca0` on the machine described in §2.1.

---

## 2. Evidence from the current implementation

### 2.1 Environment and method

| Item | Value |
|---|---|
| Repository state | `main`, HEAD `45d3ca0` (`fix(m6): stop reads from generating chunks…`) |
| Pre-existing untracked files | `.freebuff/`, `.opencode/skills/ursina-doc/`, `.superpowers/sdd/2026-10-09…`, `tests_final_report.txt`, `voxel_textures/blocks_bck/` — reported, untouched |
| Python | 3.14.5 (MSC v.1944 64-bit) |
| Ursina / Panda3D / NumPy / pytest | 8.3.0 / 1.10.16 / 2.4.4 / 9.1.1 |
| Platform | Windows 11 (`Windows-11-10.0.26200-SP0`), 1920×1080 |
| Existing suite | `python -m pytest tests -q` → **212 passed in 13.83s** |

All measurements below were produced by throwaway scripts written **outside** the
repository (in the system temp directory) that import the game modules unchanged.
They created no project file. Two scenes were measured:

- **Headless** (`Chunk.entity is None`): isolates pure CPU cost of
  `generate_chunk_mesh_split` and `World.refresh`.
- **Offscreen Ursina** (`Ursina(window_type="offscreen", …)`): the exact `main.py`
  scene — `TerrainGenerator` seed 42 (3×3 chunks), one `create_chunk_entity` per
  chunk (9 entities created), `VoxelPlayer` spawned at `(8, 8, 8)`. This includes
  real Panda3D `Mesh` creation, `apply_foliage_cutout`, the transparent water child
  and `entity.collider = "mesh"` regeneration.

Note: `Ursina()` requires `application.asset_folder` to be a `pathlib.Path`; passing
a `str` raises `AttributeError: 'str' object has no attribute 'glob'` in Ursina 8.3.
`scripts/measure_baseline.py` already passes a `Path`, so the project is correct here.

### 2.2 Frame cost of a single block change — the reported stutter

| Scenario | Measured frame cost |
|---|---|
| Idle frame (9 chunk entities, player updating) | mean **0.65 ms**, p95 0.86 ms, p99 1.06 ms, max 1.16 ms, **0 frames > 16.67 ms** (n=240) |
| **One block change** (`world.set_block` + `world.refresh()`, entity attached) | mean **44.99 ms**, range 43.53–48.58 ms (n=12) |
| `world.set_block` alone | 0.0092 ms mean (n=200) |
| `world.refresh()` with nothing dirty | 0.00025 ms mean (n=200) |
| `generate_chunk_mesh_split`, one chunk, headless | 41.74 ms mean, atlas map preloaded (n=20); 42.69 ms mean with `atlas_map=None` (n=20) |
| `raycast` (6-block range) | 0.0025 ms mean (n=2000) |
| `player.find_ground_y` | 0.0069 ms mean (n=500) |
| `player.can_move_to` | 0.0011 ms mean (n=500) |
| Whole per-frame world-query set (ground + 2× move + raycast) | **0.0116 ms** mean (n=300) |

**Conclusion (confirmed).** A single block change costs ≈45 ms of main-thread CPU
with the real scene attached, i.e. **~2.7× the 16.67 ms 60 fps budget**. ~99.98 % of
that is `world.refresh()`; block data mutation itself is free. At a plausible click
rate of ~6 edits/s the game performs ~270 ms of blocking mesh work per second and
drops 2–3 frames per click. This is exactly the reported "slight stuttering when
breaking blocks rapidly", and it is reproduced on demand.

The measurement above used `world.set_block` + `world.refresh()`, which is the
identical sequence `VoxelPlayer.break_block()` executes after its raycast returns a
hit (`player.py:938-940`). A direct `player.break_block()` call in the harness
returned `None` because the harness camera orientation did not produce a ray hit, so
the player *raycast path* itself is evidenced only by the 0.0025 ms raycast cost and
by source inspection of `break_block`/`place_block`.

### 2.3 Redundant and unbounded rebuilds

| Scenario | Measured |
|---|---|
| 4 block changes in one frame, current path (4 × `refresh()`) | **174.70 ms** in one frame |
| The same 4 changes batched into **1** `refresh()` | **44.77 ms** |
| 3 consecutive single-block break+refresh cycles | 131.03 ms mean (n=10) |
| One edit at a chunk corner boundary → dirty set → frame | **3 chunks dirty, 120.21 ms** |
| Marking all 25 chunks of a 5×5 region dirty, then one `refresh()` | **171.34 ms in a single call** |

`World.refresh()` (`world.py:41-46`) rebuilds **every** chunk in `dirty_chunks` in
one call, with no count or time bound. `_mark_dirty_with_neighbors`
(`world.py:113-131`) adds the loaded boundary neighbour(s) for any edit on a chunk
face, so a single edit can legally dirty up to 3 chunks (measured: 3).

### 2.4 Where the mesh-generation time goes

`cProfile` over 6 `refresh()` calls (0.372 s total, 324,434 function calls):

| Function | Calls | tottime | cumtime |
|---|---|---|---|
| `chunk_mesh.generate_chunk_mesh_split` | 6 | 0.060 | 0.370 |
| `chunk_mesh._add_exposed_faces_to_split` | 11,691 | 0.068 | 0.262 |
| `block_data.is_block_solid` | **81,843** | **0.132** | 0.132 |
| `chunk_mesh._get_neighbor_block` | 70,146 | 0.030 | 0.040 |
| `chunk_mesh._get_face_uvs_optional` | 5,286 | 0.012 | 0.033 |
| `block_data.is_block_transparent` | 11,691 | 0.020 | 0.022 |
| `block_data.get_block_face_textures` | 5,913 | 0.014 | 0.016 |
| `chunk_mesh._add_cross_planes` (M14 foliage) | 402 | 0.002 | 0.003 |
| `texture_config.load_atlas_map` | 6 | 0.000 | 0.002 |

Per rebuilding of one chunk that is ≈13,600 `is_block_solid` calls and ≈11,700
`_get_neighbor_block` calls. `is_block_solid` alone is **35 % of total refresh
tottime** — a single `BLOCK_PROPERTIES[block_type]['is_solid']` dict lookup, called
once per cell and again per neighbour face.

Structural causes visible in `chunk_mesh.py`:

- `generate_chunk_mesh_split` is a Python triple loop over all 16³ = 4,096 cells for
  the block pass, **plus a second full 4,096-cell pass** for M14 decorations
  (`chunk_mesh.py:124-141`), even in chunks with no decorations.
- `_add_exposed_faces_to_split` rebuilds a 6-entry `faces` list containing 24 tuples
  **per block**, and calls `get_block_face_textures()` (which allocates a new 3-key
  dict) for every face it emits.
- `_get_neighbor_block` performs its own `is_loaded` plus world-coordinate conversion
  and then calls `world.get_block`, which repeats the same coordinate conversion.
- `Chunk.refresh` (`chunk.py:84-139`) regenerates **both** the opaque and the
  transparent pass and always constructs brand-new `Mesh` objects; buffers are never
  reused. It also re-invokes `apply_foliage_cutout` / `apply_water_material`, and
  re-assigns `entity.collider = "mesh"`.

### 2.5 Engine-side cost is NOT the dominant term

`generate_chunk_mesh_split` alone (headless, no entity) is 41.74 ms, while the full
attached path is 44.99 ms. Therefore Panda3D `Mesh` construction, node reassignment
and collider regeneration account for only ≈3 ms (≈7 %) of a rebuild. **The cost is
Python, in `chunk_mesh.py`, not the engine.** This downgrades the "engine call
overhead" hypothesis and rules out blaming Panda3D or the collision system.

Idle-frame `cProfile` (240 frames individually timed; a separate 120-frame profile
of `app.step()`) is dominated by Ursina/Panda3D per-frame machinery
(`GraphicsEngine.renderFrame`, `ursina.main._update`, `has_disabled_ancestor`,
`property_generator.default_getter`, `enabled_getter`) plus ~30 `player.get_block_at`
and ~37 `world.get_block` calls per frame — together ≈0.012 ms of world queries.
Idle headroom is effectively the whole frame budget.

### 2.6 Water (M13)

| Scenario | Measured |
|---|---|
| `seed_all_sources()` (9 chunks, 113 source cells) | 5.44 ms, once |
| Startup drain to quiescence | 113 ticks, **1030 ms total** |
| Active tick time (job in flood/solve) | mean **9.11 ms**, p50 8.77, p95 10.94, **max 13.16**, 0 ticks > 16.67 ms |
| `tick()` with no pending work | 0.00018 ms |

`main.py:update()` calls `water_sim.tick()` **every frame with no time budget**;
the internal bound is `DEFAULT_MAX_CELLS_PER_TICK = 65536` *cells*, not milliseconds.
At the current lake size this costs ≈9 ms on each of ~113 consecutive frames — over
half the frame budget for ~1.9 s — and would push any frame that also performs an
edit well past 33.33 ms. No single tick violates 16.67 ms at this scale, so this is
a sustained-cost and headroom problem rather than a spike generator, but it directly
competes with the interaction path for the same budget.

`WaterSimulation._commit` (`water.py:477`) calls `world.refresh()`, which inherits
the unbounded behaviour of §2.3.

### 2.7 Chunk lifecycle, memory and traversal scaling

| Measurement | Value |
|---|---|
| Per-chunk logical storage (`blocks`+`water_levels`+`water_sources`+`decorations`) | **28,672 B ≈ 28 KB** |
| 9 generated chunks (numpy arrays) | 258 KB |
| 289 loaded chunks (numpy arrays) | **7.90 MiB** (28.6 KB/chunk) |
| 289 loaded chunks (tracemalloc, whole process delta) | 8.13 MiB |
| Chunks created by `TerrainGenerator` | 9 (3×3, `y = 0` only) |
| Terrain generation for those 9 chunks | 76.33 ms total (≈8.5 ms/chunk), once at startup |
| `load_atlas_map()` (uncached read + JSON parse) | 0.18 ms mean (n=30) |

**Chunk lifecycle findings (source-confirmed):**

- There is **no chunk unloading and no view distance** anywhere in the project: a
  grep for `unload`, `view_distance`, `render_distance`, `chunks.pop`, `remove_node`
  finds only test names and docstrings. `World.get_chunk` (`world.py:48-69`) creates
  on demand and `World.chunks` is a plain `dict` that is never pruned.
- Membership is bounded today only because world generation is limited to 3×3 chunks:
  `TerrainGenerator._generate_height_map_terrain` iterates `range(-1, 2)` twice.
- Reading is safe against phantom growth: after the M6 fix, `World.get_block` never
  creates (`world.py:81-85`), `WaterSimulation`'s view reads `world.chunks` directly
  and `set_water` refuses to create (`world.py:196-199`). `player._chunk_exists`
  (`player.py:640-693`) deliberately avoids the creating getter. `player.get_block_at`
  still *contains* creating fallbacks (`player.py:768,779`) but they are unreachable
  in practice because `World.get_block` always returns an `int` and the function
  returns on the first branch — worth noting as latent risk, not an active defect.
- Consequence: memory scales with **loaded** chunks, which is the right model, but
  nothing bounds the loaded set. At 28 KB/chunk, a 33×33 region is ≈14.5 MiB while a
  1000×1000-chunk world would be ≈28 GiB, so "scalability towards Minecraft-like
  size" cannot be achieved by loading everything — a bounded active region is required.
- `World.generate_initial_terrain` (`world.py:258-290`) is **dead code**: nothing
  calls it. Noted for accuracy; not M15's business to remove.

### 2.8 Confirmed vs. hypothesis

**Confirmed bottlenecks (measured):**

1. Synchronous full-chunk mesh regeneration inside the interaction path (≈45 ms/edit).
2. No batching: N edits in one frame = N rebuilds (measured 3.9× overhead).
3. Boundary amplification: one edit can rebuild 3 chunks (measured 120 ms).
4. `World.refresh()` is unbounded in chunk count (measured 171 ms for 25 chunks).
5. Water `tick()` consumes ≈9 ms/frame with no time budget while work is pending.
6. No chunk lifecycle: unbounded loaded set, no unload, no view distance.
7. `load_atlas_map()` is uncached disk I/O on the hot path (0.18 ms; real, minor).

**Hypotheses that still require the M15 harness (not yet measured):**

- Allocation/GC pressure: per-chunk list growth, the per-block `faces` literal and
  the per-face `get_block_face_textures` dict are visible in source and in the profile,
  but their individual GC contribution has not been separated from raw CPU time.
- Draw-call and geometry scaling with visible chunk count (needs the real renderer;
  the offscreen harness can count entities/primitives but not GPU cost).
- Whether a numpy-vectorised visibility pass beats the loop version materially.
- Whether the lazy import of `chunk_mesh`/`chunk_entity` inside `Chunk.refresh`
  (`chunk.py:85,105,133`) has measurable import-lookup cost per rebuild.

**Hypotheses downgraded or dismissed by evidence:**

- *Panda3D/Ursina engine overhead dominates rebuilds* — dismissed: ≈3 ms of ≈45 ms.
- *Player collision, ground detection and raycasting cause the stutter* — dismissed:
  ≈0.012 ms/frame in total, and idle frames show 0 frames > 16.67 ms.
- *Terrain generation blocks gameplay* — not at present: 76 ms once at startup; it
  only becomes a per-frame hazard if dynamic chunk generation is ever introduced.
- *Blocking on the atlas file read is the stutter* — no: 0.18 ms vs 42 ms of mesh work.
- *Splitting a chunk into multiple rendered entities is needed* — **not justified by
  any measurement**. The architecture invariant (one entity per rendered chunk) stands.

---

## 3. Design decisions

### D1. Measure first, in a dedicated opt-in harness — never inside gameplay code

Profiling lives in `scripts/` as a standalone benchmark program, importing the game
modules unchanged, with JSON output under `config/`. It must add **zero** cost to the
shipped game. Any counter that remains in the final game must be a handful of integer
increments on an already-traversed code path (e.g. "chunks rebuilt", "rebuild µs"),
never a per-frame allocation, file write, or timer wrap.

### D2. Preserve `World.refresh()` exactly; move the *callers* to a deferred reconcile

All 212 existing tests either call `world.refresh()` directly or exercise a code path
that does. `refresh()` therefore stays a public, synchronous, immediately-effective
API. The optimisation is to stop `VoxelPlayer.break_block`/`place_block` and
`WaterSimulation._commit` from calling it *inline*, and to introduce a deferred
reconcile step driven by the frame loop:

- block data changes **immediately** (authoritative, observable by raycast,
  collision, water — no change to M1–M14 semantics);
- rendered meshes update once per frame at a controlled point.

Rendering lag is therefore at most one frame. This is invisible to `input()`-driven
tests, which call `world.refresh()` themselves, and preserves M7's requirement that
the rendered chunk reflects the change.

### D3. Batch all edits within a frame into at most one rebuild per dirty chunk

After D2 the dirty set is deduplicated by construction (`dirty_chunks` is a `set`).
Measured upper bound of the win: 4 edits/frame 174.70 ms → 44.77 ms.

### D4. Bound per-frame mesh work by a budget, and prioritise the player's edit

Reconcile rebuilds at most a bounded amount per frame (target to be fixed after Task 2;
provisional ≤8 ms). Chunks are ordered so that the chunk containing the most recent
edit is rebuilt first, keeping interaction feedback immediate; neighbours and
background chunks follow over subsequent frames. `dirty_chunks` therefore never grows
without bound while the player is idle-editing, and no single frame can be blown out
by a large dirty set.

### D5. Reduce `generate_chunk_mesh_split` cost **without changing its output**

The cheapest safe wins, in order of risk:

1. Hoist the per-block `faces` literal and the neighbour/UV tables out of the loop.
2. Precompute per-block-type UV rectangles and solid/transparent flags once (at
   import or first use) so the per-cell and per-face dict lookups collapse.
3. Cache `load_atlas_map()` with `functools.lru_cache(maxsize=1)` plus a
   `reset_cache()` hook, mirroring the existing `load_manifest` pattern in
   `texture_config.py:33-46`.
4. Collect decorations only if `chunk.decorations.any()` (skip a whole 4,096-cell
   pass for chunks with no foliage — the common case away from generation).

Any further change (e.g. a numpy-vectorised visibility pass) is a *separate*,
higher-risk task, gated on a golden-output test proving identical vertices,
triangles and UVs, because it touches the UV/face-order code that M12 guards.

### D6. Water: keep the solver, change only its scheduling

M13 semantics, determinism and the `set_water`/`_commit` contract are unchanged. Only
the *when* changes: `tick()` gains a time budget (and runs after interaction work), so
water cannot consume the frame the player is interacting in. Proof of correctness is
**final-state equivalence**: run an identical scenario to quiescence on the old and new
scheduling and compare block/water arrays cell-by-cell.

### D7. Chunk lifecycle: define and measure the bounded active model; do not silently
introduce streaming

M15 will (a) measure the loaded/dirty/visible counts and memory trajectory,
(b) define the bounded active-region contract and its numerical target, and
(c) expose it through the harness. Implementing real unload/view-distance streaming is
an architectural change touching the M6 boundary guard, the M13 water view and M14
vegetation ownership; §9.1 asks for an explicit decision before it is scheduled.

### D8. Diagnosis-only profiling stays out of the shipped game

`cProfile`, `tracemalloc`, per-frame timers and scenario drivers belong to
`scripts/profile_m15.py`. The permanent game keeps only cheap counters.

### D9. Rollback is part of every optimisation task

Each optimisation records a before/after benchmark JSON. If the required improvement is
not demonstrated, or a regression appears, the change is reverted and documented as
"measured, no benefit". No optimisation is kept on the strength of intuition.

---

## 4. Approaches considered

| Approach | Verdict |
|---|---|
| Profile first with a reproducible harness, then optimise | **Chosen** — the cause is measurable and the measurements contradict several plausible guesses. |
| Batch/amortise rebuilds (D2–D4) | **Chosen** — highest measured benefit, lowest correctness risk, keeps every invariant. |
| Reduce mesh-generator constant factors (D5) | **Chosen, ordered after D2–D4** — 42 ms → lower is the real prize, but it touches guarded geometry/UV code. |
| Time-budget water ticks (D6) | **Chosen** — ≈9 ms/frame of avoidable competition. |
| Split a chunk into multiple rendered entities | **Rejected** — no measurement supports it; violates architecture invariant 9. Could only be revisited with data and explicit approval. |
| Multithreading / multiprocessing (thread the mesh jobs) | **Rejected for M15** — Ursina/Panda3D entity and mesh assignment is main-thread state, Python's GIL bounds pure-Python mesh work, and chunk data ownership would need locking. Not justified before cheaper single-threaded wins are taken. |
| Multithreaded/blended rendering or LOD | **Out of scope** — no evidence, large architectural cost. |
| Greedy meshing | **Out of scope** — changes geometry/UV output, would break M12 face-orientation guarantees, and no measurement yet shows vertex count to be the bottleneck (a chunk is ≈3,880 opaque vertices). |
| Replace the renderer / engine calls | **Rejected** — engine overhead measured at ≈7 %. |
| Optimise collision/raycast | **Rejected** — measured at ≈0.012 ms/frame. |
| Cache the atlas map (D5.3) | **Chosen** — trivial, removes a per-rebuild disk read; honestly small (0.18 ms). |

---

## 5. Benchmark and testing strategy

### 5.1 The M15 harness (`scripts/profile_m15.py`, created by Task 1)

Deterministic scenarios, each independently runnable by name, with a fixed RNG seed
and a fixed world (TerrainGenerator seed 42, plus a documented procedural fill for
scenarios that need more chunks). Required scenario set:

1. Break one block.
2. Break blocks rapidly in succession.
3. Break blocks at chunk boundaries.
4. Place blocks rapidly.
5. Update chunks affected by block changes (dirty-set reconciliation).
6. Water simulation under increasing active area.
7. Generate and load chunks.
8. Move through the world while new chunks are generated.
9. Render terrain with increasing numbers of visible chunks.
10. Worlds containing grass, trees and active water.

Required measurements per scenario:

- frame time **p50 / p95 / p99 / max**;
- counts and percentages over **16.67 ms** and **33.33 ms**;
- CPU time attributed to interaction, world update/reconcile, mesh generation,
  water tick and chunk generation (independent of the mesh-gen figure above);
- number and duration of mesh rebuilds (calls, total µs, max µs);
- chunks **loaded / active / visible / unloaded** (visible = has an entity);
- pending work: `len(world.dirty_chunks)`, `len(water.pending_seeds)`,
  `water.active_job is not None`;
- memory over time (numpy bytes accounted for by `world.chunks`, plus
  `tracemalloc` process delta at sampling points);
- FPS as a **secondary** metric only.

Diagnostic-profiling mode (`--profile`) additionally enables `cProfile` and
`tracemalloc`; gameplay-measurement mode (`--frames N`) leaves both off so the
numbers are publishable as real frame costs.

### 5.2 Baseline and post-change protocol

- Baseline is recorded from the untouched `main` HEAD into
  `config/m15_baseline_metrics.json` (Task 2), with **3 repetitions** per scenario to
  establish run-to-run spread.
- Every optimisation task records an after JSON and states the delta per scenario.
- Comparisons use the same scenario set, the same seed, the same machine and the same
  mode; the plan requires the before/after pair to be produced in the same session.
- Numerical acceptance targets are **fixed at the end of Task 2** (§6) and are not
  invented in advance. The provisional targets in §6 come from the measurements in §2
  and must be confirmed or adjusted against the recorded baseline.

### 5.3 Automated tests

- **No existing test may be modified or weakened.** Baseline to preserve: 212 passed.
- New tests are added for: the harness's own metrics computation (percentiles,
  over-budget counts, attribution), the cached atlas map, batching/deduplication,
  the reconcile budget and its ordering guarantee, water final-state equivalence, and
  the golden mesh-output comparison for D5.
- M1–M14 regression coverage must be part of the acceptance run, specifically:
  `tests/test_break_block.py`, `tests/test_place_block.py`,
  `tests/test_chunk_refresh.py`, `tests/test_world_dirty_tracking.py`,
  `tests/test_player_boundary.py`, `tests/test_raycasting.py`,
  `tests/test_m12_face_orientation.py`, `tests/test_chunk_mesh.py`,
  `tests/test_tree_chunk_boundaries.py`, `tests/test_vegetation_interaction.py`,
  `tests/test_water_rules.py`, `tests/test_water_chunk_integration.py`,
  `tests/test_water_mesh_culling.py`.
- Runtime verification uses the real game (onscreen where a display is available,
  otherwise offscreen with an explicit statement of the limitation) and reports
  measured frame times rather than a startup success claim.

---

## 6. Acceptance criteria mapping

Every criterion below is either **derived from the §2 measurements** or explicitly
marked as a **target to be established after Task 2's recorded baseline**. No
performance improvement is claimed anywhere in this document.

| # | Criterion | Basis |
|---|---|---|
| A1 | Interaction no longer produces a frame > 33.33 ms attributable to mesh work. **Target: single-edit reconcile ≤ 8 ms; no frame > 33.33 ms in the edit scenarios.** | Confirmed violation: 44.99 ms/edit measured; recorded baseline `break_one` p50 47.74 ms. |
| A2 | During a rapid-break session the p95 frame time is **≤ 16.67 ms** and the count of frames > 16.67 ms attributable to mesh rebuilds falls by **≥ 80 %** vs. baseline. | Recorded baseline `break_rapid` p50 75.59 ms / p95 174.54 ms, 300/300 frames over budget. |
| A3 | One block change triggers at most one rebuild per affected chunk, and a boundary edit's frame cost is bounded by the per-frame budget (≤ 8 ms) rather than scaling with the dirty-chunk count. | Confirmed: boundary edit → 3 chunks; recorded baseline `break_boundary` p50 93.24 ms. |
| A4 | No unbounded accumulation: after the player stops editing, `dirty_chunks` and the water pending set return to empty and the harness asserts it. | Confirmed: `refresh()` rebuilds all dirty chunks (25 → 171.34 ms); baseline `dirty_reconcile` flushes all loaded chunks in one call. |
| A5 | `generate_chunk_mesh_split` produces byte-identical vertices/triangles/UVs before and after D5 for a fixed set of chunks. | Correctness gate for the 42 ms hot spot. |
| A6 | Water scheduling change shows cell-for-cell identical final state when run to quiescence. | M13 determinism preserved. |
| A7 | Water's per-frame cost while active is bounded by a budget of **≤ 8 ms** and no longer consumes > 50 % of the frame on average. | Recorded baseline `water_active` p50 9.11 ms / p95 11.39 ms / max 12.95 ms. |
| A8 | Memory during sustained traversal is bounded by the active-region model; with a fixed active set, per-chunk storage growth is flat and the harness reports loaded/visible counts and numpy bytes over time. Active-region budget stated as **28 KB × active chunks**. | Confirmed: 28,672 B/chunk; 289 chunks = 7.90 MiB; no unload exists. |
| A9 | Chunk loading, unloading, regeneration and boundary behaviour remain correct (no visible boundary holes left stale for more than one frame beyond the fixed budget). | M7 chunk-boundary contract; new batching tests. |
| A10 | `python -m pytest tests -q` reports no fewer than the 212 tests that pass at baseline, with no test weakened or skipped. | §5.3. |
| A11 | All diagnostic profiling is opt-in and absent/zero-cost when disabled. | D1/D8. |

---

## 7. Non-goals

- Implementing dynamic chunk streaming/unloading without the §9.1 decision.
- Changing chunk dimensions (16×16×16) or the one-entity-per-chunk model.
- Any change to M13 water semantics, levels, spread rules or determinism.
- Any change to M14 generation rules, textures, atlas contents or decorations.
- Greedy meshing, LOD, multithreading, GPU/compute shaders, renderer replacement.
- Rewriting M1–M14, refactoring unrelated modules, or "cleaning up" dead code such as
  `World.generate_initial_terrain`.
- Touching textures, `config/texture_manifest.json`, or dependencies.
- Editing `MILESTONES.md` beyond registering M15 as PLANNED — NOT IMPLEMENTED.

---

## 8. Risks, limitations and open questions

| Risk | Mitigation |
|---|---|
| Deferred rebuild introduces visible render lag. | ≤1 frame by design; boundary-neighbour test; runtime visual check that breaking/placing still looks immediate. |
| Budgeting rebuilds leaves a boundary face stale for >1 frame. | Containing chunk is rebuilt first; neighbours follow; A9 asserts the maximum staleness. |
| Rewriting mesh internals breaks face orientation / UVs (M12). | Golden-output equality test (A5) before any speed claim; M12 tests gate the change. |
| Water scheduling change alters results. | Final-state equivalence test to quiescence (A6). |
| Offscreen measurements miss GPU cost. | All frame-cost claims are CPU/main-thread; GPU/draw-call scaling is measured only as counts and reported as not verified on the GPU. |
| Measurement machine dependence. | Every recorded JSON carries Python/Ursina/Panda3D/platform/resolution and the scene description (the existing `config/baseline_metrics.json` already does this). |
| Scope creep into streaming/LOD. | §7 non-goals; §9.1 decision gate. |

**Limitations of the §2 evidence, stated explicitly:** measurements are from one
machine (Windows 11, 1920×1080), offscreen for the entity-attached numbers, with
vsync disabled; the player raycast-hit path was not driven end-to-end, so the per-edit
figure represents the identical `set_block` + `refresh` sequence that `break_block`
performs after a hit, not a synthesised mouse click. No GPU-side attribution was made.

**Open questions:**

- Is the ≈9 ms/water-tick cost dominated by the flood/solve traversal or by
  `_make_view`/`is_loaded`/`get_block` overhead? To be attributed in Task 1.
- Is any of the idle 0.65 ms/frame (offscreen) attributable to VoxelWorld code rather
  than Ursina, once GPU work is excluded? Minor; to be captured as a scenario.
- What is the real cost of `entity.collider = "mesh"` regeneration versus `Mesh`
  construction? Currently ≈3 ms combined; may not be worth separating.

---

## 9. Decisions requiring explicit approval before implementation (APPROVED)

The user approved the plan on 2026-10-11 and with it the following decisions, taken
exactly as recommended:

1. **Chunk lifecycle scope — APPROVED: measure + contract only.** M15 defines and
   measures the bounded active model; streaming/unloading is a separate milestone.
   Streaming changes M6's generated-world boundary guard, M13's water view and M14's
   vegetation ownership, so it remains an architectural change outside M15.
2. **Per-frame mesh budget form and value — APPROVED: fixed millisecond cap of 8 ms**
   (`World.DEFAULT_MESH_BUDGET_MS`), with the edited chunk rebuilt first.
3. **Deferred reconcile shape — APPROVED.** `World.refresh()` keeps its synchronous
   API; only its callers move. The reconcile hook is a new `World.reconcile()` method
   called from `main.py:update()`, where the water tick already runs.
4. **Mesh-internals rework scope — APPROVED: low-risk hoisting/precompute only.**
   No numpy-vectorised visibility rewrite in M15.
5. **Water scheduling ordering — APPROVED.** Reconcile runs first; water runs after
   and is skipped on a frame where reconcile has already consumed the budget.
6. **Document date convention.** These two documents are dated `2026-10-12` as
   requested while the repository convention (and today's date) implies `2026-10-11`.
   Confirm the intended filename date. Actual paths produced:
   - `docs/superpowers/specs/2026-10-12-m15-performance-profiling-scalability-design.md`
   - `docs/superpowers/plans/2026-10-12-m15-performance-profiling-scalability.md`
7. **Documentation inconsistency (reported, not fixed).** `AGENTS.md` §1 lists
   `PLAN.md` as a source of truth for development workflow, but `PLAN.md` does not
   exist in the repository. This spec and plan follow the M14 Superpowers document
   conventions (`docs/superpowers/{specs,plans}/`, `-design` spec suffix).
8. **Pre-existing untracked changes.** Reported in §2.1; M15 touches none of them.
