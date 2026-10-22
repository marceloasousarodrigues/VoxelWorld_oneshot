# ARCHITECTURE.md

> **Historical scope:** This document records the Python + Ursina architecture from
> milestones M1–M16. The canonical game project is now Godot 4 in [`godot/`](godot/);
> this document describes the deprecated reference implementation in
> [`archive/ursina/`](archive/ursina/) and does not constrain the Godot architecture.

# VoxelWorld Architecture

## Purpose

This document defines the stable technical architecture of VoxelWorld.

It describes how the main systems relate to each other and defines architectural invariants that should remain stable across milestones.

It does not define the current milestone.

Current milestone scope and acceptance criteria are defined in `MILESTONES.md`.

---

## 1. Core Architecture

VoxelWorld is a voxel-based world composed of blocks organized into Chunks.

The fundamental relationship is:

World → Chunks → Block Data → Chunk Mesh Generation → Rendering

The architecture separates:

- world coordinates;
- chunk coordinates;
- local block coordinates;
- block data;
- mesh generation;
- rendering.

Block data must not depend on rendering.

Mesh generation consumes block data and produces renderable geometry.

Rendering consumes generated chunk meshes.

---

## 2. World

The World represents the complete logical voxel world currently loaded by the application.

The World is responsible for:

- managing Chunks;
- locating Chunks;
- converting world coordinates to Chunk/local coordinates;
- providing access to block data through the appropriate Chunk;
- coordinating world generation when required.

The World should not contain rendering-specific block data.

---

## 3. Chunks

The world is divided into Chunks.

The current Chunk dimensions are:

16 × 16 × 16 blocks.

A Chunk is identified by its integer Chunk coordinates.

A Chunk stores the logical block data for its local region.

Chunk coordinates are separate from world coordinates.

A Chunk should not require an Ursina Entity merely to exist as logical world data.

---

## 4. Block Data

Block data represents the logical contents of the voxel world.

Current block types include:

- AIR
- GRASS
- DIRT
- STONE

AIR represents an empty block.

Block data is independent from rendering.

The logical state of a block must be usable without requiring an Ursina Entity.

---

## 5. Coordinate Systems

VoxelWorld uses separate coordinate systems.

### World Coordinates

Represent positions in the complete voxel world.

### Chunk Coordinates

Identify which Chunk contains a block.

### Local Block Coordinates

Identify the block position inside a Chunk.

For a Chunk of size 16:

0 ≤ local coordinate < 16

Conversion between world and Chunk/local coordinates must work correctly for negative world coordinates.

Negative coordinates must use mathematical floor behavior rather than truncation toward zero.

---

## 6. Chunk Mesh Generation

Each Chunk can generate a mesh representing its visible voxel geometry.

The mesh generator operates on Chunk block data.

At minimum, the mesh generation system uses exposed-face culling.

Faces between two solid neighboring blocks should not be rendered.

Mesh generation occurs independently from the rendering layer.

The logical Chunk data remains the authoritative representation of the world.

---

## 7. Rendering

Rendering is performed using Ursina.

The intended architecture uses one rendered Ursina Entity for each rendered Chunk.

The Entity represents the rendered form of its corresponding Chunk.

The Entity receives the mesh generated from that Chunk.

The logical Chunk remains independent from the Entity.

The rendering layer must not become the authoritative storage for block data.

---

## 8. World Generation

Terrain generation produces logical block data.

Generation should operate deterministically when a deterministic generator is required by the active milestone.

Generation must populate Chunk block data rather than directly constructing the final rendered representation.

The generated logical data is subsequently consumed by Chunk mesh generation.

---

## 9. Rendering Pipeline

The intended pipeline is:

1. World determines the Chunks to generate or render.
2. Chunks are populated with block data.
3. Chunk mesh generation processes the block data.
4. A renderable mesh is produced for each rendered Chunk.
5. The corresponding Ursina Entity receives that mesh.
6. Ursina renders the Entities.

This separation allows world logic and rendering logic to evolve independently.

---

## 10. Application Entry Point

The application has a minimal entry point responsible for assembling the required systems and starting the application.

The entry point should not become a container for unrelated game logic.

As the project grows, responsibilities should remain separated into appropriate modules.

---

## 11. Current Scope Boundaries

The architecture does not require every future game system to exist immediately.

Features such as:

- player movement;
- inventory;
- crafting;
- mobs;
- water;
- advanced lighting;
- persistence;
- multiplayer;
- streaming;
- LOD;
- physics;

must only be introduced when required by an explicit milestone.

Their absence from the current implementation does not constitute an architectural failure unless required by the active milestone.

---

## 12. Architectural Invariants

The following invariants should be preserved:

1. Block data is independent from rendering.
2. Chunks are the primary spatial organization of block data.
3. Chunk dimensions remain 16 × 16 × 16 unless explicitly changed by a milestone.
4. World coordinates, Chunk coordinates, and local coordinates remain conceptually separate.
5. Negative coordinate conversion must use floor semantics.
6. Mesh generation consumes logical block data.
7. Rendering consumes generated Chunk meshes.
8. Rendering must not become the authoritative representation of world state.
9. One rendered Chunk corresponds to one rendered Ursina Entity unless explicitly changed by a future architectural milestone.
10. The application entry point remains minimal.
11. The set of loaded Chunks is a bounded active region around the player: Chunks
    within the configured streaming distance are loaded, and Chunks beyond the
    configured retention distance are unloaded. Loading and unloading never leave
    duplicate Chunks, duplicate entities, or stale rendered resources.

---

## 13. Chunk Lifecycle & Streaming (M16)

VoxelWorld streams Chunks around the player so exploration is not limited to a
fixed pre-generated region.

Two responsibilities are separated:

- **Policy** — `ChunkStreamer` (`chunk_streaming.py`) computes the desired and
  retained Chunk sets from the player's position, schedules loads nearest-first
  and unloads farthest-first, and bounds the work performed per frame.
- **Lifecycle** — `World.load_chunk` / `World.unload_chunk` keep the logical
  `chunks` registry authoritative and consistent, create or release the rendered
  entity for a Chunk, re-dirty loaded neighbours whose boundary faces changed,
  and invalidate stale water work.

### Staged loading (M16 stutter fix)

A streamed load is split across two frames so no single frame carries both the
data and the mesh work:

- **Stage A** (`World.begin_chunk_load`): registers the Chunk, generates terrain
  and vegetation, replays the player-edit overlay, and creates the Chunk's entity
  and transparent child **with no geometry**. The logical Chunk is complete and
  authoritative as soon as this returns — collidable, raycastable and editable —
  and the one-entity-per-loaded-Chunk invariant holds from this moment on.
- **Stage B** (`World.finish_chunk_load`): builds the mesh into that existing
  entity, re-dirties the loaded neighbours whose boundary faces changed, and
  bumps the water edit version.

A streamer frame performs one *kind* of load work, never both. `World.load_chunk`
remains the synchronous single-frame form and is behaviourally unchanged;
`tests/test_m16_staged_load.py` pins the two paths to the same resulting world
state. **A loaded Chunk's data may therefore be authoritative one frame before its
geometry exists — only rendering lags, never collision, raycasts or edits.**

Streaming is horizontal: only the ground layer (`chunk_y == 0`) carries terrain,
water and vegetation. The desired set is a Chebyshev radius of Chunks around the
player's Chunk; retention is a larger radius that provides hysteresis.

Settings are centralized in `config/world_config.json` and exposed through
`world_config.py`; no streaming distance or per-frame limit is hard-coded.

### Persistence policy

Chunk state is classified explicitly:

- **Regenerable** (recomputed deterministically from `(seed, coordinates)`): base
  terrain, lake water, and vegetation. Regenerating a Chunk reproduces it
  byte-for-byte.
- **Authoritative** (kept in an in-memory overlay in `World`): player block edits
  and decorations cleared by an edit. These survive an unload/re-entry.
- **Derived** (re-solved from sources after re-entry): water spread.
- **Transient**: dirty sets, pending edits, water job state, and rendered
  entities.

Unloading a Chunk therefore removes it from the registry and releases its
rendered resources without losing player modifications. Persistent on-disk
save/load of the world is **not** part of this architecture; it would be a
separate milestone.
