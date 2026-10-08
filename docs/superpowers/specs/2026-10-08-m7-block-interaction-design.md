# M7 — Block Interaction — Architectural Design

> Active milestone: M7. Architectural path.
> Decomposure artifact for brainstorming. Hand off to `writing-plans` after
> user approval. Do not implement until the spec is approved.

## 1. Intent

Introduce basic runtime interaction with the voxel world. The player aims a
raycast from the first-person camera into the voxel world to target a solid
block, a lightweight wireframe highlight shows the targeted block as the camera
moves, the primary mouse button removes the targeted block, and the secondary
mouse button places a new block adjacent to it.

Block interaction must **extend**, not duplicate, existing systems. It reuses
the M1 coordinate system, M2 block data, M3 mesh generation, M4 World
container, M5 terrain/Chunk entities, and M6 player/camera/collision. The
original architecture is preserved: one rendered Chunk = one rendered Ursina
Entity, and the logical Chunk is the authoritative world state. Breaking and
placing blocks regenerate meshes without losing textures/UVs.

## 2. Risk areas

Two pre-existing defects make interaction correctness non-trivial:

1. **Chunk boundary culling is stubbed.** `chunk_mesh.py:217-230`
   `_get_neighbor_block` returns AIR for any coordinate outside the 0..15 local
   range, so inter-chunk occlusion is never detected. A block on a chunk face
   must be handled so both the containing chunk and the neighbor chunk stay
   consistent. The ray and the render rebuild must consult the World across an
   explicit cross-chunk neighborhood, not just local coordinates.
2. **The dirty-chunk signal is unused.** `World.dirty_chunks` is recorded by
   `set_block` but nothing consumes it. Interaction marks a chunk dirty; a
   refresh consumes it.

No data-type risk: use the existing integer block value; selection is the
world-block position, block type, and hit face. Chunk size is 16 and is not a
field on World, so chunk size should be resolved from a stable constant/helper.

## 3. File contract

| File | Milestone | M7 role |
| --- | --- | --- |
| `coordinate_system.py` | M1 | unchanged; world<->chunk<->local conversion |
| `world.py` | M4 | add `dirty`, `set_block`, `refresh`; keep `get_block` |
| `chunk.py` | M2 | unchanged 16³ storage; add per-chunk refresh |
| `chunk_mesh.py` | M3 | inter-chunk neighbor visibility via World |
| `chunk_entity.py` | M5 | unchanged one-Entity-per-chunk signature |
| `player.py` | M6 | add interaction state/input only |
| `block_data.py` | M2 | integer AIR/DIRT/STONE/GRASS/WATER |

- One Entity per rendered chunk; the dirty-chunk registry feeds render refresh.
- The World's only `dirty` bookkeeping is a set of chunk ids pending refresh.
- No chunk/mesh generation lives in the World, and no ray logic lives in the
  player.

## 4. Interaction point

- Origin = camera position (player world position + eye offset), i.e. the player
  camera origin.
- Direction = camera forward (yaw 0 / pitch 0 -> (−1,0,0); pitch +90° ->
  straight down). Length = `MAX_INTERACT_RANGE` (default ≈ 6), or the camera
  origin's interaction range if the player declares one.
- The interaction point = origin + ray_dir · range. Interaction point is
  independent of chunk load state; World block lookup is the source of truth.

## 5. Ray cast

- Walk the ray cell-by-cell from the interaction origin into the voxel world.
- Step along ray_dir; count empty cells; stop at first solid cell (DDA-like).
- Report first solid block's world position (integer), block type, hit face(s),
  and each hit face's neighbor (world) position.
- If a solid block is never reached before the range, report no hit.
- The ray resolves inter-chunk occlusion via the World (see §3, `chunk_mesh.py`).
- Ray uses a chunk size that matches the World (16) so the ray and render agree.

## 6. Block actions

- **Break (left button).** `set_block(AIR)` at the block position; mark the
  affected chunk dirty; the refresh rebuilds the affected chunk and neighbors.
- **Place (right button).** Target the block adjacent to the hit face
  (`pos + face · step`); if that cell is air / a non-solid block,
  `set_block(DIRT)` and mark dirty; else reject.
- **Placement safety.** Reject placement that intersects the player body
  (`can_place(pos) == False`). Reject on player-body overlap. If rejected, block
  data is unchanged.
- **Highlight.** Set the interaction highlight position to the interaction
  position / block; rebuild the existing entity.
- **Ray / highlight / placement position** derive from the camera + World.
- **Interaction point updates once per player update.**

## 7. World refresh contract

```
world.dirty()  -> set(world.dirty_chunks)   # add the mutated cell id
world.refresh() # for each marked cell: rebuild affected chunk(s) + inter-chunk neighbors
```

- `world.dirty()` records mutating the World cell (e.g. setting block to AIR).
- `world.refresh()` rebuilds affected chunk(s) and any neighbor whose visible
  geometry changed, and reports the block set of block interactions.
- Interaction does not write a block-placement state or store a world
  block-selection state; it only reads block data and marks dirty cells.
- No new World block API that existing code relies on; cell update / raycast via
  the World block lookup stay read-only.
- `chunk.refresh()` builds a neighbor map at chunk boundaries with
  `neighbour_map` for inter-chunk face visibility.

## 8. Interaction input

- Interaction press state: left button (break) / right button (place). Two only.
- Update the interaction point each player update from the camera position/look
  and MAX_INTERACT_RANGE.
- The interaction ray traces the World block lookup (§5).

## 9. Persistence

- World cells store `int`; block data is integer.
- World blocks default to a single block type.
- No chunk-selection state inside the World.
- Cell update triggers chunk mesh rebuild.

## 10. Out of scope

- No hotbar, no block-selection UI, no drops, no tools, no crafting, no damage,
  no mobs/nuisence, no water/biome, no world streaming, no dynamic load/unload,
  no persistence/save/load, no multiplayer, no lighting/Occlusion, no advanced
  physics, no LOD, no greedy meshing, no unrelated refactoring.
