# Project status

Updated: 2026-10-22

## Canonical project

- **Engine:** Godot 4; the active project is [`godot/project.godot`](godot/project.godot).
- **Source snapshot:** `VoxelWorld_m34`, branch `codex/m34-canopy-composition`, commit
  `a2791430f2acd33507ebc24a8b87c5aaa8ff055e` (`Document M33-M37 Godot milestones`).
- The Godot project was promoted from `godot` to the top-level `godot/`
  folder. Its project-relative `res://` layout is preserved.
- The previous Python + Ursina runtime and its Python tests, scripts, dependencies, settings,
  and source textures are retained under `archive/ursina/` as deprecated reference material.

## Milestones

- M33–M36 are recorded as complete in the milestone reports; M37 is the current forest
  composition milestone and is **partial**.
- M37 generator v8 creates larger irregular clearings and improves canopy separation.
  The normal gameplay capture still shows a continuous tree line on the right hillside,
  so the forest composition work is not complete. Global forest coverage is also lower
  than the preceding generator version. See
  [`prototypes/m17/results/godot/m37-report.md`](prototypes/m17/results/godot/m37-report.md).

## Validation

The consolidated copy was opened with Godot 4.7.2 and validated after the folder move:

- Unit suite: `M17_TESTS_PASS 2923 assertions`.
- Integration suite: `M17_INTEGRATION_PASS 463 assertions` (run with
  `-- --straight-to-game`).
- Regression: `M17_REGRESSION_PASS assertions=52`.

The source M37 report also records two stable smoke runs with matching world and mesh
hashes. Those visual/runtime captures are retained as evidence; a new graphical smoke
capture was not performed during consolidation.
