# M13 Water Behavior & Fluid Simulation Implementation Plan

> **For agentic workers:** Follow the repository's Superpowers workflow. Read the required skills before starting. Use `subagent-driven-development` or `executing-plans` only if appropriate to the actual environment. For this project, execute tasks sequentially and do not launch parallel subagents.

**Goal:** Add functional voxel water (source + flowing) with vertical-priority flow, deterministic recession, bounded horizontal spread, cross-chunk propagation, dirty-chunk mesh refresh and water internal-face culling — without changing block IDs, textures or the one-mesh-per-chunk architecture.

**Architecture:** Water occupancy stays `BlockType.WATER`. A per-`Chunk` `water_levels` / `water_sources` layer carries flow strength. A headless `WaterSimulation` recomputes affected connected water regions with deterministic source-derived 0-1 BFS. It consumes a `World.changed_blocks` external-edit log and updates the world through `World.set_water`.

**Tech stack:** Python 3.14, NumPy, pytest and Ursina for rendering only. Core flow logic must be Ursina-free and headless-testable.

**Spec:** `docs/superpowers/specs/2026-10-11-m13-water-behavior-design.md`

## Global constraints

- Do not add or change block types. `BlockType` stays `AIR, GRASS, DIRT, STONE, WATER, SAND`.
- Do not modify `config/texture_manifest.json`, `voxel_textures/gen_atlas.png`, `voxel_textures/atlas_map.json`, or any texture.
- Preserve one combined mesh per rendered chunk and one Ursina Entity per rendered chunk.
- Logical `Chunk` block data remains authoritative; block data must not depend on rendering.
- Block data changes go through `World.set_block` / `World.set_water`.
- `World.set_water` must never write to `World.changed_blocks`.
- Flowing levels are derived from sources by path cost; never relax a cell toward `neighbour_level - 1`.
- Horizontal spread is suppressed only when the cell below is loaded `AIR`; `WATER` below is fed at cost 0 and does not suppress spread.
- Execute tasks sequentially. Do not launch parallel subagents.
- Do not change global OpenCode configuration or agent definitions.
- Do not modify production code before the design and plan receive explicit approval.
- Existing test baseline: `python -m pytest tests -q` — previously 96 passed.
- Constants: `MAX_LEVEL = 8`, `SOURCE_LEVEL = 8`, `MAX_HORIZONTAL_SPREAD = 32` (configurable, raised for long-cascade testing), `DEFAULT_MAX_CELLS_PER_TICK = 65536`.

## Review focus

Each of the following failure modes must have a test in its owning task:

1. A source above empty space fills the cell below and every empty cell down to the blocker; water above existing water spreads horizontally.
2. Recession drains unsupported water and equal-level neighbours cannot sustain each other.
3. Removing a source cannot be undone by stale metadata; breaking a former water cell must not resurrect it.
4. A solid block adjacent to water retains its visible face; only the water face is culled.
5. Simulation writes do not re-enter `changed_blocks`; a saturated tick neither applies a partial update nor loops indefinitely.
6. Work budgets cover flood, solve and commit preparation.
7. An edit to an unvisited cell invalidates a stale job.
8. A relevant chunk availability change invalidates an active job.
9. Atomic publication does not apply a region cell-by-cell over multiple visible frames.

---

## File structure

### Create

- `water.py` — `WaterSimulation`, `solve_water_view`, pure water rules; no Ursina import.
- `tests/test_water_rules.py` — pure solver and simulation tests.
- `tests/test_water_chunk_integration.py` — World/Chunk integration, cleanup, dirty tracking and cross-chunk behavior.
- `tests/test_water_mesh_culling.py` — water/solid face-culling decisions and opaque/UV regression.
- `tests/test_water_interaction.py` — player interaction hooks.
- `tests/test_water_texture_compatibility.py` — texture/atlas compatibility assertions.

### Modify

- `chunk.py` — water level/source layer, accessors and `clear_water`.
- `world.py` — `changed_blocks`, `water_edit_version`, loaded query, water accessors, `set_water`, `set_block` metadata cleanup and atomic publication support if required by the approved design.
- `chunk_mesh.py` — cull water-water internal faces in `_add_exposed_faces_to_split`.
- `terrain_generation.py` — mark generated lake cells as sources.
- `main.py` — instantiate, seed and tick `WaterSimulation`.
- `player.py` — only if required to route player edits correctly.
- `MILESTONES.md` — M13 completion report in Task 11 only.

### Not modified

`block_data.py`, `config/texture_manifest.json`, `scripts/pack_textures.py`, all textures, `raycast.py` and `inventory.py`, except if inspection reveals a genuine blocker requiring approval.

---

## Task 1 — Chunk water storage layer

**Files**
- Modify: `chunk.py`
- Test: `tests/test_water_chunk_integration.py`

**Interfaces produced**

- `Chunk.get_water_level(x, y, z) -> int`
- `Chunk.set_water_level(x, y, z, level) -> None`
- `Chunk.get_water_source(x, y, z) -> bool`
- `Chunk.set_water_source(x, y, z, source) -> None`
- `Chunk.clear_water(x, y, z) -> None`

### Step 1 — Write failing tests

```python
def test_chunk_water_layer_defaults_and_roundtrip():
    c = Chunk(0, 0, 0)
    assert c.get_water_level(1, 2, 3) == 0
    assert c.get_water_source(1, 2, 3) is False

    c.set_water_level(1, 2, 3, 5)
    c.set_water_source(1, 2, 3, True)

    assert c.get_water_level(1, 2, 3) == 5
    assert c.get_water_source(1, 2, 3) is True


def test_chunk_water_level_clamped_and_clear_water():
    c = Chunk(0, 0, 0)

    c.set_water_level(0, 0, 0, 99)
    assert c.get_water_level(0, 0, 0) == 8

    c.set_water_level(0, 0, 0, -3)
    assert c.get_water_level(0, 0, 0) == 0

    c.set_water_level(0, 0, 0, 4)
    c.set_water_source(0, 0, 0, True)
    c.clear_water(0, 0, 0)

    assert c.get_water_level(0, 0, 0) == 0
    assert c.get_water_source(0, 0, 0) is False
```

### Step 2 — Confirm failure

Run:

`python -m pytest tests/test_water_chunk_integration.py -q`

Expected: failure because the accessors do not exist yet.

### Step 3 — Implement

Initialize `water_levels` as an `int8` array and `water_sources` as a boolean array with dimensions matching `self.blocks`.

Implement the accessors. Clamp levels to `0..8`. `clear_water` resets level and source metadata.

### Step 4 — Verify

Run the same targeted test command. Expected: PASS.

### Step 5 — Commit

```bash
git add chunk.py tests/test_water_chunk_integration.py
git commit -m "feat(m13): add per-chunk water level/source layer"
```

---

## Task 2 — Deterministic water solver

**Files**
- Create: `water.py`
- Test: `tests/test_water_rules.py`

**Interfaces produced**

- `MAX_LEVEL`, `SOURCE_LEVEL`, `MAX_HORIZONTAL_SPREAD`
- `is_water(block_type) -> bool`
- `is_passable(block_type) -> bool`
- `is_empty(block_type) -> bool`
- `solve_water_view(view, seeds, max_horizontal_spread=32) -> dict[tuple[int,int,int], int]`

The solver consumes a `WaterView` with `is_loaded`, `get_block` and `is_source`. `World` implements this interface later; tests use a fake view.

### Step 1 — Write failing tests

```python
# Vertical fill
def test_source_over_empty_space_fills_cell_below(): ...
def test_source_over_multi_cell_drop_fills_entire_column_to_floor(): ...
def test_vertical_flow_has_priority_over_horizontal(): ...
def test_downward_flow_into_air_suppresses_horizontal(): ...

# Horizontal range
def test_horizontal_step_decrements_from_seven(): ...
def test_horizontal_spread_stops_at_configured_limit(): ...
def test_horizontal_flow_reaches_configurable_default_range(): ...
def test_solid_and_unloaded_are_boundaries(): ...

# Existing-water expansion
def test_horizontal_spread_over_existing_water(): ...
def test_water_surface_spreads_above_lake(): ...
def test_horizontal_flow_when_supported_by_solid(): ...
def test_below_unloaded_allows_horizontal_and_creates_no_chunk(): ...

# Recession and multiple sources
def test_removing_only_source_drains_all_derived(): ...
def test_two_adjacent_sources_are_stable(): ...
def test_water_supplied_by_second_source_remains(): ...
def test_overlapping_source_influence_uses_minimum_distance(): ...
def test_equal_level_neighbours_do_not_sustain_each_other(): ...
def test_solver_is_deterministic_and_reaches_fixed_point(): ...
```

### Step 2 — Confirm failure

Run:

`python -m pytest tests/test_water_rules.py -q`

Expected: failure because `water.py` does not exist.

### Step 3 — Implement

Implement the pure solver without importing Ursina.

The algorithm must:

1. Discover the existing water component associated with the supplied seeds.
2. Identify permanent sources in the affected region.
3. Traverse using source-derived 0-1 BFS.
4. Allow downward propagation into loaded `AIR` or `WATER` at cost 0.
5. Allow horizontal propagation into loaded `AIR` or `WATER` at cost 1, unless the current cell's below is loaded `AIR`.
6. Allow water above existing water to spread horizontally.
7. Limit horizontal cost to the configurable `max_horizontal_spread` (default 32).
8. Never query an unloaded cell or create a chunk.
9. Clamp reachable levels to a minimum of 1 so long horizontal runs and falls
   at the range edge never dry out from level exhaustion.
10. Return a deterministic mapping of desired water levels.

Cascade coverage: horizontal flow beyond the original 7, long vertical falls
(no distance cap), falls at the range edge, multi-terrace cascades across chunk
boundaries, and repeated block edits recomputing an active cascade.

Key assertions:

- A source at `(0,4,0)` above air at `(0,3,0)` and `(0,2,0)`, with solid at `(0,1,0)`, produces level 8 for the entire vertical column.
- The supported cell at `(0,2,0)` can spread to `(1,2,0)` at level 7.
- A cell at horizontal cost 8 is absent.
- Removing the only source produces an empty derived solution.
- A source with `WATER` below still spreads horizontally.
- A source with loaded `AIR` below fills downward and suppresses horizontal spread.
- A source with solid below can spread horizontally.

### Step 4 — Verify

Run:

`python -m pytest tests/test_water_rules.py -q`

Expected: PASS.

### Step 5 — Commit

```bash
git add water.py tests/test_water_rules.py
git commit -m "feat(m13): add deterministic source-derived water solver"
```

---

## Task 3 — Resumable simulation jobs and edit handling

**Files**
- Modify: `water.py`
- Test: `tests/test_water_rules.py`

**Interfaces produced**

- `WaterSimulation(world, max_cells_per_tick=DEFAULT_MAX_CELLS_PER_TICK)`
- `pending_seeds`
- `active_job`
- `enqueue(x, y, z)`
- `on_block_changed(x, y, z)`
- `consume_changes()`
- `seed_all_sources()`
- `tick() -> int`
- `has_pending_work() -> bool`

### Step 1 — Write failing tests

```python
# Scheduling and edit log
def test_consume_changes_drains_and_clears_log(): ...
def test_sim_generated_changes_do_not_enter_changed_blocks(): ...
def test_small_budget_completes_over_multiple_ticks(): ...
def test_budget_units_respected(): ...

# Deterministic results
def test_deterministic_equivalence_with_one_shot_solver(): ...
def test_no_visible_partial_region_updates(): ...
def test_job_commits_only_when_complete(): ...

# External edits during jobs
def test_external_edit_during_job_is_not_lost_and_commits_latest_state(): ...
def test_unrelated_edits_restart_safely(): ...
def test_invalidation_on_unvisited_edit_during_flood(): ...
def test_invalidation_on_source_toggle_during_solve(): ...
def test_invalidation_on_block_occupancy_change_during_preparation(): ...
def test_invalidation_across_chunk_boundary_during_flood(): ...

# Recession and source removal
def test_source_removal_splits_components_and_drains_unsupported_components(): ...
def test_drain_across_multiple_loaded_chunks_marks_all_dirty(): ...
def test_water_reachable_from_another_source_remains(): ...
def test_stale_metadata_cannot_resurrect_drained_water(): ...
def test_two_adjacent_sources_are_stable(): ...
```

### Step 2 — Confirm failure

Run:

`python -m pytest tests/test_water_rules.py -q`

Expected: failure because `WaterSimulation.tick` does not exist.

### Step 3 — Implement resumable jobs

Maintain a deduplicated FIFO pending-seed queue and at most one active job.

Persist flood, region-discovery and solve state between ticks.

`consume_changes()` must transfer all external edit coordinates and their six neighbours to the pending queue.

Each tick may process at most `max_cells_per_tick` work units. One traversal work unit is one queue/frontier pop, including neighbour inspection and discovered-node insertion.

### Step 4 — Implement safe invalidation

Capture `water_edit_version` at job start.

Before publication, compare the captured version with the current version. On mismatch, discard the job and restart from the latest authoritative state.

Test invalidation caused by:

- Occupancy changes.
- Source creation/removal.
- Edits to cells not yet visited.
- Relevant chunk load/unload changes.
- Cross-chunk changes.
- Edits during commit preparation.

Simulation-internal writes must not invalidate their own job.

A global version is acceptable; unrelated edits may restart a job. Add a deterministic test proving the restart does not lose pending edits and that the final result matches a fresh calculation after edits stop.

### Step 5 — Resolve bounded work and atomic publication before proceeding

Do not implement a final cell-by-cell region commit if it can exceed the per-tick budget or expose a partial region.

First inspect the existing `World` and `Chunk` storage to determine whether the complete prepared state can be published atomically.

- Prepare the complete result privately over bounded work units.
- Publish the complete region through one logical atomic operation.
- Keep the old state visible until publication.
- Ensure block lookups and rendering observe a consistent published state.
- Invalidate the prepared result if the captured world version is stale.

If this requires a world-level published-state representation or another architectural change, document the exact interface and its effect on chunk-authoritative data before implementing it.

**Blocking rule:** if the existing architecture cannot provide both bounded preparation and atomic publication, stop and report the blocker. Do not weaken either requirement without approval.

### Step 6 — Verify

Run:

`python -m pytest tests/test_water_rules.py -q`

Expected: PASS.

### Step 7 — Commit

```bash
git add water.py tests/test_water_rules.py
git commit -m "feat(m13): add resumable water simulation jobs"
```

---

## Task 4 — World integration, cleanup and dirty discipline

**Files**
- Modify: `world.py`
- Test: `tests/test_water_chunk_integration.py`

**Interfaces produced**

- `World.changed_blocks`
- `World.water_edit_version`
- `World.is_loaded(...) -> bool`
- `World.get_water(...) -> int`
- `World.is_source(...) -> bool`
- `World.set_water(...) -> bool`
- `World.set_block(...)` metadata cleanup

### Step 1 — Write failing tests

```python
def test_set_block_records_changed_blocks(): ...
def test_set_block_non_water_clears_water_metadata(): ...
def test_set_block_air_where_water_was_does_not_resurrect(): ...
def test_placing_solid_into_water_clears_level_and_source(): ...
def test_drain_clears_source_flag(): ...
def test_stale_source_flag_on_air_is_ignored(): ...
def test_dry_to_wet_marks_chunk_and_boundary_neighbours_dirty(): ...
def test_wet_to_dry_marks_dirty(): ...
def test_level_only_change_marks_nothing_dirty(): ...
def test_set_water_on_unloaded_chunk_is_noop(): ...
def test_set_water_below_y0_is_noop(): ...
def test_set_water_does_not_append_to_changed_blocks(): ...
def test_set_block_increments_water_edit_version(): ...
def test_set_water_does_not_increment_water_edit_version(): ...
def test_source_toggle_increments_external_edit_version(): ...
def test_relevant_chunk_availability_change_increments_version(): ...
```

### Step 2 — Confirm failure

Run:

`python -m pytest tests/test_water_chunk_integration.py -q`

Expected: failure because the edit log, version and water accessors do not exist.

### Step 3 — Implement

Add `changed_blocks` and `water_edit_version` to `World`.

Extend `set_block` to clear water metadata, preserve dirty tracking, record the edit and increment the version when occupancy changes.

Implement `is_loaded`, `get_water`, `is_source` and `set_water`.

`set_water` must not create unloaded chunks, must not write to the external edit log and must not invalidate its own simulation job.

Implement source metadata changes and relevant chunk-availability version changes through explicit, testable paths.

### Step 4 — Verify

Run:

`python -m pytest tests/test_water_chunk_integration.py -q`

Expected: PASS.

### Step 5 — Commit

```bash
git add world.py tests/test_water_chunk_integration.py
git commit -m "feat(m13): add World water accessors and dirty discipline"
```

---

## Task 5 — Cross-chunk propagation

**Files**
- Test: `tests/test_water_chunk_integration.py`
- Modify `water.py` or `world.py` only if required.

### Step 1 — Write failing tests

```python
def test_water_flows_across_chunk_boundary(): ...
def test_boundary_water_marks_both_chunks_dirty(): ...
def test_unloaded_neighbour_is_not_created(): ...
def test_recession_crosses_loaded_chunk_boundary(): ...
def test_boundary_availability_change_invalidates_active_job(): ...
```

### Step 2 — Confirm failure

Run:

`python -m pytest tests/test_water_chunk_integration.py -q`

Expected: failure because cross-chunk propagation or invalidation is incomplete.

### Step 3 — Implement

Use world coordinates and the existing chunk-coordinate semantics.

Ensure that:

- Loaded neighbouring chunks are traversed.
- Unloaded chunks remain boundaries.
- No chunk is created by water propagation.
- Boundary occupancy changes dirty every affected chunk.
- Relevant availability changes invalidate active jobs.

### Step 4 — Verify

Run the targeted test command. Expected: PASS.

### Step 5 — Commit

```bash
git add water.py world.py tests/test_water_chunk_integration.py
git commit -m "feat(m13): support water propagation across chunk boundaries"
```

---

## Task 6 — Water and solid face-culling decisions

**Files**
- Modify: `chunk_mesh.py`, function `_add_exposed_faces_to_split`
- Test: `tests/test_water_mesh_culling.py`

### Step 1 — Write failing tests

```python
def test_water_water_internal_faces_culled(): ...
def test_water_face_against_solid_is_culled(): ...
def test_solid_face_against_water_is_rendered(): ...
def test_water_face_against_air_is_rendered(): ...
def test_opaque_and_uv_orientation_unchanged(): ...
```

Expected geometry:

- Two adjacent water cells do not render their shared internal faces.
- Water next to stone does not render its face hidden by the solid.
- Stone next to water retains its visible face.
- Water next to air renders the exposed face.
- Existing opaque geometry and M12 UV orientation remain unchanged.

### Step 2 — Confirm failure

Run:

`python -m pytest tests/test_water_mesh_culling.py -q`

Expected: adjacent water emits internal faces.

### Step 3 — Implement

In `_add_exposed_faces_to_split`, add a transparent-pass rule that culls a face when the neighbouring block is the same water type.

Do not modify the opaque pass. Do not change atlas mapping, UVs, textures or entity architecture.

### Step 4 — Verify

Run the targeted test command. Expected: PASS.

### Step 5 — Commit

```bash
git add chunk_mesh.py tests/test_water_mesh_culling.py
git commit -m "feat(m13): cull internal water faces"
```

---

## Task 7 — Lake source generation and startup regression safety

**Files**
- Modify: `terrain_generation.py`
- Test: `tests/test_water_chunk_integration.py`

### Step 1 — Write failing tests

```python
def test_generated_lake_top_layer_is_sources_and_lower_is_not(): ...
def test_generated_lake_steady_state_stable_across_ticks(): ...
def test_startup_does_not_create_new_water_outside_initial_lake(): ...
def test_non_water_terrain_unchanged_for_fixed_seed(): ...
```

### Step 2 — Confirm failure

Run:

`python -m pytest tests/test_water_chunk_integration.py -q`

Expected: lake source metadata is not initialized.

### Step 3 — Implement

For every lake cell, initialize water level 8.

Set `water_source=True` only for cells at `y == lake_level`. Lower lake cells must remain derived water.

Preserve lake geometry and all non-water terrain for a fixed seed.

### Step 4 — Verify

Run the targeted test command. Expected: PASS.

### Step 5 — Commit

```bash
git add terrain_generation.py tests/test_water_chunk_integration.py
git commit -m "feat(m13): mark only top lake layer as water sources"
```

---

## Task 8 — Player interaction hooks

**Files**
- Test: `tests/test_water_interaction.py`
- Modify: `player.py` / `main.py` only where required.

### Step 1 — Write failing tests

```python
def test_break_beside_water_enqueues_and_flows(): ...
def test_place_into_water_is_rejected_and_no_item_consumed(): ...
def test_place_into_air_marks_changed_blocks(): ...
def test_break_and_place_still_regenerate_mesh(): ...
```

### Step 2 — Confirm failure

Run:

`python -m pytest tests/test_water_interaction.py -q`

Expected: edits do not yet trigger the intended water update behavior.

### Step 3 — Implement

Wire the existing player edit path into `World.changed_blocks` and the simulation's `consume_changes()` / `tick()` sequence.

Rejected placement must return before consuming inventory quantity.

Do not make water selectable, breakable, placeable or collectable.

### Step 4 — Verify

Run the targeted test command. Expected: PASS.

### Step 5 — Commit

```bash
git add tests/test_water_interaction.py player.py main.py
git commit -m "feat(m13): connect player edits to water simulation"
```

---

## Task 9 — Texture and atlas compatibility tests

**Files**
- Test: `tests/test_water_texture_compatibility.py`

No production texture or atlas changes are permitted.

### Step 1 — Write tests

```python
def test_manifest_still_maps_water_to_blocks_water(): ...
def test_water_asset_is_16x16_rgba(): ...
def test_atlas_includes_water_tile(): ...
def test_minetest_water_textures_documented_as_incompatible(): ...
```

The compatibility test documents that the existing Minetest stills are opaque 128×128 images and animated textures are 128×1024 eight-frame strips, incompatible with the current static single-frame atlas path.

### Step 2 — Confirm failure

Run:

`python -m pytest tests/test_water_texture_compatibility.py -q`

Expected: the test file does not exist.

### Step 3 — Implement tests only

Add assertions for the current texture mapping, dimensions, alpha channel and atlas inclusion.

Do not modify production assets or the packer.

### Step 4 — Verify

Run the targeted test command. Expected: PASS.

### Step 5 — Commit

```bash
git add tests/test_water_texture_compatibility.py
git commit -m "test(m13): pin water texture compatibility decision"
```

---

## Task 10 — Main wiring and startup smoke test

**Files**
- Modify: `main.py`
- Test: `tests/test_water_chunk_integration.py`

### Step 1 — Write failing test

```python
def test_headless_sim_smoke(): ...
```

Build a headless world, seed the sources, run a bounded number of ticks and assert expected levels and face counts.

### Step 2 — Confirm failure

Run:

`python -m pytest tests/test_water_chunk_integration.py -q`

Expected: the water simulation smoke test is missing.

### Step 3 — Wire `main.py`

After terrain generation:

1. Instantiate `WaterSimulation(world)`.
2. Call `seed_all_sources()` once.
3. Each frame, consume external changes.
4. Advance the simulation by the configured budget.
5. Refresh affected chunk meshes when published occupancy changes.

Keep `main.py` minimal. Do not run a second simulation or bypass the world API.

### Step 4 — Verify

Run the targeted test command. Expected: PASS.

### Step 5 — Commit

```bash
git add main.py tests/test_water_chunk_integration.py
git commit -m "feat(m13): seed and tick water simulation"
```

---

## Task 11 — Verification and M13 completion report

**Files**
- Modify: `MILESTONES.md` — M13 report only.

### Step 1 — Automated test evidence

Run:

`python -m pytest tests -q`

Record the exact command, final count and result. The previous baseline was 96 passing tests.

### Step 2 — Startup and smoke evidence

Run `python main.py` for a bounded interval, for example 12 seconds.

Confirm the window is created, chunks/entities build and no exception is raised. Record the headless water-level and face-count smoke output.

This proves integration only, not visual correctness.

### Step 3 — Visual verification

Attempt to launch and inspect the running game.

If rendered pixels cannot be inspected in the environment, report visual verification as **not performed**. Do not make visual-correctness claims based on automated tests or startup success.

### Step 4 — Write the completion report

Update only the M13 status/report in `MILESTONES.md`.

Include:

- Files changed.
- Water behavior decisions.
- Automated test evidence.
- Startup/smoke evidence.
- Visual verification status.
- Atomic publication and work-budget results.
- Known limitations.
- The existing truncated-section limitation.

Do not repair unrelated milestone documentation.

### Step 5 — Commit

```bash
git add MILESTONES.md
git commit -m "docs(m13): add water behavior completion report"
```

---

## Final self-review checklist

Before declaring M13 complete, verify:

- [ ] Source-derived 0-1 BFS is deterministic.
- [ ] Vertical fill and horizontal suppression rules match D2.
- [ ] Horizontal range is limited to seven cost units.
- [ ] Source removal drains unsupported water.
- [ ] Multiple sources remain stable.
- [ ] Stale metadata cannot resurrect water.
- [ ] `set_water` does not re-enter `changed_blocks`.
- [ ] External occupancy, source and relevant chunk-availability changes invalidate active jobs.
- [ ] Unrelated edits restart safely without losing pending seeds.
- [ ] Flood, solve and preparation respect the work budget.
- [ ] Publication is atomic and does not apply visible cell mutations over multiple frames.
- [ ] No stale job can publish.
- [ ] Cross-chunk propagation and recession work.
- [ ] Correct chunks are marked dirty and refreshed.
- [ ] Water-water internal faces are culled.
- [ ] Solid faces beside water remain visible.
- [ ] Texture and atlas assets remain unchanged.
- [ ] One combined mesh and one Ursina Entity per rendered chunk remain true.
- [ ] All M1–M12 tests pass.
- [ ] Automated, smoke and visual evidence are reported separately.
- [ ] `MILESTONES.md` truncation is documented but not repaired as unrelated work.

**Stop after the plan is approved and completed. Do not start M14 or unrelated refactoring.**
