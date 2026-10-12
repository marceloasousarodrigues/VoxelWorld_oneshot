# Post-M16 Readiness Review — VoxelWorld

**Date:** 2026-10-12
**Type:** inspection and planning only. No production code was modified, no milestone started,
nothing committed or pushed.

**Target direction being assessed:** a first-person voxel survival RPG with a large
explorable world, inventory, crafting, building, farming, settlement management, resident
NPCs and enemy raids.

**Method:** every claim below was checked against code, tests or recorded artifacts. Where a
claim could not be checked it is marked as such. Evidence is given as `file:line`.

---

## 1. Current state and the Git checkpoint recommendation

| Item | Value |
|---|---|
| HEAD | `9a3177a` — `feat(m15): complete performance profiling and budgetable water commits` |
| Branch | `main` (no other local branches) |
| Remote | `origin` = `git@github.com:marceloasousarodrigues/VoxelWorld_oneshot.git` |
| Tags / stashes | none / none |
| Staged | nothing staged |
| Working tree | 10 modified tracked files, 213 untracked files (155 texture assets + 42 M16 files + 16 agent-state files) |

### 1.1 The headline risk

**The whole of M16 — streaming, the four stutter fixes, its tests and its reports — exists
only in the working tree.** `HEAD` is still the M15 commit. Any `git checkout`, `git clean`,
`git reset --hard`, branch switch or agent misfire destroys it irrecoverably.

### 1.2 Classification of every change (verified, not assumed)

All ten modified tracked files were read as diffs and are unambiguously M16 work:

| File | Nature of the change |
|---|---|
| `world.py` | M16 chunk lifecycle: `begin_chunk_load`/`finish_chunk_load`/`load_chunk`/`unload_chunk`, edit overlay, neighbour dirtying, water-version bump |
| `terrain_generation.py` | M16 per-chunk entry points `generate_chunk` / `generate_chunk_terrain` extracted from the whole-world loop |
| `water.py` | M16 `seed_chunk_sources` (per-chunk source seeding for streaming) |
| `chunk.py` | M16 `generated` provenance flag; stutter-fix `has_transparent_block` |
| `chunk_entity.py` | M16 placeholder/`apply_chunk_mesh` split; stutter-fix vectorised scan call |
| `block_data.py` | Stutter fix 2: `TRANSPARENT_BLOCK_TYPES`, `has_transparent_block` |
| `highlight.py` | Stutter fix 4: reusable highlight entities |
| `main.py` | M16 streamer wiring + `gc_tuning.apply()` |
| `ARCHITECTURE.md` | §13 Chunk Lifecycle & Streaming, staged loading, persistence policy |
| `MILESTONES.md` | M16 section, M16 completion report, M16 follow-up report |

Untracked M16 files, enumerated exactly (42): the modules `chunk_streaming.py`, `world_config.py`,
`gc_tuning.py`; `config/world_config.json` plus 18 measurement JSONs under `config/`
(`m16_stutter_*` × 11, `m16_rep{1,2,3}.json`, `m16_attribution.json`, `m16_after_attribution.json`,
`m16_after_scan.json`, `m16_streaming_metrics.json`); **13** × `tests/test_m16_*.py`; 3 ×
`scripts/{measure_m16_streaming,profile_m16_attribution,profile_m16_stutter}.py`; and 5 ×
`docs/superpowers/{specs,plans}/*m16*`.

### 1.3 Pre-existing work that is NOT M16 (do not commit, do not delete)

| Path | Assessment |
|---|---|
| `voxel_textures/blocks_bck/` (**155 files**) | **User asset library.** `MILESTONES.md:1233` and `:1319` record that *the environment renamed* `voxel_textures/blocks/` → `blocks_bck/`. It holds 155 source textures — `blocks_bck/*.png` (87) plus `blocks_bck/plants/` (59) and `blocks_bck/plants/crops/` (9, including `carrots_stage1..3.png`) — of which the tracked `voxel_textures/blocks/` has only 7. It is the **only copy** of those assets, and it already contains crop-stage art useful to a future farming milestone. Both the M15 and M16 design docs list it as "Pre-existing untracked files … reported, untouched". |
| `.freebuff/`, `.opencode/skills/ursina-doc/`, `.superpowers/sdd/…` (16 files) | Agent/tooling state, same provenance. |
| `tests_final_report.txt` | Stray UTF-16 pytest log at the repo root (from an earlier session). Harmless content, actively harmful to collection (see §2.3). |

### 1.4 Recommended checkpoint (before any further implementation)

1. **Extend `.gitignore` first** (it currently covers only `__pycache__/`, `.pytest_cache/`, `*.py[cod]`, venvs, `.opencode/agents_bck/`) to exclude `.freebuff/`, `.superpowers/`, `tests_final_report.txt` and the bulk measurement JSONs.
2. **Commit M16 in reviewable units, never `git add -A`**: (a) lifecycle/streaming code + `world_config.py` + `config/world_config.json`; (b) the four stutter fixes + `gc_tuning.py`; (c) the 12 M16 test modules; (d) the profiling scripts and a *curated* subset of `config/m16_*.json` (the 16 ~34 KB stutter runs need not all be kept); (e) docs (`ARCHITECTURE.md`, `MILESTONES.md`, specs/plans).
3. **Leave `voxel_textures/blocks_bck/` untracked** and ask the owner whether to commit it as an asset library or ignore it. Do not delete it.
4. **Tag the M16 checkpoint** (e.g. `m16`) so the pre-M17 state is addressable.
5. Until step 2 is done, avoid any command that rewrites the working tree.

---

## 2. What actually exists (verified)

### 2.1 Code inventory

Root modules (5,688 lines total): `player.py` 1026, `world.py` 696, `water.py` 626,
`chunk_mesh.py` 595, `vegetation.py` 441, `chunk_entity.py` 286, `terrain_generation.py` 267,
`chunk_streaming.py` 264, `chunk.py` 196, `raycast.py` 149, `block_data.py` 146, `main.py` 112,
`world_config.py` 103, `inventory_ui.py` 100, `test_world.py` 99, `texture_config.py` 95,
`highlight.py` 91, `texture_manager.py` 90, `inventory.py` 86, `gc_tuning.py` 77,
`debug_main.py` 51, `coordinate_system.py` 48, `main_original.py` 44.

Systems present and working: chunked voxel world (16³), deterministic terrain + lake,
vegetation (trees/tufts), water simulation with a version gate and budgets, face-culled split
opaque/transparent meshes, atlas + per-face texture configuration, first-person player with
collision/raycast/break/place, hotbar + inventory primitives, chunk streaming with staged
loading, GC-tuning policy, and a real profiling/measurement harness.

### 2.2 Test and measurement state (re-verified today)

- `python -m pytest tests -q` → **334 passed, exit 0, 27 s**. Matches the M16 report.
- 54 test modules under `tests/` (6,624 lines) **plus** a stray root-level `test_world.py` (8 tests) → 342 total.
- M16 perf artifacts spot-checked: `config/m16_stutter_after_2.json` has `meta.gc_tuning: true`,
  `windowed: true`, `vsync: false`, `cross_boundary` max 27.88 ms with 0 frames over 33.33 ms,
  `explore` max 31.93 ms with 0 over 33.33 ms. The recorded numbers match the report.
- `scripts/`: `measure_baseline.py`, `measure_water_commit.py`, `measure_m16_streaming.py`,
  `pack_textures.py`, `profile_m15.py`, `profile_m16_attribution.py`, `profile_m16_stutter.py`.

### 2.3 A newly found, reproducible defect in the verification workflow

**Bare `python -m pytest` from the repo root is broken.** `python -m pytest --collect-only -q` at the
root reports **`342 tests collected, 1 error`** and exits **2**, with
`ERROR collecting tests_final_report.txt — UnicodeDecodeError: 'utf-8' codec can't decode byte 0xff`.
The file is confirmed UTF-16 little-endian. Pointing pytest straight at it
(`python -m pytest --collect-only -q tests_final_report.txt`) reproduces the identical error, so the
stray file — not the test code — is the cause. `python -m pytest tests -q` bypasses it and exits 0.

There is **no pytest configuration anywhere** (no `pytest.ini`, `pyproject.toml`, `setup.cfg`
or `conftest.py` in the repo or any parent), `PYTEST_ADDOPTS` is unset, and every test module
repeats its own `sys.path.insert` boilerplate. The working invocation is therefore an
undocumented convention (`pytest tests`), which any future contributor or CI job would get wrong.

### 2.4 Evidence-quality findings in the measurement harness

Re-reading the artifacts (not just the report) surfaced three things worth recording:

1. **The published numbers reproduce.** `config/m16_stutter_after_2.json` has
   `meta.gc_tuning=true`, `windowed=true`, `vsync=false`; `cross_boundary` max **27.88 ms** with
   `over/33.33 = 0`, `explore` max **31.93 ms** with `over/33.33 = 0`, `stand_still`/`rotate`/
   `walk_loaded`/`boundary_repeat` all 0 over 33.33 ms. The report's claims check out.
2. **The artifacts' environment provenance is incomplete.** Every M16 run records
   `meta.ursina = "unavailable"`, yet ursina **8.3.0 is installed and is used by the harness**
   (verified by import). `_version()` in `scripts/profile_m16_stutter.py:746` reads a module's
   `__version__`, which ursina does not expose; `importlib.metadata.version("ursina")` returns
   `8.3.0`. So the recorded engine version — the single most important dependency for
   reproducibility — is silently missing. `python` (3.14.5), `panda3d` (1.10.16) and `numpy`
   (2.4.4) *are* recorded.
3. **The worst frames are still structural, not just machine noise.** The 27.88 ms
   `cross_boundary` spike decomposes as `reconcile_ms` 14.87 + `mesh_ms` 14.85 (overlapping — the
   neighbour remesh happens *inside* reconcile) on the same frame as `streamer_ms` 10.08 and
   `terrain_ms` 8.69; the 31.93 ms `explore` spike carries `gc_pause_ms` 12.22 on top of
   `reconcile_ms` 19.5. Staged loading separated *streamer* load work from mesh work, but a
   neighbour remesh triggered by a load still lands in the same frame, and GC still lands in the
   worst frame. Both partially corroborate the report's honest limitation of ≈29–31 ms load frames.
   The artifacts also self-document two limitation strings (GPU async with vsync off; camera driven
   by the harness rather than by raw mouse input), which is good practice worth keeping.

---

## 3. Missing foundations

Each gap states **status · evidence · dependencies · blocking? · recommended milestone · acceptance criteria**.

### G1 — Reproducible environment and dependency pinning
- **Status:** missing. **Blocking.**
- **Evidence:** no `requirements*.txt`, `pyproject.toml`, `setup.py`, `Pipfile`, `environment.yml`,
  lockfile, `Dockerfile`, `README` or `LICENSE` anywhere in the repo (searched, none found).
  `.gitignore` expects a `.venv/`, but there is **no project virtualenv**; the code runs against a
  user-level install (`C:\Users\Admin\AppData\Local\Python\pythoncore-3.14-64\python.exe`) with
  unpinned ursina 8.3.0, Panda3D 1.10.16, numpy 2.4.4, pytest 9.1.1, pillow 12.2.0.
- **Dependencies:** none. **Blocks:** all subsequent verification (G2), reproducibility, and CI.
- **Placement:** M17, task 1.
- **Acceptance criteria:** a dependency manifest with pinned versions and a documented single
  setup command; a fresh clone installs and runs `pytest tests` green on a clean machine;
  the interpreter and all direct dependencies are declared; the pipeline is documented in a README.

### G2 — Test, profiling and runtime-verification workflow
- **Status:** partially present, with one blocking defect and no automation. **Blocking.**
- **Evidence:** 334 tests pass, but bare `pytest` exits 2 (§2.3); no `.github/workflows` (the
  `.github/` directory exists and is empty); no coverage, no markers, no slow-test separation;
`test_world.py` sits outside `tests/` — a `unittest.TestCase` module whose 8 tests are part of the
342 (`python -m pytest --collect-only -q test_world.py` → `8 tests collected`); each module
duplicates path setup; `tests_final_report.txt` breaks collection. Profiling exists and is genuinely good (two profilers, phase attribution,
  before/after JSON artifacts) but the loop is manual.
- **Dependencies:** G1. **Blocks:** confidence in every later milestone; regression protection.
- **Placement:** M17.
- **Acceptance criteria:** `pytest` and `pytest tests` both exit 0 from a clean clone; a test
  configuration declares `testpaths`/`rootdir`; shared fixtures replace per-file path boilerplate;
  a CI job runs the suite on every change; stray, non-test artifacts cannot break collection;
  a documented, repeatable performance-baseline command exists and its budgets are recorded;
  the profilers' `meta` records the **engine version that actually produced it**
  (§2.4 finding 2 — `meta.ursina` currently says `unavailable` while ursina 8.3.0 is in use).

### G3 — World persistence and save-format evolution
- **Status:** absent **by explicit design**, and now the critical missing foundation. **Blocking.**
- **Evidence:** the only `json.load` calls are configuration reads (`texture_config.py:41,89`,
  `world_config.py:48`); no writes of world state anywhere. `ARCHITECTURE.md:291` states plainly:
  *"Persistent on-disk save/load of the world is not part of this architecture; it would be a
  separate milestone."* M16's non-goals repeat it, and M8's out-of-scope list already deferred
  "World persistence and save/load". Player edits live in the in-memory overlay
  `World.block_overrides` / `decoration_overrides` and survive an unload/re-entry **only within one
  session**. The terrain seed is hard-coded (`terrain_generation.py:108`, `self.seed = 42`), so a
  save format must carry it explicitly. There is no schema, no version field and no migration path.
- **Dependencies:** G1/G2 (a save format needs a reproducible test harness). **Blocks:** everything
  that must survive a restart — buildings, crops, inventories, NPC and settlement state.
- **Placement:** M18 (first gameplay-architecture milestone).
- **Acceptance criteria:** a versioned save file records seed, player state, inventory and the edit
  overlay; save→load round-trips to an identical logical world (block-for-block) with an equivalence
  test; writes are atomic and a truncated/corrupt file is detected rather than silently accepted;
  the schema carries a version and an unknown/newer version is refused with a clear error; a
  migration hook exists and is exercised by a test.

### G4 — Separation of logical world data from rendering
- **Status:** strong — the project's best-developed foundation. **Not blocking; preserve it.**
- **Evidence:** `ARCHITECTURE.md` §1–§9 and invariants 1–9; M16's staged load makes the separation
  explicit (`begin_chunk_load` completes authoritative data before any geometry exists). `World` and
  `Chunk` hold only logical data; meshes are built by `chunk_mesh.py` and entities by
  `chunk_entity.py`.
- **Residual coupling to watch:** `Chunk` stores `entity` / `entity_transparent` render handles
  (`chunk.py:23-24`), and `player.py` is a 1,026-line class mixing movement, collision, raycast,
  interaction, inventory and camera. Neither is a violation today, but both will make M19/M23 harder.
- **Dependencies:** none. **Placement:** no milestone of its own; enforce in M17 (CI) and refactor
  opportunistically in M19/M23.

### G5 — Item definitions, stacks and inventory architecture
- **Status:** minimal prototype. **Blocking for crafting, farming and NPC logistics.**
- **Evidence:** `inventory.py` defines `ItemStack(item_type: BlockType, quantity: int)` — items *are*
  block types; there is no item registry, no non-block items (tools, food, seeds, currency), no
  per-item stack size (the cap `64` is hard-coded in `can_add`/`add_item`), no durability or
  metadata, and no item definitions data file. `Inventory(size=27)` is a flat list of optional
  stacks (`inventory.py:5-10`). `inventory_ui.py` renders **only 9 slots** — `for i in range(9)` at
  `inventory_ui.py:23` and `:70`, against the declared `size=27` — so
  the remaining 18 of the declared 27 are unreachable through the UI; there is no full-grid screen,
  no cursor stack, no drag/drop, and no equipment slot.
- **Dependencies:** G3 (an inventory that cannot be saved is not a foundation). **Blocks:** M20
  crafting, M22 farming, M24 settlement logistics.
- **Placement:** M19.
- **Acceptance criteria:** a data-driven item registry distinguishing placeable blocks from usable
  items, with id, display name, stack size, icon and category; the inventory stores item ids, not
  `BlockType`; per-item stack limits honoured by add/remove/split/merge; a full inventory grid with
  cursor-held stack and slot-to-slot transfer; equipment slots; save/load round-trip of the whole
  inventory state; regression tests that existing block placement and collection behaviour is
  unchanged.

### G6 — First-person character, equipment and interaction
- **Status:** partially present (movement/collision/interaction), no equipment or survival stats.
- **Evidence:**  `player.py` implements input, horizontal/vertical movement, collision
  (`can_move_to:425`, `body_intersects_solid:508`), ground finding, raycast interaction
  (`get_interaction_ray:903`), `break_block:917`, `place_block:967` and hotbar selection
  (`hotbar_index`, `player.py:54,173`).
  Verified absent: `health` (0 matches), `damage` (0), `hunger|stamina|food` (0),
  `sprint|crouch|sneak` (0), `auto_step|step_up` (0) — the last of these corroborates the
  measured behaviour that a 2-block rise wedges the player. No equipment/hand/view-model layer.
  `block_data.py` is a Python `IntEnum` plus a hard-coded property dict, not content data.
- **Dependencies:** G5 for tools/equipment. **Placement:** M19 (equipment, tool-gated breaking)
  and a later combat milestone for health/damage.
- **Acceptance criteria:** equipment slots affect breaking speed/yield; tool-gated block breaking
  with a data-driven tool-type mapping; movement gains step-up (or an explicit decision to keep the
  current behaviour) with a regression test; every new stat is persisted (G3).

### G7 — Crafting, construction and farming prerequisites
- **Status:** absent. **Blocking for the survival loop.**
- **Evidence:** no `craft|recipe|smelt|furnace` matches in code or JSON. Construction is single-block
  `place_block` only — no blueprints, no multi-block structures, no rotation. Farming has nothing:
  no crops (`farm|crop|harvest` matches are all `pillow.crop` in `scripts/pack_textures.py`), and no
  block-state/metadata layer for growth stages — the closest precedent is the separate `decorations`
  int8 array in `chunk.py`, which shows the project can carry side-channel layers but has no general
  mechanism. There is also no scheduled-update system for growth; water has a bespoke job system
  (`water.py`) that is not general.
- **Dependencies:** G5 (recipes consume items; crops are items), G3 (crop state must persist),
  and a general scheduler (G8/G9). **Blocks:** the farming and building pillars.
- **Placement:** M20 (crafting + construction foundations), M22 (farming, after the scheduler).

### G8 — Actor/entity framework, NPCs, jobs and raids
- **Status:** absent, and the largest architectural gap. **Blocking.**
- **Evidence:** no `\bnpc\b|resident|villager|raid|enemy|mob|pathfind|spawn_entity` matches anywhere
  in Python code. There is no non-chunk entity lifecycle (the only entities are chunk entities and
  the player), no pathfinding, no navigation graph, no spatial query beyond single-block lookups
  (`World.get_block`, `World.is_loaded`) and no broad-phase structure, no job/scheduler abstraction,
  no inventory-transfer API (only `Inventory.add_item`/`remove_qty` on a local inventory), and no
  world clock — `time_of_day|world_time|clock|tick_schedul` yields 2 incidental matches only.
- **Dependencies:** G3 (NPC/settlement state must persist), G5 (carried items), a scheduler, and
  spatial queries. **Blocks:** M23, M24, M25.
- **Placement:** M21 (temporal/scheduler layer), M23 (actors + NPCs), M24 (settlement + logistics),
  M25 (combat/raids).

### G9 — Temporal systems (world clock and scheduled updates)
- **Status:** absent. **Blocking for growth, NPC schedules and raids.**
- **Evidence:** `main.py:update()` runs `reconcile`, `streamer.update`, water `consume_changes`/`tick`
  — a fixed per-frame loop with no notion of game time; no day/night, no calendar, no per-block
  scheduled updates. Water's version-gated job system is the only precedent for deferred work.
- **Dependencies:** G1/G2. **Placement:** M21.
- **Acceptance criteria:** a monotonic world-time value advanced from frame deltas, persisted in the
  save; a scheduler that can register deferred per-chunk/per-block work with a due-time and a
  per-frame work budget (generalizing the water pattern); tests proving determinism for a fixed
  number of ticks and bounded per-frame cost.

### G10 — Optional tooling (explicitly *not* blocking)
- CI performance-regression gate comparing new `config/*.json` against recorded budgets.
- Coverage reporting; mutation testing; determinism/golden-mesh harness generalization beyond M15's.
- A debug/observer overlay (chunk state, entity counts, timing) — valuable specifically because this
  environment **cannot inspect rendered pixels**, which is the one verification class the project
  has never been able to perform.
- Automated content pipeline: `scripts/pack_textures.py` runs manually and its determinism is
  unverified; a content/asset manifest check would help M19's item icons.

---

## 4. Proposed milestone sequence

Existing history (M6–M16 as recorded in `MILESTONES.md`, plus the M16 follow-up) is preserved
unchanged. New work is appended; nothing is renumbered or rewritten.

```
M17  Project Infrastructure & Reproducible Environment   [essential infra]  <- recommended next
M18  Persistence & Save System                            [essential infra]
M19  Item & Inventory System (generalized) + Equipment     [essential]
M20  Crafting & Construction Foundations                   [essential]
M21  Temporal Systems (world clock + update scheduler)     [essential infra]
M22  Farming & Settlement Building                         [feature]
M23  Actor Framework & Resident NPCs                        [feature/platform]
M24  Settlement Management & Resource Logistics             [feature]
M25  Enemies, Combat & Raids                                [feature]
```

Dependency edges: M17 → M18 → M19 → {M20, M22, M23}; M21 → {M22, M23}; M23 → {M24, M25};
M19 → {M24, M25}. M20 → M22 (farm plots need building). M24 → M25 (a settlement worth raiding).

Suggested acceptance criteria per milestone:

| Milestone | Acceptance criteria (summary) |
|---|---|
| **M17** | Pinned dependency manifest + lockfile + virtualenv; documented setup; README; `pytest` exits 0 from a clean clone; CI green; test config replaced per-file path hacks; M16 committed and tagged; stray artifacts cannot break collection; recorded performance budget command |
| **M18** | Versioned, atomic save/load of seed, player, inventory and edit overlay; block-for-block round-trip equivalence test; corruption detection; version refusal + migration hook; save size and load time measured |
| **M19** | Data-driven item registry (blocks vs items); per-item stack sizes; full grid UI with cursor stack and transfers; equipment slots; tool-gated breaking; inventory persists; existing collection/placement regression-free |
| **M20** | Recipe data + validation; crafting UI; station blocks; multi-block placement with rotation; crafted output enters inventory; deterministic and persisted |
| **M21** | World clock from frame deltas, persisted; deferred-update scheduler with due-times and a per-frame budget; deterministic tick tests; bounded cost measured |
| **M22** | Crop items, planting on valid soil, growth stages driven by M21, harvest yields; crops persist across save/load; plot/building ownership |
| **M23** | Non-chunk actor lifecycle with spawn/despawn budgets; grid pathfinding; needs/behaviour loop; NPCs persist and are scheduled by M21; ≤ N actors at bounded per-frame cost |
| **M24** | Job assignment, storage containers, resource transfer between inventories, production quotas, settlement UI state; logistics survive save/load |
| **M25** | Health/damage, weapons/armour, raid spawning with warning, defense outcomes, death/respawn; all balanced content persisted |

---

## 5. Recommendation: the next implementation milestone is **M17 — Project Infrastructure & Reproducible Environment**

**Why its dependencies are satisfied:** M17 needs only the existing codebase and test suite, both
present and verified today (334 tests pass; M16 code and reports exist). It has no dependency on
persistence, items or actors, so there is nothing for it to wait on.

**Why it must come first:**

1. **Nothing is currently reproducible.** There is no dependency manifest and no pinned versions —
   the suite runs against a global, machine-specific install. Every future milestone's verification
   baseline inherits that unreliability, and the `python -m pytest` collection defect (§2.3) shows the
   gap is real rather than theoretical.
2. **The 334-test safety net is unprotected.** No CI, no coverage, no markers: the only regression
   protection for a project about to add five subsystems is a human remembering to run `pytest tests`.
3. **It is the milestone that makes M16 durable.** The M16 checkpoint (Task 1) belongs in its first
   task, and the working tree currently holds ~1,500 lines of uncommitted milestone work.
4. **It is the lowest-risk, highest-leverage step.** It changes no gameplay behaviour and touches no
   architecture invariant, so it cannot destabilise M1–M16 — while visibly accelerating every
   milestone after it.
5. **Later milestones would be designed against the wrong substrate without it.** M18's save format
   and M19's item registry are both *data-schema* designs; they should follow M17's establishment of
   the project's data/manifest conventions (`config/texture_manifest.json` and `world_config.py` are
   the existing precedents to generalize).

**The tempting alternative, and why not to take it first:** starting at M18 (persistence) or M19
(items) is more exciting and directly visible, but both would be built, tested and profiled inside an
environment that cannot be reproduced from the repository, using a broken default test invocation,
with the M16 foundation still uncommitted. If a single milestone must be prioritised over M17, the
defensible order is **M17 then M18**, and never M18 without M17.

**Immediate next actions (all inside M17, none of them gameplay):** create the checkpoint commit and
tag for M16; add the dependency manifest and virtualenv; fix the test invocation so bare `pytest`
exits 0 (remove the stray `tests_final_report.txt` from collection, or configure `testpaths`);
extend `.gitignore`; add CI; write the README. Then M18 designs the save format.

---

## 6. Limitations of this review

- Read-only: no code was executed beyond the test suite, the profilers and configuration inspection.
  Runtime behaviour of gameplay systems was not re-verified — the M16 measurements were spot-checked
  as artifacts, not re-run.
- No rendered-pixel inspection is possible in this environment, so no claim is made about on-screen
  appearance; that gap is itself recorded as a tooling recommendation (G10).
- The absence findings (crafting, NPCs, farming, equipment, audio, world clock) are grep- and
  read-based across `*.py`; they are strong but not a formal proof of absence.
- `scripts/pack_textures.py` determinism was not verified.
- M1–M5 are not documented in `MILESTONES.md` (it begins at M6); this review therefore cannot
  describe their scope, and it does not attempt to reconstruct them.
- The roadmap's milestone *numbering* beyond M17 is a proposal for the owner's approval; the
  dependency analysis stands independently of it.

---

## 7. Follow-up — resolution status on 2026-10-13

Added after the fact by the infrastructure work below. Every finding, status and number above is
preserved unchanged as the record of the repository as it stood on 2026-10-12; nothing here
retroactively rewrites an earlier claim.

Resolved by commit `06a2933` ("pin the verified environment, unblock bare pytest and add Windows CI")
and the preceding M16 checkpoint verification:

| Finding | Status on 2026-10-13 | Evidence |
|---|---|---|
| **G1** — no dependency manifest, unreproducible environment (**blocking**) | **Resolved** for the manifest; still open for a lockfile, README and virtualenv helper | `requirements.txt` pins Python 3.14 / ursina 8.3.0 / panda3d 1.10.16 / numpy 2.4.4 / pytest 9.1.1 / Pillow 12.2.0, and those exact pins installed into a clean CPython 3.14 virtual environment where both test commands passed. |
| **§2.3 / G2** — bare `pytest` from the root exits 2 on `tests_final_report.txt` (**blocking**) | **Resolved** | `pytest.ini` clears pytest's implicit `test*.txt` doctest glob so `.txt` files are never auto-collected, and `tests/test_pytest_collection_health.py` guards it. `python -m pytest -q` now exits 0 with 344 passed; `python -m pytest tests -q` exits 0 with 336 passed. The stray file was not renamed, deleted or ignored on disk. |
| **G2** — no CI workflow | **Added; first GitHub run still unverified** | `.github/workflows/tests.yml` installs `requirements.txt`, runs `compileall` and `pytest` on `windows-latest` with Python 3.14 for every push and pull request. **No GitHub execution has been observed** — only the same three commands were run locally on the verified Windows x64 machine. |
| **§2.4 finding 2** — artifacts record `meta.ursina` as `unavailable` | **Resolved in the harnesses; the recorded artifacts were not regenerated** | `_version()` in `scripts/profile_m16_stutter.py` and `scripts/measure_m16_streaming.py` now reads `importlib.metadata` instead of `module.__version__` and reports ursina **8.3.0**; `tests/test_m16_harness.py` covers both helpers. The existing `config/m16_*.json` files still hold the old `unavailable`/`unknown` values, so the published M16 numbers retain the incomplete provenance described above and re-running the harnesses remains optional. |

Still open — each item below was re-checked by grep or read on 2026-10-13, not assumed:

- **G3 persistence/save:** still absent. No world-state writes exist (`json.dump`, `write_text` and
  `open(..., "w")` appear only in `scripts/` tooling and configuration, never in a root module);
  player edits still live only in the in-memory overlay.
- **G5 item registry / G6 equipment:** unchanged — `inventory.py` still stores `BlockType` stacks and
  `inventory_ui.py` still renders `range(9)` of the declared 27 slots.
- **G7 crafting, construction, farming:** absent — no `recipe|smelt|furnace|craft`,
  `crop|harvest|farm_plot|growth_stage` or item-registry matches outside PIL's `Image.crop`.
- **G8 NPCs/raids, G9 world clock/scheduler:** absent — no `npc|villager|resident|raid|pathfind|enemy`
  and no `world_time|time_of_day|schedule_update` matches in code.
- **G2 remainder:** the per-file `sys.path` boilerplate, an explicit `testpaths` declaration,
  coverage and markers, and moving the root-level `test_world.py` into `tests/` are all still open.
  **M17 has not been started** — this was an M16 follow-up, so the ordering recommendation in §5
  stands unchanged.
- **G10 optional tooling:** unchanged.

The collection defect and the missing manifest — the two defects §5 used to argue M17 must come first
— are now closed. M17's remaining scope (lockfile/README, CI observed green on a real run, shared
fixtures, a documented performance-budget command) is what still justifies it as the next milestone.
