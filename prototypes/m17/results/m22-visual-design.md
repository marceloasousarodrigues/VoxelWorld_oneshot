# M22 — Lush fantasy wilderness and medieval settlements

Status: **implemented and verified** (2026-10-19). This is the visual and
behavioural contract for the M22 Godot work under `prototypes/m17/godot/`. It
defines what the milestone means by "convincing", how it is reproduced, and what
evidence must exist before the work is called complete. It does not replace
`m18-visual-design.md`; it extends that material/geometry contract with a
second, architectural vocabulary. Implementation evidence is recorded in
`m22-progress.md`.

## 1. Art direction

One coherent identity, built from two references without copying either:

**Lush handcrafted fantasy**

- Rich but controlled greens, bright blue sky, warm earth, neutral stone.
- Layered terrain silhouettes: grass over dirt, exposed stone, readable slopes.
- Several tree silhouettes with full, irregular crowns (oak, pine, birch,
  blossom) instead of one repeated green blob.
- A dense but navigable understory: grass tufts, ferns, bushes, three flower
  colours, fallen wood, boulders.
- A winding path that belongs to the terrain rather than a grey slab dropped on
  it.

**Medieval fantasy architecture**

- Reusable, predominantly block-based vocabulary: stone foundation, timber
  frame, plank infill, glass windows, door, stepped tiled roof with eaves and a
  ridge.
- Settlements must feel inhabited: lanterns with real warm light, work areas
  with crafting table/furnace, storage, barrels, fences, a market stall.
- A stone path, a small plank bridge, fences and gates around the buildings.

The world stays voxel-first. Logical blocks remain authoritative for collision,
harvesting, chunk ownership, fluid state and saves. Custom meshes are limited to
one-cell details (stations, barrels, lanterns, fences) and crossed-quad
decoration; they do not replace terrain.

## 2. Palette and material rules

- One tile per metre; every cube face still samples one `Texture2DArray` layer
  at an exact integer (`UV2.x`, no `+0.5`).
- Grass and foliage: sage / forest green; no fluorescent green. Blossom crowns
  are a restrained pink accent, not a second global palette.
- Soil: warm umber. Stone: neutral cool grey with readable darks. Roof tiles:
  muted terracotta. Timber: warm brown with dark structural beams. Lantern
  light: amber/orange.
- Keep the existing low-frequency world-space variation and baked vertex AO;
  do not add per-pixel noise that hides block edges.
- New textures are generated in-repo by `tools/generate_m22_textures.py`; no
  external download and no new licence obligation.

## 3. Terrain and vegetation rules

- Terrain generation stays deterministic and remains the existing height/biome
  system. M22 changes surface decoration and tree variety, not the terrain
  algorithm.
- Biome decoration is deterministic per column. Forest/plains receive flowers
  and bushes at a bounded rate; snow/savanna keep their identity.
- Tree library: oak (rounded), pine (conical), birch (slender pale trunk,
  lighter/airier crown) and a rare blossom tree in temperate biomes.
- Decoration is non-solid crossed quads (or a single non-solid cell) and never
  changes the block underneath. Flowers must keep their own hue rather than
  inheriting a heavy green tint.
- Architecture blocks are normal voxel blocks so they can be mined, placed,
  saved and streamed like everything else.

## 4. Architecture rules

- The reusable settlement module is data in `StructureDB` (ASCII layers) plus
  shared placement helpers. The showcase stamps the same definitions; it must
  not be a one-off model.
- `timber_cottage`: stone foundation, timber-framed walls with plank infill,
  glass windows, two-block door, jettied/overhanging stepped roof with a ridge,
  and a furnished interior (table, furnace, chest, lantern).
- `market_stall`: posts, counter, barrels and a tiled roof; usable as a work
  area in the showcase.
- A fence line and gate use the fence block. A small plank bridge with log
  supports crosses the showcase stream.
- Lantern blocks are custom one-cell models with an emissive pane. A light
  manager creates a small pool of warm `OmniLight3D`s near the player at night
  and dims them by day; it must not create one node per lantern in the world.

## 5. Lighting and atmosphere

- Daytime: brighter, more saturated blue sky than the baseline, readable
  sunlit foliage, gentle blue-green haze instead of a white wash. Fog density
  must not bleach the middle distance.
- Dusk/night: warm lantern pools and readable silhouettes; no crushed black.
- Keep ACES tonemapping and four-split shadows. A subtle glow pass is allowed
  for emissive lantern panes but must be measured.
- Solve material/geometry problems in daylight; lighting is not a mask.

## 6. Reproducible showcase

Extend `VisualTestArena` at the existing deterministic site
`(72, 65, -88)` and keep it behind `--visual-test`. It is isolated from
autosave, creatures, NPCs and raids.

Required contents:

1. A wider clearing with layered grass/dirt/stone edges.
2. A winding path from the open south side to the cottage door, with a stone
   apron and a branching garden path.
3. The `timber_cottage` from the reusable definition, plus an exterior crafting
   area (table, furnace, chest, barrels).
4. A `market_stall` and fence/gate line.
5. A stream extension with a plank bridge and log supports.
6. Several tree species, bushes, flowers, ferns and boulders framing the view.
7. Lantern posts with real warm lights; at least one lantern inside the cottage.
8. Wide, close material, vegetation, architecture and dusk viewpoints.

Fixed viewpoints are added to `--visual-test`:
`normal` (default approach through the south gate), `wide` (east 3/4 view of
the clearing, forest and sky; capture at render distance 5), `close` (path,
flowers and cottage materials), `cottage` (front facade), `garden` (flower bed
and path), `bridge` (deck, water and rails), and `dusk` (lanterns; use
`--time=0.50`). `--time=0.75` reuses `dusk` for the night capture.

## 7. Procedural integration

- New blocks, vegetation rules and the `timber_cottage`/`market_stall`
  definitions are part of normal world generation, not showcase-only.
- Existing structure placement rules still apply (one per 96-block region,
  deterministic, biome/slope sited, complete across chunk borders).
- A structure stamped at runtime for the showcase uses the same definition as
  generated structures.
- The world hash will change because decoration and tree variety change. This
  is expected; determinism (same seed, same order-independent voxels) must
  remain true and is re-verified.

## 8. Acceptance criteria

M22 is complete only when all of these are true:

1. `timber_cottage` and `market_stall` are valid `StructureDB` definitions and
   appear in normal deterministic generation within a bounded scan.
2. A deterministic `--visual-test` showcase contains the cottage, path, fence,
   bridge, crafting area, lanterns, at least three tree species and flowers.
3. `--visual-test` remains isolated from saves/creatures/NPCs/raids.
4. The new blocks are defined, placeable, breakable with sensible drops,
   correctly layered/culled, and survive save/load and chunk unload/reload.
5. Lantern lights are bounded and do not leak nodes when chunks unload.
6. Automated unit and integration suites pass with updated assertion counts;
   pre-existing failures, if any, are listed separately.
7. Headless smoke runs twice with the same world hash, proving decoration is
   deterministic.
8. Windowed captures are inspected for: no texture swim, no missing/inverted
   faces, no floating props, no dark shadow slabs, no obvious repetition, and
   a coherent day/dusk look.
9. Performance is measured against `m22-before-{settle,look,walk}.json` at
   radius 4, seed 17017. Report p50/p95/p99, 1 % low, draw calls and the
   worst frame. Any material regression is either fixed or explained.
10. Documentation and verified Git savepoints exist; unrelated user changes
    (including the pre-existing `tests/test_m16_streaming_budget.py` edit and
    generated evidence files) are preserved.

## 9. Out of scope

- Replacing the renderer, engine or voxel architecture.
- Fully furnishing and populating the entire world with settlements.
- Doors that open/close, NPC trading, city management, weather.
- Photorealism, screen-space global illumination, heavy post-processing.
- External paid assets or new third-party dependencies.
