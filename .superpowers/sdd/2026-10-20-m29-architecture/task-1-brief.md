# M29 Builder Brief — Medieval Architectural Building System

ACTIVE MILESTONE: M29

## Goal

Replace the bulky stepped M28 roof silhouette with a believable medieval gable roof
(slate/shingle, thin eaves, proper ridge, closed gable ends, stone chimney) and add a
small reusable player-placeable architectural palette for timber framing, stonework,
windows, shutters, doors and details. Upgrade the normal-game starter cottage and the
existing player-authored showcase so the result is visible in ordinary gameplay, not
only in a test arena.

Reference image (primary visual target):
`prototypes/m17/references/m29-architecture/01-world-style.png`,
`02-village-style.png`, `03-castle-style.png`.

Baseline capture (same camera to reuse after the change):
`prototypes/m17/results/godot/m29-before-cottage.png`
Command:
```powershell
$godot = 'C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe'
& $godot --path godot -- --capture --capture-name=m29-after-cottage.png --look=38,-8 --settle=16 --render-distance=5 --hide-hud --time=0.28
```

## Rules

- Work only under `godot/` plus M29 documentation/evidence paths.
- Do not modify the original Python/Ursina implementation.
- Append new block IDs after `BlockDB.STAIR` (88); never renumber or reorder existing IDs.
- Preserve existing saves and M23–M28 behavior. Keep chunk/mesh/streaming invariants.
- Keep the work incremental: roof + shaped pieces first, run focused tests, capture and
  compare against the reference, then facade/details and the larger structure.
- Use TDD for new behavior: add a failing focused test, then implement.
- Preserve unrelated modified/untracked files in the worktree.

## Required block set (append-only)

Use these names/ids unless a concrete implementation problem requires an equivalent set:

| ID | Constant | Purpose |
|---:|---|---|
| 89 | `PLASTER` | warm lime-plaster wall infill |
| 90 | `DARK_TIMBER` | dark structural oak |
| 91 | `STONE_WALL` | coursed warm-grey medieval stone |
| 92 | `TIMBER_BRACE` | plaster panel with a diagonal dark brace |
| 93 | `SLATE_TILE` | slate/shingle roof cube |
| 94 | `SLATE_STAIR` | stair-shaped slate roof piece |
| 95 | `SLATE_SLAB` | half-height slate eave/edge piece |
| 96 | `SLATE_RIDGE` | custom triangular ridge cap |
| 97 | `WINDOW` | custom framed window (wood frame + glass + mullion) |
| 98 | `SHUTTER` | louvered shutter cube |
| 99 | `CHIMNEY` | custom masonry chimney block |
| 100 | `FINIAL` | small non-solid ridge finial |
| 101 | `FLOWER_BOX` | small non-solid planter with flowers |

`DEFINED_COUNT` and `COUNT` must be updated. All new blocks must drop themselves, be
mineable with the correct tool family, be placeable from inventory, and have recipes
reachable from existing materials.

## Roof design (priority 1)

Implement a reusable gable-roof helper (e.g. in `scripts/game/medieval_kit.gd`) used by
the starter cottage, the M25 build demo and the M28 final showcase. For a wall footprint
`x=-hx..hx`, `z=-hz..hz`, wall top at `y=eave`:

- eave row at `z=±(hz+1)`, `y=eave`, full `x=-hx-1..hx+1`: `SLATE_SLAB` (thin overhang)
- slope rows for `step=0..hz-1`: `z=±(hz-step)`, `y=eave+step`:
  `SLATE_STAIR`, orientation `0` on +Z and `2` on -Z (top half toward the ridge)
- ridge row at `z=0`, `y=eave+hz-1`: `SLATE_RIDGE`, ridge axis along X
- gable infill at `x=±hx`: fill air cells from eave to ridge with `PLASTER`,
  `DARK_TIMBER` posts/beams and `TIMBER_BRACE` diagonals
- optional finials at the two ridge ends; stone `CHIMNEY` replacing roof cells on the
  rear slope and rising above the ridge
- use `SLATE_*` textures (grey-blue slate with warm shadow), not the old plank faces

Do not leave full-cube ridge blocks or plank-textured stairs as the roof surface.

## Mesher/shape/integration requirements

- Extend `BlockShape` with slab support (bottom and upside-down/top half) and make
  `SLATE_STAIR` use the existing stair mask.
- Generalize `set_block_state` validation from "STAIR only" to any orientable block and
  update `SaveManager` row validation the same way. Existing saves stay valid.
- Generalize `VoxelPlayer.rotate_placement`, `placement_orientation` and the HUD build
  prompt from stair-only to orientable pieces. `SLATE_RIDGE` must rotate its long axis;
  roof stairs/slabs keep the existing 0..7 convention.
- Pass block orientation into custom-model emission for `SLATE_RIDGE` only (other custom
  models are symmetric). Emit a triangular ridge prism with correct winding/normals,
  UVs, textures and collision. Keep everything in the chunk mesh (no per-block nodes).
- New custom models must not cull neighbouring faces incorrectly. Solid models keep
  full-cell collision consistent with existing custom blocks.
- New textures go through a new `tools/generate_m29_textures.py` (procedural, in-repo),
  with `assets/texture_sources.json` manifest entries and `TextureLibrary` grade entries
  where appropriate. Do not download third-party art.

## Demonstration / visual work

- Rebuild `BuildDemo._build_cottage` using the new palette: stone plinth, plaster/timber
  framing with braces, framed windows and shutters, dark timber door surround, slate
  roof with eave overhang, ridge, gable infill, stone chimney, interior props/lantern.
- The starter house uses this cottage automatically and must remain editable/saveable.
- Update the M28 longhouse, market stalls and keep roofs to the new slate roof helper,
  and add coherent details (shutters, chimney, finials) where they fit. Keep the castle
  stone/crenellated identity and all existing gameplay.
- Add a focused M29 demo capture mode only if the existing build/final demo views cannot
  show the larger structure adequately; prefer reusing `--build-demo=cottage` and
  `--final-demo=wide|village|castle`.

## Tests

Add/update Godot tests, at minimum:

- block IDs are appended after 88; new blocks defined, solid/opaque/custom flags sane;
  drops and tool classes correct
- slab and roof-stair masks, orientation and collision geometry (half faces)
- mesher emits custom window/chimney/ridge geometry with collision where required
- ridge orientation round-trips through `set_block_state` and save/load validation
- craft recipes for the new palette validate and are craftable at the right station
- starter house and build/final demos contain slate roof stairs, ridge, eaves, windows,
  shutters and chimney; all pieces are mineable
- existing M23–M28 suites still pass unchanged where behavior was not intentionally
  changed; update assertions for intentionally replaced roof blocks

Run during iteration:
```powershell
& $godot --headless --path godot --script res://scripts/tests/run_tests.gd
```
At the milestone gate also run integration, smoke and determinism commands from
`prototypes/m17/results/godot-progress.md`.

## Report

Return: files changed/created, block IDs, tests added/run with counts, runtime/capture
commands, remaining limitations, and any criterion not verified. Do not claim success
from tests alone; the roof silhouette and material result must be checked in a capture.
