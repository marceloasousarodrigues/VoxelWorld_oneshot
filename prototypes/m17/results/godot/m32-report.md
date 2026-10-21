# M32 — Playable Landscape Quality Pass

## Status

**PASS with documented limitations.** A continuous winding river is now demonstrated in
runtime captures, the forest canopy and riverbanks are visibly closer to the primary
reference, the thin dark vertical lines are explained and fixed, generator versions 0/1/2
remain byte-identical, and matched performance measurements show no frame-time regression
at the cost of more foliage geometry and draw calls.

## Preflight

- Original checkout: `C:/Users/Admin/Documents/Projects/VoxelWorld_oneshot`, branch `main`,
  HEAD `32a104d` (Restore M29 terrain generation for legacy saves). It was dirty before this
  work (modified `tests/test_m16_streaming_budget.py` and many untracked evidence files);
  it was not modified.
- Confirmed in history: M29 architecture `b3cf7f8`, M30 merge `fae27be`, legacy-save
  remediation `32a104d`, and M31 `f3bc6eb` (`codex/m31-voxel-wilderness-visuals`).
- Work branch: `codex/m32-landscape-quality`, worktree
  `C:/Users/Admin/Documents/Projects/VoxelWorld_m32`, created from `f3bc6eb`.
- The existing M30/M31 worktrees and their uncommitted generated `.import`/`.uid` files were
  not modified by this work.
- Godot 4.7.2 stable mono, Vulkan, NVIDIA GeForce RTX 3080.
- Ursina/Python sources were not touched.

## What was found

### The river existed; M31 never looked at it

The generator probe at the M31 camera and the M31 density probe only sampled a 256-block
window and classified water by biome. A carved river column becomes `OCEAN`/`BEACH` because
its height drops below sea level, so the probe's `BED` and `wet_inland` counters excluded the
very columns the carve had created. The M31 captures also pointed away from the channel.

A dedicated probe (`m32_river_probe.gd`) found inland water components once the search was
widened to 512 blocks, including a long reach around `x=80, z=152`. A runtime capture from
`80, 92, 180` looking north shows the river continuously for the first time. The river was
therefore **present, exposed and correctly levelled in v2**, but it was not demonstrated and
its banks were visually poor (a broad pale sand apron and terraced canal sides).

### The thin dark vertical lines were the block target marker

Matching the M31 camera (`60.5, 71, -30.5`, yaw 0, pitch -2) reproduced two thin dark vertical
lines. Capturing the same frame with `--no-target-marker` removed them. The cause is
`VoxelPlayer`'s 1 m wireframe target box: when the camera is inside a solid cell (fly capture
or standing in a leaf cell), `VoxelRay` reports a hit at distance zero and the box surrounds
the camera, so two of its vertical edges project as full-frame hairlines. This is geometry,
not a chunk seam, material or shadow artifact.

### The water surface had a blocky bed pattern

The matched water view showed a strong checkerboard from the transparent water revealing the
blocky riverbed. This is a material issue, not chunk seams. The shader was changed to reach
opaque water closer to shore and to reduce the atlas grain; the matched before/after is
`m32-water-before.png` / `m32-water-after.png`.

## What changed

Generator version 3 (`WorldGen.M32_VERSION`) is used only by new worlds. Versions 0, 1 and 2
keep their exact output.

- **River corridor**: the proven v2 carve is retained. M32 replaces the all-sand apron with a
  narrow waterline sand/gravel edge, a mixed grass/gravel/soil lip, and a wider tree-free
  corridor. Banks are no longer painted one flat material.
- **Hills and mountains**: hills use the detail field's natural one-block steps instead of
  2-block stair bands. The M31 3-block stepped shelves remain above the snow line
  (`M32_MOUNTAIN_FLOOR = SEA + 46`), preserving the snowy summits. A ±2-block deterministic
  detail field breaks long straight terrace edges. Upper mountain slopes below the snow line
  now carry grass and a conifer treeline instead of a bare grey belt.
- **Forest**: highland plains/savanna become forest above `SEA + 8`, clearings are slightly
  smaller, canopy candidates are denser (measured 13.3% tree coverage over forest columns,
  versus 13.7% in M31), clearings still stay open, and broadleaf crowns are larger, lower on
  the trunk, more varied in height, and more heavily trimmed at the corners. Trees on slopes
  get a small height lift so the crown clears the uphill tread. Pines are less frequent in
  lowland forest and no longer receive the slope lift.
- **Foliage tint**: tint is now version-aware through `ChunkData.terrain_version`, so v3 can
  use a brighter lime canopy without changing the palette of v0/v1/v2 chunks or fixtures.
- **Spawn**: `VoxelPlayer.spawn_on_column` skips natural leaves and trunks, so the new dense
  canopy cannot spawn the player on top of a tree. This was a real regression found during
  the performance run (spawn y=101 on leaves); it now spawns on the ground at y=81.
- **Target marker**: the outline is hidden when the hit is closer than 0.75 m, which removes
  the full-frame hairline artifact without changing normal targeting.
- **Water material**: `depth_scale` 7.0 → 2.5, `alpha_deep` 0.985 → 1.0, atlas grain
  0.025 → 0.008. Shallow edges remain translucent; the riverbed checkerboard is gone.

## Runtime captures

Matched settings: seed `17017`, generator v3, render radius 6, `--fly`, `--hide-hud`,
`--settle=25`, 1280×720, Vulkan, frozen clock at 0.28. Files are in
`prototypes/m17/results/godot/`.

| Evidence | Camera | File |
|---|---|---|
| Hero: winding river, forest and banks | `80,92,180`, yaw 0, pitch −25 | `m32-river-hero.png` |
| Ground-level river and bank transitions | `80,72,160`, yaw 0, pitch −8 | `m32-river-ground.png` |
| Cottage, forest opening and canopy | `80,72,160`, yaw 90, pitch −8 | `m32-forest-clearing.png` |
| Dense canopy and a clearing | `224,92,288`, yaw 75, pitch −24 | `m32-canopy.png` |
| Snow-capped mountains retained | `76,140,-40`, yaw 180, pitch −14 | `m32-mountain-vista.png` |
| M31 baseline at the hero camera | `80,92,180`, yaw 0, pitch −25 | `m32-before-river-0.png` |
| Thin-line artifact before | `60.5,71,-30.5`, yaw 0, pitch −2 | `m32-artifact-before.png` |
| Same view after marker fix | `60.5,71,-30.5`, yaw 0, pitch −2 | `m32-artifact-after.png` |
| Water bed pattern before | `80,72,160`, yaw 0, pitch −8, old shader | `m32-water-before.png` |
| Water after shader fix | same camera, current shader | `m32-water-after.png` |

The hero capture shows the river bending through forested banks with sand/gravel waterline,
green and soil terraces, exposed stone, and trees on both sides. It is a normal elevated
gameplay view, not a test fixture or a decorative water patch.

## Performance

Matched camera `80,92,180`, seed 17017, render radius 6, fly, RTX 3080. Two runs per build;
the table reports both runs and the median, because single FPS samples vary by several percent
on this machine.

| Metric | M31 baseline | M32 final | Change |
|---|---|---|---|
| Look avg FPS (runs) | 448.9 / 496.5 (472.7) | 439.8 / 482.9 (461.3) | −2.4% median |
| Look p95 frame ms | 2.823 / 2.270 (2.55) | 2.906 / 2.327 (2.62) | +2.7% median |
| Look p99 frame ms | 3.222 / 2.843 (3.03) | 3.286 / 2.895 (3.09) | +2.0% median |
| Look 1% low FPS | 173.5 / 282.4 | 168.0 / 292.4 | within run variance |
| Look worst frame ms | 30.0 / 13.9 | 30.1 / 13.1 | unchanged |
| Look avg draw calls | 665 / 666 | 711 / 721 | +8.2% |
| Settle avg FPS | 296.3 / 332.2 (314.3) | 305.5 / 331.7 (318.6) | +1.4% median |
| Settle p95 / p99 ms | 6.54 / 10.74 | 6.29 / 11.18 | within variance |
| Settle worst frame ms | 36.8 / 24.5 | 40.6 / 30.4 | +4–6 ms |
| Settle draw calls | 740.6 / 741.6 | 756.5 / 760.2 | +2.3% |
| Loaded / wanted at settle | 791 / 791 | 791 / 791 | equal |
| Queued at settle / in flight | 0 / 0 | 0 / 0 | equal |
| Generation total (settle) | 1176 / 1182 ms | 1153 / 1176 ms | equal |
| Mesh total (settle) | 10.19 / 10.26 s | 10.74 / 11.44 s | +5.4% to +11.5% |

Hero-view geometry at settle: 305,242 faces (M31) → 355,349 faces (M32), +16.4%. At the
ground river view: 544,309 → 618,533 faces (+13.6%), draw calls 782 → 864 (+10.5%),
primitives 572,438 → 828,426 (+44.7%). The extra primitives are the cost of the denser,
larger canopy. Frame pacing is unchanged because the streamer's per-frame budgets absorb the
work; the visible regression is GPU geometry and mesh-build time, not average/worst frame
time. No canopy or river feature was removed to hide this trade-off.

## Verification

Commands run from the M32 worktree with
`Godot_v4.7.2-stable_mono_win64.exe`:

| Suite | Command | Result |
|---|---|---|
| Unit | `--headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd` | `M17_TESTS_PASS 2578 assertions`, exit 0 |
| Integration | `--headless --path prototypes/m17/godot --script res://scripts/tests/run_integration.gd -- --straight-to-game` | `M17_INTEGRATION_PASS 463 assertions`, exit 0 |
| Regression | `--headless --path prototypes/m17/godot --script res://scripts/regression.gd` | `M17_REGRESSION_PASS assertions=52`, exit 0 |
| Smoke ×2 | `--headless --path prototypes/m17/godot -- --straight-to-game --seed=17017 --render-distance=6 --quit-after=30` | both `world_hash=5495814557571427371`, `faces_hash=3989804036799183035`, `faces=468281`, exit 0 |
| River probe | `--headless ... --script res://scripts/tests/m32_river_probe.gd -- --version=3 --radius=512 --step=4` | 150 inland water components; largest `x=-304..-192 z=4..136`, height 55..61 |

Focused tests in `test_m32_landscape.gd`:
- version 3 is current and supported; version 4 is rejected;
- v0/v1/v2 region hashes are pinned to `3214517825889907206`,
  `5947596836865492245`, `8397584315617538769`; v3 is distinct;
- v2 still uses 3-block terraces, v3's mountain belt keeps 3-block shelves, and v3 hills are
  not quantised into 2-block bands;
- the river reach at `z=152` has a continuous exposed water surface, returns grass and soil
  outside the sand edge, and is not an all-sand apron;
- canopy coverage is 13.3% (dense but not a carpet), crowns span at least five blocks in x, z
  and y, and the M32 tree pad is 8;
- the target marker is hidden at 0 and 0.5 m, shown at 0.75 m and 3 m, and can be disabled;
- spawn ground skips leaves and trunks but accepts grass and a player-built plank surface.

Generator fingerprint (`wilderness_probe.gd --fingerprint`, seed 17017):

| Version | Hash |
|---|---|
| 0 (M29) | `3214517825889907206` |
| 1 (M30) | `5947596836865492245` |
| 2 (M31) | `8397584315617538769` |
| 3 (M32) | `8299345369586821846` |

Version 0/1/2 is unchanged; a v2 save still records and restores the M31 generator. Save
loading, player edits, block IDs, chunk streaming, collision, water propagation and the M29
build systems are covered by the existing suites.

## Limitations

- **Cascades**: the river is a sea-level water body, so there is no terrain-supported drop to
  place a cascade on. No cascades were added; adding them would require a water-level or
  waterfall carve that is outside the smallest justified fix.
- **Far-field**: the horizon is still open ocean/sky beyond the streamed world. This is an
  explicit M32 exclusion and was not implemented.
- **Canopy close-up**: from directly above, overlapping crowns still read as a continuous
  green carpet in places, although ground-level and middle-distance views show distinct
  stepped crowns and clearings.
- **Mountain silhouette**: the snow cap is a stepped white plateau rather than a sharp peak;
  the M31 stepped profile was retained rather than redesigned.
- **Performance variance**: FPS varies by several percent between runs. The matched medians
  and both runs are reported; single-run figures are not used as proof.
- **Water A/B**: the water before/after is a same-camera, same-seed comparison with only the
  shader change between the captures; the rest of the build is current.
- The `--no-target-marker` option remains as a capture diagnostic; it is not required for the
  fix.

## Files

- `prototypes/m17/godot/scripts/core/world_gen.gd` (v3)
- `prototypes/m17/godot/scripts/core/chunk_data.gd` (per-chunk generator version)
- `prototypes/m17/godot/scripts/core/chunk_mesher.gd` (version-aware tint)
- `prototypes/m17/godot/scripts/game/voxel_player.gd` (marker distance, spawn ground)
- `prototypes/m17/godot/scripts/game/game.gd` (`--no-target-marker` diagnostic)
- `prototypes/m17/godot/shaders/voxel_water.gdshader`
- `prototypes/m17/godot/scripts/tests/test_m32_landscape.gd` (new)
- `prototypes/m17/godot/scripts/tests/m32_river_probe.gd` (new diagnostic)
- `prototypes/m17/godot/scripts/tests/{run_tests,run_integration,test_generation,test_m31_wilderness,test_m29_architecture,test_final_demo,wilderness_probe}.gd`
- `prototypes/m17/results/godot/m32-*.png`, `m32-matched-*.json`, this report

Generated `.import`/`.uid` files from the Godot import pass are not part of the commit.
